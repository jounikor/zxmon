		DEVICE	ZXSPECTRUM128
		SLDOPT	COMMENT WPMEM, LOGPOINT, ASSERTION

		MODULE	disasm

		INCLUDE	"zxmon.inc"


ARG_ROT_Y			equ		'/'-32
ARG_R_Z				equ		'0'-32
ARG_Y				equ		'1'-32
ARG_INDEX_B			equ		'2'-32
ARG_R_Y				equ		'3'-32
ARG_JR				equ		'4'-32
ARG_JR_D_INC		equ		'5'-32
ARG_HL				equ		'6'-32
ARG_RP_P			equ		'7'-32
ARG_BLI_Y_Z			equ		'8'-32
ARG_IMM16_INC		equ		'9'-32
ARG_LD				equ		':'-32
ARG_IMM8_INC		equ		';'-32
ARG_CC_P			equ		'<'-32
ARG_CC_Y			equ		'='-32
ARG_ALU_Y			equ		'>'-32
ARG_Y_8				equ		'?'-32
ARG_ERR				equ		'@'-32



;-----------------------------------------------------------------------------
;
; Disassemble memory. Both 8 and 16 lines of output supported.
;
; Input:
;  IX = ptr to sysvars, which contains tokenized ARGV[]..
;
; Returns:
;  A = 0 when no error and A contains file handle.
;  A > 0 and A contains error code.
;
f_dis16
		ld		b,16
		db		00010001b		; LD DE,nn
f_dis8:
		ld		b,8
		ld		a,(ix+zxmon.VARS.input_argc)
		cp		2
		jr c,	.mon_continue_addr
		;
		ld		d,ixh
		ld		e,(ix+zxmon.VARS.input_argv+1)
		call	zxmon.string.str_to_number
		jr nc,	.num_conversion_ok
		ld		a,CMD_ENUMCONV
		ret
.num_conversion_ok:
		ld		(ix+zxmon.VARS.mem_addr+0),l
		ld		(ix+zxmon.VARS.mem_addr+1),h
.mon_continue_addr:
		ld		e,(ix+zxmon.VARS.mem_addr+0)
		ld		d,(ix+zxmon.VARS.mem_addr+1)
		
.dis_display_main:
		push	bc
		push	ix
		pop		hl
		push	hl
		
		; print address
		call	zxmon.string.word_in_DE_to_ascii
		ld		(hl),':'
		inc		l

		; init output buffer to all spaces
		push	hl
		ld		b,zxmon.MAXX-6
.init_output_buf:
		ld		(hl),' '
		inc		l
		djnz	.init_output_buf
		pop		hl

		inc		l

		; save output buffer ptr where to continue output
		push	hl
		; Save IX and memory address to disassemble and 
		push	ix
		push	de

		; skip byte and ascii output area
		ld		bc,16
		add		hl,bc

		push	de
		pop		ix
		ex		de,hl
		call	dis_z80
		; add EOL
		xor		a			; clears C_flag
		ld		(de),a

		; Check how many bytes to output
		push	ix
		pop		hl			; currnet memory ptr
		pop		de			; start memory ptr
		sbc		hl,de
		ld		b,l			; B = how many bytes the opcode was..

		pop		ix			; IX = pre to VARS
		pop		hl			; HL = ptr to output buffer to continue

		push	de
		push	bc
		push	hl

		;
.dis_display_loop:
		ld		a,(de)
		inc		de
		call	zxmon.string.byte_in_A_to_ascii
		djnz	.dis_display_loop

		pop		hl
		ld		bc,9
		add		hl,bc
		ld		(hl),"'"
		inc		l
		pop		bc
		pop		de
.dis_ascii_loop:
		ld		a,(de)
		inc		de
		cp		' '
		jr c,	.force_dot
		cp		'~'+1
		jr c,	.dis_to_ascii
.force_dot:
		ld		a,'.'
.dis_to_ascii:
		ld		(hl),a
		inc		l
		djnz	.dis_ascii_loop
		;
		ld		(hl),"'"
		;

		pop		hl
		push	de
		ld		de,0x1f00
		call	zxmon.input_and_screen.print_at
		call	zxmon.input_and_screen.scroll_up_whole_screen
		pop		de
		pop		bc
		djnz	.dis_display_main
		;

		ld		(ix+zxmon.VARS.mem_addr+0),e
		ld		(ix+zxmon.VARS.mem_addr+1),d
		xor		a
		ret

