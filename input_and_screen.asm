;-----------------------------------------------------------------------------
;
; (c) 2026 Jouni 'Mr.Spiv' Korhonen
;
;

		DEVICE	ZXSPECTRUM128
		SLDOPT 	COMMENT WPMEM, LOGPOINT, ASSERTION

; High byte of the screen location. If page 7 is used then this would be 0xc0.
SCREEN_HIGH		equ		0x40

		MODULE	input_and_screen


;-----------------------------------------------------------------------------
; Update one line length input buffer. The buffer allows simple editing and
; moving left and right with cursor. The buffer is in 'insert' mode.
;
; Sysvar buffer flags (VARS.input_buf_flags) are modified accordingly:
;   BUF_DIRTY_F is set if any editing of the buffer too place.
;               Also moving just cursor does marks buffer dirty, if the
;               cursor position changes.
;
; Input:
;  IX = ptr to 256 bytes aligned sysvars (STRUCT VARS)
;
; Returns:
;  None
;
; Trashes:
;  A, BC, DE, HL
;
update_input_buffer:
		; Return if the same key is kept pressed.
		ld		a,(ix+zxmon.VARS.key_raw_pressed)
		cp		(ix+zxmon.VARS.key_raw_previous)
		jr nz,	.different_raw_code
		; Check first key repeat threshold is passed
		dec		(ix+zxmon.VARS.key_rep_timer1)
		ret nz
		; Ok.. make sure we we get here next time as well..
		inc		(ix+zxmon.VARS.key_rep_timer1)
		; is between keys repeat timer expired?
		dec		(ix+zxmon.VARS.key_rep_timer2)
		ret nz
		jr		.repeat_or_new_key
		;
.different_raw_code:
		ld		(ix+zxmon.VARS.key_rep_timer1),zxmon.KEY_REP_TIMER1
.repeat_or_new_key:
		ld		(ix+zxmon.VARS.key_rep_timer2),zxmon.KEY_REP_TIMER2
		ld		(ix+zxmon.VARS.key_raw_previous),a
		; Check for special keys. These include:
		;  - caps shift + '5' i.e. cursor left
		;  - caps shift + '8' i.e. cursor right
		;  - caps shift + '0' i.e. delete
		;  - enter
		cp		zxmon.KEY_CURSOR_LEFT
		jr nz,	.not_left
		ld		a,(ix+zxmon.VARS.input_cur_oldx)
		and		a
		ret z
		dec		a
		ld		(ix+zxmon.VARS.input_cur_newx),a
		set		zxmon.BUF_DIRTY_F,(ix+zxmon.VARS.input_buf_flags)
		ret

.not_left:
		cp		zxmon.KEY_CURSOR_RGHT
		jr nz,	.not_right
		ld		a,(ix+zxmon.VARS.input_cur_oldx)
		cp		(ix+zxmon.VARS.input_buf_end)
		ret nc
		cp		zxmon.MAXX-1
		ret nc
		inc		a
		ld		(ix+zxmon.VARS.input_cur_newx),a
		set		zxmon.BUF_DIRTY_F,(ix+zxmon.VARS.input_buf_flags)
		ret

.not_right:
		cp		zxmon.KEY_ENTER	
		jr nz,	.not_enter
		;
		; Add terminating \0
		;
		push	ix
		pop		hl
		ld		l,(ix+zxmon.VARS.input_buf_end)
		ld		(hl),0
		set		zxmon.BUF_ENTER_F,(ix+zxmon.VARS.input_buf_flags)
		ret

.not_enter:
		cp		zxmon.KEY_DELETE
		jr nz,	.not_delete
		; Delete a charater from the input buffer
		ld		b,0
		ld		a,(ix+zxmon.VARS.input_cur_oldx)
		cp		b
		ret z
		ld		c,a
		push	ix		; JIK optimize
		pop		hl
		add		hl,bc
		push	hl
		pop		de
		dec		de
		ld		a,(ix+zxmon.VARS.input_buf_end)
		sub		c
		jr z,	.skip_buffer_delete_move
		ld		c,a
		ldir

