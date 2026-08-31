		DEVICE	ZXSPECTRUM128
		SLDOPT	COMMENT WPMEM, LOGPOINT, ASSERTION

		MODULE	string

		INCLUDE	"zxmon.inc"

;
; Case sensitive strncmp() with non-NIL terminated strings.
;
; int strncmp(const char *s1, const char *s2, size_t n);
;
; Inputs:
;   B = n
;  DL = s1 (not \0 terminated)
;  HL = s2 (not \0 terminated)
;
; Returns:
;  Z_flag == 1 if OK, note that if n == 0 then Z is set as well.
;  When match is found DE = end of s1 and HL = end of s2
;  B = remaining string bytes. B == 0 if strings matched fully.
;  If Z_flag == 1, but B > 0 then either s1 or s2
;  was \0 terminated and less then n bytes long.
;  bytes length  
;  C_flag = 1 if n = 0 i.e. max amount got matched. Otherwise,
;  C_flag = 0
;
; Trashes:
;   A,B,DE,HL
;
;
strncmp:
		ld		a,b
		and		a
		ccf
		ret z
.cmploop:
		ld		a,(de)
        inc     de
		xor		(hl)
		inc		hl
		ret	nz
		djnz	.cmploop
.match:
		scf
		ret
;
; Convert WORD or BYTE to ASCII
;
; Inputs:
;  HL = ptr to output
;  DE = value to convert
;
; Returns:
;  HL = next ptr after converted ASCII HEX.
;
; Trashes:
;  A
;
word_in_DE_to_ascii:
		ld		a,d
		call	byte_in_A_to_ascii
		ld		a,e
byte_in_A_to_ascii:
		push	de
		ld		e,a
		and		11110000b
		rrca
		rrca
		rrca
		rrca
		cp		0x0a
		jr c,	.letter1
		add		a,'A'-'0'-10
.letter1:
		add		a,'0'
		; latter byte will be LD D,C

		ld		(hl),a
		inc		hl
		
		ld		a,00001111b
		and		e
		cp		0x0a
		jr c,	.letter2
		add		a,'A'-'0'-10
.letter2:
		add		a,'0'
		; latter byte will be LD D,C
		ld		(hl),a
		inc		hl
		pop		de
		ret

;-----------------------------------------------------------------------------
;
; Internal convert hex string number
;
; Input:
;  BC = ptr to string, either NIL or whitespace terminated, or
;       in case of error the offending character
;
; Return:
;  DEHL = number is case of a dword
;  C_flag = 0 if conversion was OK
;  C_flag = 1 if conversion failed; HL contains carbage
;
; Trashes:
;  A
;
_hexstr_to_number:
_nibble_loop:
		ld		a,(bc)
		inc		bc
		; take care of a single nibble number
		cp		' '			; If Z=1 then C_flag = 0 as well
		jr z,	_pop_bc_exit
		and		a			; If Z=1 then C_flag = 0 as well
		jr z,	_pop_bc_exit
		; Start with one nibble
		sub		'0'
		jr c,	_pop_bc_exit				; C_flag = 1 -> conversion error
		cp		10
		jr c,	_between_0_9
		and		0xDF
		sub		7			; C_flag = 1 -> conversion error
		jr c,	_pop_bc_exit
		cp		16
		jr c,	_between_A_F
		ccf
_pop_bc_exit:
		pop		bc
		ret
_between_A_F:
_between_0_9:
		add		hl,hl
		rl		e
		rl		d
		add		hl,hl
		rl		e
		rl		d
		add		hl,hl
		rl		e
		rl		d
		add		hl,hl
		rl		e
		rl		d
		or		l			; C_flag = 0
		ld		l,a
		jr		_nibble_loop


;-----------------------------------------------------------------------------
;
; Generic conversion of string to number (max 65535).3
;
; Input:
;  DE = ptr to string, either NIL or whitespace terminated, or
;       in case of error the offending character
;       If the string starts with underscore ('_') the following number will
;       be treated as a decimal number. Otherwise it will be treared as a hex
;       number.
;
; Return:
;  DEHL = number is case of a dword
;  C_flag = 0 if conversion was OK
;  C_flag = 1 if conversion failed; HL contains carbage
;
; Trashes:
;  A
;
str_to_number:
		push	bc
		ld		b,d
		ld		c,e
		xor		a
		ld		h,a
		ld		l,a
		ld		d,a
		ld		e,a

		ld		a,(bc)
		cp		'_'
		jr nz, 	_hexstr_to_number
		inc		bc	

;-----------------------------------------------------------------------------
;
; Internal convert decimal string to number.
;
; Input:
;  DE = ptr to string, either NIL or whitespace terminated, or
;       in case of error the offending character
;
; Return:
;  DEHL = converted number
;  C_flag = 0 if conversion was OK
;  C_flag = 1 if conversion failed; HL contains carbage
;
_decstr_to_number:
.number_loop:
		ld		a,(bc)
		inc		bc
		cp		' '
		jr z,	_pop_bc_exit
		and		a
		jr z,	_pop_bc_exit
		sub		'0'
		jr c,	_pop_bc_exit
		cp		10
		jr nc,	_pop_bc_exit
		call	zxmon.math.mul_DEHLx10
		add		l
		ld		l,a
		jr nc,	.number_loop
		inc		h
		jr		.number_loop



;-----------------------------------------------------------------------------
;
; Convert a 32 bit number in DEHL to unsigned decimal string with NIL
; termination. String uses sysvars VARS.conversion_buf space
; as a work buffer. If input is 0 then only '0',0 is outputed.
;
; Input;
;  IX = ptr to sysvar
;  DEHL = 32 bit unsigned number to convert to decimal string
;    or
;    HL = 16 bit unsigned number.
;
; Returns:
;   HL = ptr to start of the string.
;    A = string length
;
; Trashes:
;  A,DE
;
hl_to_decstr:
		ld		de,0
dehl_to_decstr:
		push	bc
		ld		b,ixh
		ld		c,VARS.conversion_buf+SZ_CONV_STR
		; NIL termination of the string. We know buffer
		; is one longer than SZ_CONV_STR..
		xor		a
		ld		(bc),a
		push	bc

.file_size_loop:
		call	zxmon.math.div_DEHL_by_10
		ex		(sp),hl
		add		a,'0'
		dec		l
		ld		(hl),a
		ex		(sp),hl
		ld		a,l
		or		h
		jr nz,	.file_size_loop
		ld		a,e
		or		d
		jr nz,	.file_size_loop

		pop		hl
		ld		a,VARS.conversion_buf+SZ_CONV_STR
		sub		l
		pop		bc
		ret

        ENDMODULE