;-----------------------------------------------------------------------------
;
; Output ascii line:
; 0         1         2         3         4
; 012345678901234567890123456789012345678901
; 8000: 11223344 'ab.?' CALL NZ,ADDR  
; 8003: BB2211   'xdc'  LD A,(IX+11h)
; 8006: AA2211   'ab%'  LD HL,(1122h)
; ..
;
; Inputs:
;  IX = ptr to addr to disassemble
;  DE = pre to buffer to output disassembly. Note it is assumed the buffer
;       is initialized to all spaces.
;
; Return:
;  IX = ptr to next opcode to disassembke
;  De = ptr to next empty position in output bugffer
;
; Trashes:
;  A,A',BC,HL
;
;
; How ASCII strings are coded
;
; 76543210
; ESaaaaaa
;
; E = 1 -> End-marker for the string
; S = 1 -> Add space after the 'aaaaaa' (be ASCII or argument)
; aaaaaa = ASCII-32 or argument
; aaaaaa = '_'-32 is the end marker for the entire list of strings
;          End marker must be follow executable code, like RET
;
dis_z80:
		call	get_A_from_IX
prefix_DD_NONI:
prefix_FD_NONI:
		ld		c,2
		cp		0xdd
		jr		z,prefix_DD
		dec		c
		cp		0xfd
		jr		z,prefix_FD
prefix_ED_NONI:
		ld		c,0
		; Ok.. this is not DD/FD prefixes opcode.. 
		; C = 0, B is unknown
		cp		0xed
		jr		z,prefix_ED
		cp		0xcb
		jr		z,prefix_CB
		jp		normal_opcode
		;
prefix_DD:
prefix_FD:
		call	get_A_B_from_IX
		cp		0xdd
		jr		z,prefix_DD_NONI
		cp		0xfd
		jr		z,prefix_FD_NONI
		cp		0xed
		jr		z,prefix_ED_NONI
		cp		0xcb
		inc		ix
		jp		nz,normal_opcode_after_DDFD
		; This is DD/FD prefixed CB.. skip displacement and get new opcode
		; This is just CD prfix.. get new opcode
prefix_CB:
		call	get_A_from_IX
		; 76543210 opcode
		; xxyyyzzz
		; Where
		;  x=0 -> rot[y] r[z]
		;  x=1 -> BIT y,r[z]
		;  x=2 -> RES y,r[z]
		;  x=3 -> SET y,r[z]
		; A = opcode
		; B = IX/IY index
		; C = HL/IX/IY marker
		;
		and		11000000b
		rlca
		rlca
		call	print_opcode_str_index
		db		ARG_ROT_Y+64,ARG_R_Z+128							; rot|y],r[z]
		db		'B'-32,'I'-32,'T'-32+64,ARG_Y,','-32,ARG_R_Z+128	; BIT y,r[z]
		db		'R'-32,'E'-32,'S'-32+64,ARG_Y,','-32,ARG_R_Z+128	; RES y,r[z]
		db		'S'-32,'E'-32,'T'-32+64,ARG_Y,','-32,ARG_R_Z+128	; SET y,r[z]

prefix_ED:
		call	get_A_from_IX
		and		11000000b
		rlca
		rlca
		call	jump_tab
		db		prefix_ED_err-$
		db		func_ED_misc-$
		db		func_bli-$
		db		prefix_ED_err-$

func_ED_misc:
		call	jump_tab8
		db		prefix_ED_IN-$
		db		prefix_ED_OUT-$
		db		prefix_ED_16b-$
		db		prefix_ED_LD16-$
		db		prefix_ED_NEG-$
		db		prefix_ED_RET-$
		db		prefix_ED_IM-$
		db		prefix_ED_LD-$

prefix_ED_IN:
prefix_ED_OUT:
		ld		l,a
		and		00111000b
		cp		00110000b			; HL -> IN (C)
		ld		a,0
		jr		z,.equals_6
		inc		a
.equals_6:
		srl		l
		jr		nc,.it_is_IN
		add		a,a