.skip_buffer_delete_move:
		; Move the cursor left and shorten the input buffer
		dec		(ix+zxmon.VARS.input_cur_oldx)
		dec		(ix+zxmon.VARS.input_cur_newx)
		dec		(ix+zxmon.VARS.input_buf_end)

		; Mark buffer dirty i.e. later print it again from
		; input_cur_oldx to input_buf_end
		set		zxmon.BUF_DIRTY_F,(ix+zxmon.VARS.input_buf_flags)

		; remove the last character.. since this won't necessarily be part
		; of the characters to print when entire buffer is reprinted.
		; also, make sure input buffer ends with NIL
		ld		a,' '
		ld		(de),a
		ret

.not_delete:
		; Update the input buffer and the single editing line.
		ld		a,(ix+zxmon.VARS.key_cooked)

		; Another sanity check. The cooked keycode can be zero, which means
		; it is a non-printable. Caps shift or symbol shift alone and enter
		; fall into this category, for example.
		and		a
		ret z

		; Check if we can add more input. Last input buffer position is reserved
		; for the cursor, so only MAXX-1 charaters can be in the buffer.
		ld		d,a
		ld		a,(ix+zxmon.VARS.input_buf_end)
		cp		zxmon.MAXX-1
		ret z

		; Make space for the new character. Move input buffer from cursor oldx to
		; buffer end + , and insert the new character to cursor oldx position 
		; D = cooked keycode
		push	ix
		pop		hl
		ld		b,0
		ld		c,a
		add		hl,bc
		sub		(ix+zxmon.VARS.input_cur_oldx)
		ld		c,a
		ld		a,d
		push	hl
		pop		de
		dec		hl		; Does not affect flags
		jr z,	.skip_buffer_insert_move
		lddr

.skip_buffer_insert_move
		;
		; DE = insert position
		;  A = new character
		; Insert the new character
		ld		(de),a

		; Update cursor position and buffer size
		;inc		(ix+zxmon.VARS.input_cur_oldx)
		inc		(ix+zxmon.VARS.input_cur_newx)
		inc		(ix+zxmon.VARS.input_buf_end)

		; Mark buffer dirty..
		set     zxmon.BUF_DIRTY_F,(ix+zxmon.VARS.input_buf_flags)
		ret

;-----------------------------------------------------------------------------
; Print input buffer (if it is dirty) and update cursor positional variables.
; Print position is fixed to the last line of the screen (MAXY-1).
; If enter-key was pressed then the entire screen is also scrolled up by
; one line (and input buffer is reset as well).
;
; Input:
;  IX = ptr to 256 bytes aligned sysvars (STRUCT VARS)
;
; Returns:
;  None
;
; Trashes:
;  A, BC, DE, HL
;
print_input_buffer:
		bit		zxmon.BUF_ENTER_F,(ix+zxmon.VARS.input_buf_flags)
		jr nz,	.enter

		; Has buffer content changed?
		bit     zxmon.BUF_DIRTY_F,(ix+zxmon.VARS.input_buf_flags) 
		ret z

		; Cursor has moved or enter was pressed.. replace the character in the old cursor
		; location to make sure it is cleared.
.enter:
		res		zxmon.BUF_DIRTY_F,(ix+zxmon.VARS.input_buf_flags)
		ld		a,(ix+zxmon.VARS.input_buf_end)
		ld		c,(ix+zxmon.VARS.input_cur_oldx)
		ld		e,c
		sub		c
		jr z,	.empty_buffer
		ld		d,zxmon.MAXY-1
		ld		b,0
		push	ix
		pop		hl
		add		hl,bc
		ld		b,a
		; Print existing buffer
		call	print_at

.empty_buffer:
		; print from buf_end to buf_pend with spaces
		ld		a,(ix+zxmon.VARS.input_buf_pend)
		ld		e,(ix+zxmon.VARS.input_buf_end)
		sub		e
		jr c,	.longer_buffer
		inc		a
		ld		b,a
		ld		d,zxmon.MAXY-1
.print_spaces:
		push	bc
		push	de
		ld		a,' '
		call	print_at_char
		pop		de
		pop		bc
		inc		e
		djnz	.print_spaces
.longer_buffer:
		bit		zxmon.BUF_ENTER_F,(ix+zxmon.VARS.input_buf_flags)
		call nz,scroll_screen_up_and_reset_buffer

		; Fix counters
		ld		a,(ix+zxmon.VARS.input_cur_newx)
		ld		(ix+zxmon.VARS.input_cur_oldx),a
		ld		a,(ix+zxmon.VARS.input_buf_end)
		ld		(ix+zxmon.VARS.input_buf_pend),a
		ret