.it_is_IN:
		call	print_opcode_str_index
		db		'I'-32,'N'-32+64,'('-32,'C'-32,')'-32+128
		db		'I'-32,'N'-32+64,ARG_R_Y,','-32,'('-32,'C'-32,')'-32+128
		db		'O'-32,'U'-32,'T'-32+64,'('-32,'C'-32,')'-32+128
		db		'O'-32,'O'-32,'T'-32+64,ARG_R_Y,','-32,'('-32,'C'-32,')'-32+128

prefix_ED_16b:
prefix_ED_LD16:
		rrca
		adc		a,0
		rrca
		and		00000011b
		call	print_opcode_str_index
		db		'S'-32,'B'-32,'C'-32+64,'H'-32,'L'-32,','-32,ARG_RP_P+128	; q = 0
		db		ARG_LD+64,'('-32,ARG_IMM16_INC,')'-32,','-32,ARG_RP_P+128	; q = 0
		db		'A'-32,'D'-32,'C'-32+64,'H'-32,'L'-32,','-32,ARG_RP_P+128	; q =1
		db		ARG_LD+64,ARG_RP_P,','-32,'('-32,ARG_IMM16_INC,')'-32+128	; q =1

prefix_ED_NEG:
		call	print_opcode_str_index0
		db		'N'-32,'E'-32,'G'-32+128

prefix_ED_RET:
		and		00001000b
		jr		z,.it_is_RETN
		ld		a,1
.it_is_RETN:
		call	print_opcode_str_index
		db		'R'-32,'E'-32,'T'-32,'N'-32+128
		db		'R'-32,'E'-32,'T'-32,'1'-32+128

prefix_ED_IM:
		and		00011000b
		call	print_opcode_str_index8_shift
		db		'I'-32,'M'-32+64,'0'-32+128
		db		'I'-32,'M'-32+64,'0'-32,'-'-32,'1'-32+128
		db		'I'-32,'M'-32+64,'1'-32+128
		db		'I'-32,'M'-32+64,'2'-32+128

prefix_ED_LD:
		call	print_opcode_str_index8_shift
		db		ARG_LD+64,'I'-32,','-32+64,'A'-32+128
		db		ARG_LD+64,'R'-32,','-32+64,'A'-32+128
		db		ARG_LD+64,'A'-32,','-32+64,'I'-32+128
		db		ARG_LD+64,'A'-32,','-32+64,'R'-32+128
		db		'R'-32,'R'-32,'D'-32+128
		db		'R'-32,ARG_LD+128				; RLD
		db		'N'-32,'O'-32,'P'-32+128		; undocumented?
		db		'N'-32,'O'-32,'P'-32+128		; undocumented?
		
prefix_ED_err:
		ld		a,4
func_bli:
		; this saves 2 bytes (and changes string table to 2 entries)
		rrca
		rrca
		and		00000001b
		call	print_opcode_str_index
		db		ARG_BLI_Y_Z-128
		db		'*'-32+128

normal_opcode_after_DDFD:
		; Skipped index byte and use one in B instead
normal_opcode:
		; Ok.. normal opcode..
		; 76543210
		; xxyyyzzz
		;   ppq
		;
		rlca
		rlca
		and		00000011b
		call	jump_tab8
		db		opcode_00nnnnnn-$
		db		opcode_01nnnnnn-$
		db		opcode_10nnnnnn-$
		db		opcode_11nnnnnn-$
opcode_01nnnnnn:
		call	get_opcode_to_A
		and		00111111b
		xor		00110110b
		jr		z,opcode_halt
		ld		a,1
opcode_halt:
		call	print_opcode_str_index
		db		'H'-32,'A'-32,'L'-32,'T'-32+128			; HALT
		db		ARG_LD+64,ARG_R_Y,','-32,ARG_R_Z+128					; LD r[y],r[z]

opcode_10nnnnnn:
		call	print_opcode_str_index0
		db		ARG_ALU_Y,ARG_R_Z+128				; ADD A,r[z] etc

opcode_11nnnnnn:
		and		00000111b
		srl		a
		jr		c,opcode_11_misc
		; 000 -> 000 ret cc[y]
		; 001 -> 000 
		; 010 -> 001 jp cc[y]
		; 011 -> 001
		; 100 -> 010 call cc[y]
		; 101 -> 010
		; 110 -> 011 alu [y],nn
		; 111 -> 011 rst y*8