;-----------------------------------------------------------------------------
; Scroll entire screen up by one line including the input buffer content.
; After scrolling the input buffer is reset.
;
; Inputs:
;
; Returns:
;  None
;
; Trashes:
;  A, BC, DE, HL
;
scroll_screen_up_and_reset_buffer:
		; Reset cursor position, clear buffer and scroll screen
		res		zxmon.BUF_ENTER_F,(ix+zxmon.VARS.input_buf_flags)

		; Scroll screen up by one row
		ld		de,0
		ld		bc,((zxmon.MAXY-1) << 8)|32
		;ld		c,32
		;ld		b,zxmon.MAXY-1
		call	scroll_up
		
		xor		a
		ld		(ix+zxmon.VARS.input_cur_newx),a
		ld		(ix+zxmon.VARS.input_buf_end),a
		ret

blink_cursor:
		; Later this check will be different. In a proper imolementation
		; the coounter is decreased in an interrupt, not in this 
		; functions.
		dec		(ix+zxmon.VARS.input_cur_timer)
		ret nz

		ld		(ix+zxmon.VARS.input_cur_timer),zxmon.BLINK_T
		ld		d,5+((zxmon.MAXY-1)*6)
		ld		e,(ix+zxmon.VARS.input_cur_newx)
		call	calculate_xy_addr_x
		ld		de,0111110000000000b
		jr z,	.no_shift
.shift_loop:
		srl		d
		rr		e
		dec		a
		jr nz,	.shift_loop
.no_shift:
		ld		a,(hl)
		xor		d
		ld		(hl),a
		inc		l
		ld		a,(hl)
		xor		e
		ld		(hl),a
		ret


;-----------------------------------------------------------------------------
;
; Keyboard scanning routine
;
; Input:
;  IX = ptr 256 bytes aligned to VARS.
;
; Return 
;  A = charater as xynnnnnn, where
;      x = 1 if shift has been pressed
;      y = 1 if sym has been pressed
;      n = 1 if a mapped kay has been pressed
;
; Trashes:
;  BC,DE,HL
;
;
scan_keys:
		ld		d,0
		ld		hl,raw_keymap
		ld		(ix+zxmon.VARS.key_raw_pressed),d
		ld		(ix+zxmon.VARS.key_cooked),d
		ld		bc,0xfefe

.io_port_loop
		in		a,(c)
		cpl
		ld		e,a
		push	bc
		ld		b,5
		xor		a

.key_scanning_loop:
		srl		e
		jr nc,	.not_pressed
		ld		a,(hl)
		bit		7,a
		jr z,	.not_caps_shift
		set		7,d
.not_caps_shift:
		bit		6,a
		jr  z,	.not_symbol_symbol
		set		6,d
.not_symbol_symbol:
		and		00111111b
.not_pressed:
		inc		hl
		djnz	.key_scanning_loop
		pop		bc
		and		a
		jr z,	.next_port
		ld		(ix+zxmon.VARS.key_raw_pressed),a
.next_port:
		rlc		b
		jr c,	.io_port_loop
		ld		a,(ix+zxmon.VARS.key_raw_pressed)
		or		d
		ld		(ix+zxmon.VARS.key_raw_pressed),a
		;and		01111111b
		ld		d,0
		ld		e,a
		add		hl,de

		ld		a,(hl)
		ld		(ix+zxmon.VARS.key_cooked),a
		ret

;-----------------------------------------------------------------------------
;
;
; Returns:
;  C_flag = 0 if key was pressed, and  A = 0
;  C_flag = 1 if no key was pressed, and  A = 1
;
; Trashes:
;  None
;
scan_caps_shift_for_break:
		push	bc
		ld		bc,0xfefe
		in		a,(c)
		rrca
		jr nc,	.user_abort
		;
		ld		b,0x7f
		in		a,(c)
		rrca
		rrca
		jr nc,	.user_abort
		;
		ld		a,1
		pop		bc
		ret
		;
.user_abort:
		xor		a
		pop		bc
		ret