opcode_11_alu_ok:
		call	print_opcode_str_index8
		db		'R'-32,'E'-32,'T'-32+64,ARG_CC_Y+128
		db		'J'-32,'P'-32+64,ARG_CC_Y,','-32,ARG_IMM16_INC+128
		db		'C'-32,'A'-32,'L'-32,'L'-32+64,ARG_CC_Y,','-32,ARG_IMM16_INC+128
		db		ARG_ALU_Y,ARG_IMM8_INC+128				; alu[y] nn
		db		'R'-32,'S'-32,'T'-32+64,ARG_Y_8+128		; RST p

opcode_11_misc:
		ld		l,a
		ld		a,c
		and		a
		jr		z,.IX_IY_ok
		dec		ix
.IX_IY_ok:
		ld		a,l
		inc		a
		; Check for RST
		cp		4
		jr		z,opcode_11_alu_ok
		call	jump_tab8
		db		0												; excess byte
		db		opcode_11_pop-$
		db		opcode_11_jp-$
		db		opcode_11_push-$
opcode_11_pop:
		call	print_opcode_str_index8_shift
		db		'P'-32,'O'-32,'P'-32+64,ARG_RP_P+128			; POP BC
		db		'R'-32,'E'-32,'T'-32+128						; RET
		db		'P'-32,'O'-32,'P'-32+64,ARG_RP_P+128			; POP DE
		db		'E'-32,'X'-32,'X'-32+128						; EXX
		db		'P'-32,'O'-32,'P'-32+64,ARG_HL+128				; POP HL/IX/IY
		db		'J'-32,'P'-32+64,'('-32,ARG_HL,')'-32+128		; JP (HL/IX/IY)
		db		'P'-32,'O'-32,'P'-32+64,'A'-32,'F'-32+128		; POP AF
		db		ARG_LD+64,'S'-32,'P'-32,ARG_HL+128				; LD SP,HL/IX/IY

opcode_11_jp:
		call	print_opcode_str_index8_shift
		db		'J'-32,'P'-32+64,ARG_IMM16_INC+128
		db		ARG_ERR+128										; CB prefix
		db		'O'-32,'U'-32,'T'-32+64,'('-32,ARG_IMM8_INC,')'-32,','-32,'A'-32+128
		db		'I'-32,'N'-32+64,'A'-32,'('-32,ARG_IMM8_INC,')'-32+128
		db		'E'-32,'X'-32+64,'('-32,'S'-32,'P'-32,')'-32,ARG_HL+128
		db		'E'-32,'X'-32+64,'D'-32,'E'-32,','-32,'H'-32,'L'-32+128
		db		'D'-32,'I'-32+128
		db		'E'-32,'I'-32+128		

opcode_11_push:
		call	print_opcode_str_index8_shift
		db		'P'-32,'U'-32,'S'-32,'H'-32+64,ARG_RP_P+128
		db		'C'-32,'A'-32,'L'-32,'L'-32+64,ARG_IMM16_INC+128
		db		'P'-32,'U'-32,'S'-32,'H'-32+64,ARG_RP_P+128
		db		ARG_ERR+128
		db		'P'-32,'U'-32,'S'-32,'H'-32+64,ARG_HL+128
		db		ARG_ERR+128
		db		'P'-32,'U'-32,'S'-32,'H'-32+64,'A'-32,'F'-32+128
		db		ARG_ERR+128		

opcode_00nnnnnn:
		call	jump_tab8
		db		opcode_00_reljumps-$
		db		opcode_00_ldadd16_imm-$
		db		opcode_00_indirect_ld-$
		db		opcode_00_incdec16-$
		db		opcode_00_inc8-$
		db		opcode_00_dec8-$
		db		opcode_00_ld8_imm-$
		db		opcode_00_misc_acc-$

opcode_00_reljumps:
		bit		5,a
		jr		z,.ok_test
		ld		a,4<<3			; == 00100000b
.ok_test:
		call	print_opcode_str_index8_shift
		db		'N'-32,'O'-32,'P'-32+128
		db		'E'-32,'X'-32+64,'A'-32,'F'-32,','-32,'A'-32,'F'-32,"'"-32+128
		db		'D'-32,'J'-32,'N'-32,'Z'-32+64,ARG_JR_D_INC+128			; DJNZ d
		db		ARG_JR+64,ARG_JR_D_INC+128								; JR d
		db		ARG_JR+64,ARG_CC_P,','-32,ARG_JR_D_INC+128				; JR cc,d
		;db		ARG_JR+64,'N'-32,'Z'-32,','-32,ARG_JR_D_INC+128			; JR NZ,d
		;db		ARG_JR+64,'Z'-32,','-32,ARG_JR_D_INC+128				; JR Z,d
		;db		ARG_JR+64,'N'-32,'C'-32,','-32,ARG_JR_D_INC+128			; JR NC,d
		;db		ARG_JR+64,'C'-32,','-32,ARG_JR_D_INC+128				; JR C,d

opcode_00_ldadd16_imm:
		and		00001000b
		jr		z,.ld16imm
		;ld		a,1
.ld16imm:
		; check if there was DD/FD prefix.. if so fix IX
		ld		l,a
		ld		a,c
		and		a
		jr		z,.no_DD_or_FD_prefix
		dec		ix
.no_DD_or_FD_prefix:
		ld		a,l
		call	print_opcode_str_index8_shift
		db		ARG_LD+64,ARG_RP_P,','-32,ARG_IMM16_INC+128			; LD rp[p],imm16
		db		'A'-32,'D'-32,'D'-32+64,ARG_HL,','-32,ARG_RP_P+128	; ADD HL,rp[p]

opcode_00_indirect_ld:
		call	print_opcode_str_index8_shift
		db		ARG_LD+64,'('-32,'B'-32,'C'-32,')'-32,','-32,'A'-32+128
		db		ARG_LD+64,'A'-32,','-32,'('-32,'B'-32,'C'-32,')'-32+128
		db		ARG_LD+64,'('-32,'D'-32,'E'-32,')'-32,','-32,'A'-32+128
		db		ARG_LD+64,'A'-32,','-32,'('-32,'D'-32,'E'-32,')'-32+128
		db		ARG_LD+64,'('-32,ARG_IMM16_INC,')'-32,','-32,ARG_HL+128
		db		ARG_LD+64,ARG_HL,'('-32,ARG_IMM16_INC,')'-32+128
		db		ARG_LD+64,'('-32,ARG_IMM16_INC,')'-32,','-32,'A'-32+128
		db		ARG_LD+64,'A'-32,','-32,'('-32,ARG_IMM8_INC,')'-32+128

opcode_00_incdec16:
		and		00001000b
		jr		z,opcode_00_inc16
		ld		a,1
opcode_00_inc16:
		call	print_opcode_str_index
		db		'I'-32,'N'-32,'C'-32+64,ARG_RP_P+128
		db		'D'-32,'E'-32,'C'-32+64,ARG_RP_P+128

opcode_00_inc8:
opcode_00_dec8:
opcode_00_ld8_imm:
		and		00000011b
		call	print_opcode_str_index
		db		'I'-32,'N'-32,'C'-32+64,ARG_R_Y+128
		db		'D'-32,'E'-32,'C'-32+64,ARG_R_Y+128
		db		ARG_LD+64,ARG_R_Y,','-32,ARG_IMM8_INC+128

opcode_00_misc_acc:
		call	print_opcode_str_index8_shift
		db		'R'-32,'L'-32,'C'-32,'A'-32+128
		db		'R'-32,'R'-32,'C'-32,'A'-32+128
		db		'R'-32,'L'-32,'A'-32+128
		db		'R'-32,'R'-32,'A'-32+128
		db		'D'-32,'A'-32,'A'-32+128
		db		'C'-32,'P'-32,'L'-32+128
		db		'S'-32,'C'-32,'F'-32+128
		db		'C'-32,'C'-32,'F'-32+128

;
; Returns:
;  IX = next position in mem
;   A = read opcode byte from mem
;   B = read byte from mem+2
;
; <opcode>
; <opcode> <nn>
; <opcode> <nn> <nn>
; DD/FD <opcode> <dd>
; DD/FD <opcode> <nn> <nn>
; CB <opcode>
; DD CB <dd> <opcode>
; FD CB <dd> <opcode>
; DD DD -> NONI + DD
; DD FD -> NONI + FD
; DD ED -> NONI + ED
; FD DD -> NONI + DD
; FD FD -> NONI + FD
; FD ED -> NONI + ED
; ED <opcode> 
; ED <opcode> <nn> <nn>
;
get_A_B_from_IX:
		ld		b,(ix+1)