;-----------------------------------------------------------------------------
;
; Input:
;  IX = ptr 256 bytes aligned to VARS
;
; Return:
;  A  = argc
;  D  = IXH
;  H  = IXH 
;
; Trashes:
;  BC,DE,HL
;
; Note:
;  VARS.input_buf is modified so that each ARGV[n] string ends with NIL.
;
tokenize_input_buffer:
		ld		d,ixh
		ld		h,d
		ld		l,zxmon.VARS.input_argv
		xor		a
		ld		c,a
		ld		e,a
		ld		(ix+zxmon.VARS.input_argc),a
		; HL = ptr to input_argv
		; DE = ptr to input_buf
		ld		b,(ix+zxmon.VARS.input_buf_end)
		cp		b
		jr z,	.parse_exit
		; B = VARS.input_buf_end
		; C = 0 = ARGC
		; eat space characters
.parse_line_loop_main:
		ld		a,(de)
		cp		' '
		jr z,	.eat_space
		ld		(hl),e
		inc		c
		inc		l
		jr		.eat_non_space
		; eat non-space characters
.parse_line_loop:
		ld		a,(de)
		sub		' '
		jr z,	.eat_space
.eat_non_space:
		inc		e
		djnz	.parse_line_loop
		jr		.parse_exit
.eat_space:
		ld		(de),a
		inc		e
		djnz	.parse_line_loop_main
.parse_exit:
		ld		a,c
		; Insert the last input buffer index into ARGV table
		; For an empty input buffer E == 0
		ld		(hl),e
		ld		(ix+zxmon.VARS.input_argc),a
		ret

;
; Raw keymap can have keycodes from $3f to 63 that map to some ASCII 
; character. Keycode $40 is reserved for 'symbol shift' key and
; $80 is reserved for 'caps shift'.
; Raw keys can have either symbol shift and/or caps shift also pressed.
; 
; Cooked keycodes are ASCII codes between $01 and $7f. Cooked keycodes 
; betweem $40 and $7f have symbol shift pressed as well.
raw_keymap:
		db	$80,  1,  2,  3,  4
		db	  5,  6,  7,  8,  9
		db	 10, 11, 12, 13, 14
		db	 15, 16, 17, 18, 19
		db	 20, 21, 22, 23, 24
		db	 25, 26, 27, 28, 29
		db	 30, 31, 32, 33, 34
		db	 35,$40, 37, 38, 39

; ASCII code 0 means the mapped key is not printable. It is up to print
; routine to somehow handle ASCII codes between $01 and $1f. This source
; does not have even fonts for those ;)
to_ascii:
		db	  0,'z','x','c','v'
		db  'a','s','d','f','g'
		db  'q','w','e','r','t'
		db  '1','2','3','4','5'
		db  '0','9','8','7','6'
		db  'p','o','i','u','y'
		db    0,'l','k','j','h'
		db  ' ',  0,'m','n','b'
		ds	64-40	; unfortunate wasted space	

; And same keys when symbol shift is pressed.
with_shift:
		db	  0,':','$','?','/'
		db  '~','|','\','{','}'
		db  ' ',' ',' ','<','>'
		db  '!','@','#','$','%'
		db  '_',')','(',"'",'&'
		db  '"',';',' ',']','['
		db    0,'=','+','-','^'
		db  ' ',  0,'.',',','*'
		ds	64-40	; unfortunate wasted space	

; And same keys when caps shift is pressed.
with_caps:
		db	  0,'Z','X','C','V'
		db  'A','S','D','F','G'
		db  'Q','W','E','R','T'
		db    0,  0,  0,  0,  0
		db    0,  0,  0,  0,  0
		db  'P','O','I','U','Y'
		db    0,'L','K','J','H'
		db  ' ',  0,'M','N','B'


	DISPLAY	"raw_keymap: ",/H,raw_keymap
	DISPLAY	"to_ascii: ",/H,to_ascii
	DISPLAY	"with_shift: ",/H,with_shift




;-----------------------------------------------------------------------------
;
; Scroll screen up 6 pix at time starting byte offset E from row D, amd
; width of B bytes.
;
; Input:
;  D = y [0..191] must be a multiple of 6
;  E = x [0..255] 
;  C = width in bytes
;  B = number of rows to scroll up
;
; Returns:
;  None
;
; Trashes:
;  A,BC,DE
;

scroll_up_whole_screen:
		ld		de,0
		ld		bc,0x1f20
scroll_up:
		push	hl
.row_loop:
		push	bc
		ld		b,6