get_A_from_IX:
		ld		a,(ix+0)
		push	af
		ex		af,af'
		pop		af
		ex		af,af'
		inc		ix
		ret

;-----------------------------------------------------------------------------
;
; Jump into routine in a table following the CALL. A register low 3 bits are
; used as am index to table.
;
; Inputs:
;  IX = ptr to mem+1 to disassemble
;  DE = ptr to output buffer.  (assume buffer is initialized to all ' ')
;   A = index to jump table entry
;   B = IX/IY index
;   C = HL/IX/IY marker
;
; Returns:
;  Depends on the called function.
;
; Trashes:
;  A
;
; Note: 
;
; Usage is like below. Note this only can jump forward
;		CALL	jump_tab8_args
;		db		func0-$			; A = 0
;		db		func1-$			; A = 1
;		..
;		db		func7-$			; A = 7
;		..
;		db		funcn-$			; A = n
;
jump_tab8:
		and		00000111b
jump_tab:
		ex		(sp),hl
		push	bc
		ld		c,a
		ld		b,0
		add		hl,bc
		ld		c,(hl)
		add		hl,bc
		pop		bc
		ex		(sp),hl
get_opcode_to_A:
		ex		af,af'
		push	af
		ex		af,af'
		pop		af
		; IX = whatever it was
		; HL = whatever it was
		; DE = whatever it was
		; BC = whatever it was
		;  A = latest opcode
		ret

;-----------------------------------------------------------------------------
;
; Prints a coded string whose start address in in the stack. This function
; must follow the code convention familiar from RST e.g.:
;    LD   A,2	; offset within the string
;    CALL print_opcode_str_index
;    db   '1'-32,'2'-32,'S'-32,'T'-32,'R'-32,'I'-32,'N'-32,'G'-32+128 
;    db   '1'-32,'2'-32,'S'-32,'T'-32,'R'-32,'I'-32,'N'-32,'G'-32+128 
;    ..
;
; After calling the function the execiton continues where this subroutiine
; was called..
;
;
;
; Inputs:
;  IX = ptr to mem+1 to disassemble
;  DE = ptr to output buffer. (assume buffer is initialized to all ' ')
;   A = string index
;   B = IX/IY index
;   C = HL/IX/IY marker
;
; Returns:
;  DE = ptr to next available position in the output buffer
;
; Trashes:
;  A, BC, HL
;

print_opcode_str_index0:
		xor		a
print_opcode_str_index8_shift:
		rrca
		rrca
		rrca
print_opcode_str_index8:
		and		00000111b
print_opcode_str_index:
		pop		hl
		; find string to print..
		and		a
		jr z,	.print_loop
		;
.find_string_loop:
		bit		7,(hl)
		inc		hl
		jr z,	.find_string_loop
		dec		a
		jr 		nz,.find_string_loop
		;
.print_loop:
		ld		a,(hl)
		inc		hl
		push	af
		and		00111111b
		; Check space
		cp		'/'-32
		jr		c,.no_arguments
		; Check for arguments
		cp		'A'-32
		jr		nc,.no_arguments
		sub		'/'-32
.no_space:
		; Calls to subroutines must maintain HL and DE
		push	hl
		call	parse_arguments
		pop		hl
		jr		.exit_argument
.no_arguments:
		add		32
		ld		(de),a
		inc		de
.exit_argument:
		pop		af
		add		a,a
		bit		7,a
		jr		z,.no_trailing_space
		inc		de
.no_trailing_space:
		jr nc,	.print_loop
		pop		hl
		jp		(hl)


;
parse_arguments:
		call	jump_tab
		db		func_ARG_ROT_Y-$
		db		func_ARG_R_Z-$
		db		func_ARG_Y-$
		db		func_ARG_INDEX_B-$
		db		func_ARG_R_Y-$
		db		func_ARG_JR-$
		db		func_ARG_JR_D_INC-$
		db		func_ARG_HL-$
		db		func_ARG_R_P-$
		db		func_ARG_BLI_Y_Z-$
		db		func_ARG_IMM16_INC-$
		db		func_ARG_LD-$
		db		func_ARG_IMM8_INC-$
		db		func_ARG_CC_P-$
		db		func_ARG_CC-$
		db		func_ARG_ALU-$
		db		func_ARG_Y_8-$
		db		func_ARG_ERR-$
arguments_end:

func_ARG_ERR:
		jp		prefix_ED_err

func_ARG_HL:
		ld		a,c
		ld		c,0
		call	print_opcode_str_index
		db		'H'-32,'L'-32+128
		db		'I'-32,'Y'-32+128
		db		'I'-32,'X'-32+128

func_ARG_R_P:
		add		00010000b
		and		00110000b
		rlca
		rlca
		rlca
		rlca
		call	print_opcode_str_index8
		db		'S'-32,'P'-32+128
		db		'B'-32,'C'-32+128
		db		'D'-32,'E'-32+128
		db		ARG_HL+128

func_ARG_ROT_Y:
		and		0011100b
		rrca
		rrca
		call	print_opcode_str_index
		db		'R'-32,'L'-32,'C'-32+128
		db		'R'-32,'R'-32,'C'-32+128
		db		'R'-32,'L'-32+128
		db		'R'-32,'R'-32+128
		db		'S'-32,'L'-32,'A'-32+128
		db		'S'-32,'R'-32,'A'-32+128
		db		'S'-32,'L'-32,'L'-32+128
		db		'S'-32,'R'-32,'L'-32+128

func_ARG_Y_8:
		ex		de,hl
		and		00111000b
		jr		cont_imm8_no_inc

func_ARG_IMM8_INC:
		ex		de,hl
		ld		a,(ix+0)
		jr		cont_imm8

func_ARG_IMM16_INC:
		ex		de,hl
		ld		a,(ix+1)
		call	print_hexbyte_A_to_HL
		ld		a,(ix-0)
		inc		ix
cont_imm8:
		inc		ix
cont_imm8_no_inc:
		call	print_hexbyte_A_to_HL
		ld		(hl),'h'
		jr		func_inc_ex_ret

func_ARG_R_Y:
		rrca
		rrca
		rrca
func_ARG_R_Z:
		inc		a
		and		00000111b
		cp		7
		jr		z,.check_IX_IY
		cp		5
		jr		c,.not_H_or_L
		
		add		a,c
		add		a,c
		cp		7
		jr		c,.no_DD_or_FD
		dec		ix			; we have increased IX earlier
							; for no reason.. UGLY FIX
.no_DD_or_FD:
.not_H_or_L:
		call	print_opcode_str_index
		db		'A'-32+128						; 0
		db		'B'-32+128						; 1
		db		'C'-32+128						; 2
		db		'D'-32+128						; 3
		db		'E'-32+128						; 4
		db		'H'-32+128						; 5
		db		'L'-32+128						; 6
		db		ARG_HL,'H'-32+128				; 7  -> 'I'-32,'Y'-32,'H'-32+128
		db		ARG_HL,'L'-32+128				; 8  -> 'I'-32,'Y'-32,'L'-32+128
		db		ARG_HL,'H'-32+128				; 9  -> 'I'-32,'X'-32,'H'-32+128
		db		ARG_HL,'L'-32+128				; 10 -> 'I'-32,'X'-32,'L'-32+128

.check_IX_IY:
		ld		a,c
		call	print_opcode_str_index
		db		'('-32,ARG_HL,')'-32+128
		db		'('-32,ARG_HL,ARG_INDEX_B,')'-32+128
		db		'('-32,ARG_HL,ARG_INDEX_B,')'-32+128

func_ARG_Y:
		ex		de,hl
		rrca
		rrca
		rrca
		and		00000111b
		call	print_hexnibble_A_to_HL
		ex		de,hl
		ret

func_ARG_INDEX_B:
		ex		de,hl
		ld		a,b
		cp		128
		jr		c,.positive_index
		;
		ld		(hl),'-'
		neg
		;jr		.positive_index_skip
		db		00010001b			; LD DE,nnnnn to skip LD (HL),'+'
.positive_index:
		ld		(hl),'+'
.positive_index_skip:
		inc		hl
		call	print_hexbyte_A_to_HL
		ld		(hl),'h'
		jr		func_inc_ex_ret
		