.column_loop:
		push	bc
		push	de
		call	calculate_xy_addr
		; HL current line address
		ld		a,d
		add		a,6
		ld		d,a
		push	hl
		call	calculate_xy_addr
		; HL = next line address
		ld		b,0
		pop		de
		ldir
		pop		de
		inc		d
		pop		bc
		djnz	.column_loop
		pop		bc
		djnz	.row_loop
		; Clear last line
		ld		b,6
.clear_loop:
		push	bc
		call	calculate_xy_addr
		xor		a
		ld		b,c
.clear_line:
		ld		(hl),a
		inc		l
		djnz	.clear_line
		inc		d
		pop		bc
		djnz	.clear_loop
		pop		hl
		ret


;-----------------------------------------------------------------------------
;
; Input:
;  D = y [0..31]
;  E = x [0..41]
;  B = # of chars to print
;  HL = NUL terminated string
;
; Returns:
;  HL = next position in input string
;  DE = next position on the ouput line
;   B = 0
;
; Trashes:
;  A
;
print_at_bottom:
		ld		de,zxmon.AT_LOW_LEFT
print_at:
.print_loop:
		ld		a,(hl)
		inc		hl
		and		a
		ret		z
		push	af
		and		01111111b
		push	hl
		push	bc
		push	de

		call	print_at_char

		pop		de
		pop		bc
		pop		hl
		pop		af
		ret		m
		inc		e

		djnz	.print_loop
		ret


;-----------------------------------------------------------------------------
;
; Input:
;  A = ASCII
;  D = y [0..191] or [0..31] for _char 
;  E = x [0..255] or [0..41] for _char
;
; Returns:
;  D = input D + 6
;
; Trashes:
;  BC,D,HL,A
;
;

print_at_char:
		push	af
		
		; y = D x 6
		ld		a,d
		add		a,a
		ld		d,a
		add		a,a
		add		a,d
		ld		d,a

		; x = E x 6
		ld		a,e
		add		a,a
		ld		e,a
		add		a,a
		add		a,e
		ld		e,a

		pop		af
print_xy_char:
		ld		h,0
		sub		32		; ' '
		add		a,a
		ld		l,a
		push	hl
		add		hl,hl
		pop		bc
		add		hl,bc
		ld		bc,font_6x6
		add		hl,bc
		; HL = ptr to font gfx
		ld		b,6
		push	hl

.print_loop:
		call	calculate_xy_addr
		ex		(sp),hl
		; HL   = ptr to font
		; (SP) = ptr to screen
		; A    = shift
		ld		c,(hl)
		inc		hl
		ex		(sp),hl                                                                                                                                                       
		; HL   = ptr to screen
		; (SP) = ptr to font
		;    C = font data
		push	de
		push	bc
		ld		b,0
		ld		de,1000000111111111b
		jr z,	.no_shift
.shift_font:
		srl		c
		rr		b
		sra		d
		rr		e
		dec		a
		jr nz,	.shift_font
.no_shift:
		ld		a,(hl)
		and		d
		or		c
		ld		(hl),a
		inc		l
		ld		a,(hl)
		and		e
		or		b			; Clears C_flag
		ld		(hl),a
		pop		bc
		pop		de
		inc		d
		djnz	.print_loop
		pop		hl
		ret

;-----------------------------------------------------------------------------
;
; Inputs:
;  E = x [0..255] or [0..41]
;  D = y [0..191] or [0..31]
;
; Returns:
;  HL = address
;   A = # of shift to right
;   Z_flag = according A
;   D = y in [0..191]
;   E = x in [0..255]
;   C_flag = 0
;
; Trashes:
;   
calculate_xy_char_addr:
		; x6
		ld		a,d
		add		a,a
		ld		d,a
		add		a,a
		add		a,d
		ld		d,a
calculate_xy_addr_x:
		; x6
		ld		a,e
		add		a,a
		ld		e,a
		add		a,a
		add		a,e
		ld		e,a
calculate_xy_addr:
		call	calculate_y_addr
		ld		a,11111000b
		and		e
		rrca
		rrca
		rrca
		or		l
		ld		l,a
		ld		a,00000111b
		and		e
		ret

;-----------------------------------------------------------------------------
;
; Inputs:
;  D = y [0..191]
;
; Returns:
;  HL = address
;
; Trashes:
;  A
;
calculate_y_addr:
		ld		a,00000111b
		and		d
		or		zxmon.SCREEN_HIGH
		ld		h,a
		ld		a,11000000b
		and		d
		rrca
		rrca
		rrca
		or		h
		ld		h,a
		ld		a,00111000b
		and		d
		rlca
		rlca
		ld		l,a
		ret