func_ARG_LD:
		ex		de,hl
		ld		(hl),'L'
		inc		hl
		ld		(hl),'D'
		jr		func_inc_ex_ret

func_ARG_JR:
		ex		de,hl
		ld		(hl),'J'
		inc		hl
		ld		(hl),'R'
func_inc_ex_ret:
		inc		hl
		ex		de,hl
		ret

func_ARG_BLI_Y_Z:
		jr		func_ARG_BLI_Y_Z_real

func_ARG_JR_D_INC:
		ld		a,(ix)
		inc		ix
		push	ix
		pop		hl
		ld		b,0
		ld		c,a
		add		a,a
		jr		nc,.positive
		dec		b
.positive:
		add		hl,bc
		ex		hl,de
		ld		a,d
		call	print_hexbyte_A_to_HL
		ld		a,e
		call	print_hexbyte_A_to_HL
		ld		(hl),'h'
		jr		func_inc_ex_ret

func_ARG_CC_P:
		;and		00110000b	; not needed since the only case this is used
		rrca					; upper 2 bits are 00b
func_ARG_CC:
		call	print_opcode_str_index8_shift
		db		'N'-32,'Z'-32+128
		db		'Z'-32+128
		db		'N'-32,'C'-32+128
		db		'C'-32+128
		db		'P'-32,'O'-32+128
		db		'P'-32,'E'-32+128
		db		'P'-32+128
		db		'M'-32+128

func_ARG_ALU:
		call	print_opcode_str_index8_shift
		db		'A'-32,'D'-32,'D'-32+64,'A'-32,','-32+128	; ADD ..
		db		'A'-32,'D'-32,'C'-32+64,'A'-32,','-32+128	; ADC ..
		db		'S'-32,'U'-32,'B'-32+64+128						; SUB ..
		db		'S'-32,'B'-32,'C'-32+64,'A'-32,','-32+128		; SBC ..
		db		'A'-32,'N'-32,'D'-32+64+128						; AND .. 
		db		'X'-32,'O'-32,'R'-32+64+128						; XOR ..
		db		'O'-32,'R'-32+64+128							; OR ..
		db		'C'-32,'P'-32+64+128							; CP ..

func_ARG_BLI_Y_Z_real:
		and		00110011b
		ld		l,a
		rlca
		rlca
		or		l
		and		00001111b		
		call	print_opcode_str_index
		db		ARG_LD,'I'-32+128					; a=4,b=0
		db		'C'-32,'P'-32,'I'-32+128			; a=4,b=1
		db		'I'-32,'N'-32,'I'-32+128			; a=4,b=2
		db		'O'-32,'U'-32,'T'-32,'I'-32+128		; a=4,b=3
		db		ARG_LD,'D'-32+128					; a=5,b=0
		db		'C'-32,'P'-32,'D'-32+128			; a=5,b=1
		db		'I'-32,'N'-32,'D'-32+128			; a=5,b=2
		db		'O'-32,'U'-32,'T'-32,'D'-32+128		; a=5,b=3
		db		ARG_LD,'I'-32,'R'-32+128			; a=6,b=0
		db		'C'-32,'P'-32,'I'-32,'R'-32+128		; a=6,b=1
		db		'I'-32,'N'-32,'I'-32,'R'-32+128		; a=6,b=2
		db		'O'-32,'T'-32,'I'-32,'R'-32+128		; a=6,b=1
		db		ARG_LD,'D'-32,'R'-32+128			; a=6,b=0
		db		'C'-32,'P'-32,'D'-32,'R'-32+128		; a=6,b=1
		db		'I'-32,'N'-32,'D'-32,'R'-32+128		; a=6,b=2
		db		'O'-32,'T'-32,'D'-32,'R'-32+128		; a=6,b=18

;

print_hexbyte_A_to_HL:
		push	af
		rrca
		rrca
		rrca
		rrca
		call	print_hexnibble_A_to_HL
		pop		af
print_hexnibble_A_to_HL:
		and		00001111b
		cp		10
		jr c,	.between_0_and_9
		add		'A'-'0'-10
.between_0_and_9:
		add		'0'
		ld		(hl),a
		inc		hl
		ret
dis_z80_end:

		DISPLAY	"esxMON size:", /D, dis_z80_end-dis_z80


		ENDMODULE