;-----------------------------------------------------------------------------
; Calculate next line on the screen from current HL.
;
; Input:
;  HL = screen address
;
; Returns:
;  HL = next line screen address (on the same x-position)
;
; Trashes:
;  A
;
next_line_HL:
		inc		h
		ld		a,h
		and		0x07
		ret nz
		ld		a,l
		add		a,0x20
		ld		l,a
		ret c
		ld		a,h
		sub		0x08
		ld		h,a
		ret

;-----------------------------------------------------------------------------
; Capital letter + numbers alphabet.
; Meant to 6x6 pixel output.
font_6x6
		db		000000000	; space
		db		00000000b
		db		00000000b
		db		00000000b
		db		00000000b
		db		00000000b

		db		00110000b	; Exclamanation mark
		db		00110000b
		db		00110000b
		db		00000000b
		db		00110000b
		db		00000000b

		db		00101000b	; Double quotes
		db		00101000b
		db		00000000b
		db		00000000b
		db		00000000b
		db		00000000b

		db		00101000b	; 	Number sign
		db		01111100b
		db		00101000b
		db		01111100b
		db		00101000b
		db		00000000b

		db		00010000b	; Dollar
		db		00111000b
		db		00100000b
		db		00011000b
		db		00111000b
		db		00010000b
		
		db		01000100b	; percent
		db		00001000b
		db		00010000b
		db		00100000b
		db		01000100b
		db		00000000b

		db		00100000b	; amp
		db		01010000b
		db		00100000b
		db		01010000b
		db		00111000b
		db		00000000b

		db		00100000b	; apos
		db		00100000b
		db		00000000b
		db		00000000b
		db		00000000b
		db		00000000b

		db		00001000b	; lparenthesis
		db		00010000b
		db		00010000b
		db		00010000b
		db		00001000b
		db		00000000b

		db		00100000b	; rparenthesis
		db		00010000b
		db		00010000b
		db		00010000b
		db		00100000b
		db		00000000b

		db		00000000b	; asterix
		db		00101000b
		db		00010000b
		db		00101000b
		db		00000000b
		db		00000000b

		db		00010000b	; plus
		db		00010000b
		db		01111100b
		db		00010000b
		db		00010000b
		db		00000000b

		db		00000000b	; comma
		db		00000000b
		db		00000000b
		db		00000000b
		db		00100000b
		db		01100000b

		db		00000000b	; minus
		db		00000000b
		db		01111100b
		db		00000000b
		db		00000000b
		db		00000000b

		db		00000000b	; period
		db		00000000b
		db		00000000b
		db		00000000b
		db		01100000b
		db		00000000b

		db		00000100b	; /
		db		00001000b
		db		00010000b
		db		00100000b
		db		01000000b
		db		00000000b

		db		00111000b	; 0
		db		01000100b
		db		01010100b
		db		01000100b
		db		00111000b
		db		00000000b

		db		01110000b	; 1
		db		00010000b
		db		00010000b
		db		00010000b
		db		01111100b
		db		00000000b

		db		01111000b	; 2
		db		00000100b
		db		00111100b
		db		01000000b
		db		01111100b
		db		00000000b

		db		01111100b	; 3
		db		00000100b
		db		00011100b
		db		00000100b
		db		01111100b
		db		00000000b

		db		01000100b	; 4
		db		01000100b
		db		01111100b
		db		00000100b
		db		00000100b
		db		00000000b

		db		01111100b	; 5
		db		01000000b
		db		01111000b
		db		00000100b
		db		01111000b
		db		00000000b

		db		00111000b	; 6
		db		01000000b
		db		01111000b
		db		01000100b
		db		00111000b
		db		00000000b

		db		01111100b	; 7
		db		00000100b
		db		00001000b
		db		00010000b
		db		00010000b
		db		00000000b

		db		00111000b	; 8
		db		01000100b
		db		00111000b
		db		01000100b
		db		00111000b
		db		00000000b

		db		00111000b	; 9
		db		01000100b
		db		00111100b
		db		00000100b
		db		01111000b
		db		00000000b

		db		00000000b	; colon
		db		00011000b
		db		00000000b
		db		00011000b
		db		00000000b
		db		00000000b

		db		00000000b	; semicolon
		db		00011000b
		db		00000000b
		db		00011000b
		db		00110000b
		db		00000000b

		db		00010000b	; less than
		db		00100000b
		db		01000000b
		db		00100000b
		db		00010000b
		db		00000000b

		db		00000000b	; equal
		db		01111100b
		db		00000000b
		db		01111100b
		db		00000000b
		db		00000000b

		db		01000000b	; greater than
		db		00100000b
		db		00010000b
		db		00100000b
		db		01000000b
		db		00000000b

		db		00111000b	; question mark
		db		00000100b
		db		00011000b
		db		00000000b
		db		00011000b
		db		00000000b

		db		00110000b	; commat
		db		01001000b
		db		01011000b
		db		01000000b
		db		00111000b
		db		00000000b

		db		00111000b	; A
		db		01000100b
		db		01111100b
		db		01000100b
		db		01000100b
		db		00000000b

		db		01111000b	; B
		db		01000100b
		db		01111000b
		db		01000100b
		db		01111000b
		db		00000000b

		db		00111000b	; C
		db		01000100b
		db		01000000b
		db		01000100b
		db		00111000b
		db		00000000b

		db		01111000b	; D
		db		01000100b
		db		01000100b
		db		01000100b
		db		01111000b
		db		00000000b

		db		01111100b	; E
		db		01000000b
		db		01110000b
		db		01000000b
		db		01111100b
		db		00000000b

		db		01111100b	; F
		db		01000000b
		db		01110000b
		db		01000000b
		db		01000000b
		db		00000000b

		db		00111000b	; G
		db		01000000b
		db		01011100b
		db		01000100b
		db		00111000b
		db		00000000b

		db		01000100b	; H
		db		01000100b
		db		01111100b
		db		01000100b
		db		01000100b
		db		00000000b

		db		01111100b	; I
		db		00010000b
		db		00010000b
		db		00010000b
		db		01111100b
		db		00000000b

		db		00000100b	; J
		db		00000100b
		db		00000100b
		db		01000100b
		db		00111000b
		db		00000000b

		db		01000100b	; K
		db		01001000b
		db		01110000b
		db		01001000b
		db		01000100b
		db		00000000b

		db		01000000b	; L
		db		01000000b
		db		01000000b
		db		01000000b
		db		01111100b
		db		00000000b

		db		01000100b	; M
		db		01101100b
		db		01010100b
		db		01000100b
		db		01000100b
		db		00000000b

		db		01000100b	; N
		db		01100100b
		db		01010100b
		db		01001100b
		db		01000100b
		db		00000000b

		db		00111000b	; O
		db		01000100b
		db		01000100b
		db		01000100b
		db		00111000b
		db		00000000b

		db		01111000b	; P
		db		01000100b
		db		01111000b
		db		01000000b
		db		01000000b
		db		00000000b

		db		00111000b	; Q
		db		01000100b
		db		01010100b
		db		01001000b
		db		00110100b
		db		00000000b

		db		01111000b	; R
		db		01000100b
		db		01111000b
		db		01001000b
		db		01000100b
		db		00000000b

		db		00111100b	; S
		db		01000000b
		db		00111000b
		db		00000100b
		db		01111000b
		db		00000000b

		db		01111100b	; T
		db		00010000b
		db		00010000b
		db		00010000b
		db		00010000b
		db		00000000b

		db		01000100b	; U
		db		01000100b
		db		01000100b
		db		01000100b
		db		00111000b
		db		00000000b

		db		01000100b	; V
		db		01000100b
		db		01000100b
		db		00101000b
		db		00010000b
		db		00000000b

		db		01000100b	; W
		db		01000100b
		db		01010100b
		db		01101100b
		db		01000100b
		db		00000000b

		db		01000100b	; X
		db		00101000b
		db		00010000b
		db		00101000b
		db		01000100b
		db		00000000b

		db		01000100b	; Y
		db		00101000b
		db		00010000b
		db		00010000b
		db		00010000b
		db		00000000b

		db		01111100b	; Z
		db		00001000b
		db		00010000b
		db		00100000b
		db		01111100b
		db		00000000b

		db		00011000b	; [
		db		00010000b
		db		00010000b
		db		00010000b
		db		00011000b
		db		00000000b

		db		01000000b	; \
		db		00100000b
		db		00010000b
		db		00001000b
		db		00000100b
		db		00000000b

		db		00110000b	; ]
		db		00010000b
		db		00010000b
		db		00010000b
		db		00110000b
		db		00000000b

		db		00010000b	; ^
		db		00101000b
		db		01000100b
		db		00000000b
		db		00000000b
		db		00000000b

		db		00000000b	; _
		db		00000000b
		db		00000000b
		db		00000000b
		db		01111100b
		db		00000000b

		db		00010000b	; `
		db		00100000b
		db		00000000b
		db		00000000b
		db		00000000b
		db		00000000b

		db		00000000b	; a
		db		00111000b
		db		01001000b
		db		01001000b
		db		00111000b
		db		00000000b

		db		01000000b	; b
		db		01110000b
		db		01001000b
		db		01001000b
		db		01110000b
		db		00000000b

		db		00000000b	; c
		db		00111000b
		db		01000000b
		db		01000000b
		db		00111000b
		db		00000000b

		db		00001000b	; d
		db		00111000b
		db		01001000b
		db		01001000b
		db		00111000b
		db		00000000b

		db		00000000b	; e
		db		00111000b
		db		01111000b
		db		01000000b
		db		00111000b
		db		00000000b

		db		00011000b	; f
		db		00100000b
		db		01111000b
		db		00100000b
		db		00100000b
		db		00000000b

		db		00000000b	; g
		db		00111000b
		db		01001000b
		db		00111000b
		db		00001000b
		db		01110000b

		db		01000000b	; h
		db		01110000b
		db		01001000b
		db		01001000b
		db		01001000b
		db		00000000b

		db		00100000b	; i
		db		00000000b
		db		00100000b
		db		00100000b
		db		00100000b
		db		00000000b

		db		00001000b	; j
		db		00000000b
		db		00001000b
		db		00001000b
		db		01001000b
		db		00110000b

		db		01000000b	; k
		db		01001000b
		db		01110000b
		db		01001000b
		db		01001000b
		db		00000000b

		db		01000000b	; l
		db		01000000b
		db		01000000b
		db		01000000b
		db		00110000b
		db		00000000b

		db		00000000b	; m
		db		01001000b
		db		01111000b
		db		01001000b
		db		01001000b
		db		00000000b

		db		00000000b	; n
		db		01110000b
		db		01001000b
		db		01001000b
		db		01001000b
		db		00000000b

		db		00000000b	; o
		db		00110000b
		db		01001000b
		db		01001000b
		db		00110000b
		db		00000000b

		db		00000000b	; p
		db		01110000b
		db		01001000b
		db		01001000b
		db		01110000b
		db		01000000b

		db		00000000b	; q
		db		00111000b
		db		01001000b
		db		01001000b
		db		00111000b
		db		00001000b

		db		00000000b	; r
		db		01110000b
		db		01001000b
		db		01000000b
		db		01000000b
		db		00000000b

		db		00000000b	; s
		db		00111000b
		db		01100000b
		db		00011000b
		db		01110000b
		db		00000000b

		db		00100000b	; t
		db		01110000b
		db		00100000b
		db		00100000b
		db		00110000b
		db		00000000b

		db		00000000b	; u
		db		01001000b
		db		01001000b
		db		01001000b
		db		00110000b
		db		00000000b

		db		00000000b	; v
		db		01001000b
		db		01001000b
		db		00110000b
		db		00110000b
		db		00000000b

		db		00000000b	; w
		db		01001000b
		db		01001000b
		db		01111000b
		db		01001000b
		db		00000000b

		db		00000000b	; x
		db		01001000b
		db		00110000b
		db		00110000b
		db		01001000b
		db		00000000b

		db		00000000b	; y
		db		01001000b
		db		01001000b
		db		00111000b
		db		00001000b
		db		01110000b

		db		00000000b	; z
		db		01111000b
		db		00011000b
		db		01100000b
		db		01111000b
		db		00000000b

		db		00011000b	; {
		db		00010000b
		db		00100000b
		db		00010000b
		db		00011000b
		db		00000000b

		db		00010000b	; |
		db		00010000b
		db		00010000b
		db		00010000b
		db		00010000b
		db		00000000b


		db		00110000b	; }
		db		00010000b
		db		00001000b
		db		00010000b
		db		00110000b
		db		00000000b


		db		00100000b	; ~
		db		01010100b
		db		00001000b
		db		00000000b
		db		00000000b
		db		00000000b



fonts_end:

		ENDMODULE
	


