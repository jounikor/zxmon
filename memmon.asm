;-----------------------------------------------------------------------------
;
; (c) 2026 Jouni 'Mr.Spiv' Korhonen
;
;

		DEVICE	ZXSPECTRUM128
		SLDOPT	COMMENT WPMEM, LOGPOINT, ASSERTION

		MODULE	memmon

		INCLUDE	"zxmon.inc"

PAGE_VAR	equ		0x5b5c

;-----------------------------------------------------------------------------
;
; Display memory as hex and ascii. Both 8 and 16 lines of output supported.
;
; Input:
;  IX = ptr to sysvars, which contains tokenized ARGV[]..
;
; Returns:
;  A = 0 when no error and A contains file handle.
;  A > 0 and A contains error code.
;
f_mon16
		ld		b,15
		db		00010001b		; LD DE,nn
f_mon8:
		ld		b,7
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
		
.mem_display_main:
		push	bc
		push	ix
		pop		hl
		push	hl
		
		; print address
		call	zxmon.string.word_in_DE_to_ascii
		ld		(hl),':'
		inc		l
		ld		(hl),' '
		inc		l

		;
		ld		b,4
		push	de
.mem_display_loop:
		ld		a,(de)
		inc		de
		call	zxmon.string.byte_in_A_to_ascii
		ld		a,(de)
		inc		de
		call	zxmon.string.byte_in_A_to_ascii
		ld		(hl),' '
		inc		l
		djnz	.mem_display_loop
		
		;
		pop		de
		ld		(hl),"'"
		inc		l
		ld		b,8
.mem_ascii_loop:
		ld		a,(de)
		inc		de
		cp		' '
		jr c,	.force_dot
		cp		'~'+1
		jr c,	.mem_to_ascii
.force_dot:
		ld		a,'.'
.mem_to_ascii:
		ld		(hl),a
		inc		l
		djnz	.mem_ascii_loop
		;
		ld		(hl),"'"
		inc		l
		ld		(hl),0
		;

		pop		hl
		push	de
		ld		de,0x1f00
		call	zxmon.input_and_screen.print_at
		call	zxmon.input_and_screen.scroll_up_whole_screen
		pop		de
		pop		bc
		djnz	.mem_display_main
		;

		ld		(ix+zxmon.VARS.mem_addr+0),e
		ld		(ix+zxmon.VARS.mem_addr+1),d
		xor		a
		ret


;-----------------------------------------------------------------------------
;
; Poke bytes and strings into memory. 
;
; Input:
;  IX = ptr to sysvars, which contains tokenized ARGV[]..
;
; Returns:
;  A = 0 when no error and A contains file handle.
;  A > 0 and A contains error code.
;
f_poke:
		ld		a,(ix+zxmon.VARS.input_argc)
		cp		3
		jr nc,	.enough_parameters
		ld		a,CMD_ENUMPARAMS
		ret
		;
.enough_parameters:
		ld		d,ixh
		ld		e,(ix+zxmon.VARS.input_argv+1)
		
		; Get POKE address
		call	zxmon.string.str_to_number
		jr nc,	.num_conversion_ok
.num_conversion_failed:
		ld		a,CMD_ENUMCONV
		ret
		; 
.num_conversion_ok:
		ld		(ix+zxmon.VARS.mem_addr+0),l
		ld		(ix+zxmon.VARS.mem_addr+1),h

		; Get ARGC-2
		ld		b,(ix+zxmon.VARS.input_argc)
		dec		b
		dec		b

		;  Loop through all remaining ARGS
		ld		d,ixh
		ld		e,zxmon.VARS.input_argv+2-1
.args_loop:
		inc		e
		push	de
		push	hl
		ld		a,(de)
		ld		e,a
		ld		a,(de)
		;cp		"'"
		cp		0x27
		jr nz,	.got_number
		;
		inc		e
.char_loop:
		ld		a,(de)
		inc		e
		cp		" "
		jr z,	.char_loop_done
		and		a
		jr z,	.char_loop_done
		ld		(hl),a
		inc		hl
		jr		.char_loop
.char_loop_done:
		pop		de
		pop		de
		djnz	.args_loop
		xor		a
		ret

.got_number:
		call	zxmon.string.str_to_number
		ld		a,l
		pop		hl
		pop		de
		jr c,	.num_conversion_failed
		ld		(hl),a
		inc		hl
		;
		djnz	.args_loop
		xor		a
		ret

;-----------------------------------------------------------------------------
;
; Fill memory range with a byte value. 
;
; Input:
;  IX = ptr to sysvars, which contains tokenized ARGV[]..
;
; Returns:
;  A = 0 when no error and A contains file handle.
;  A > 0 and A contains error code.
;
f_fill:
		ld		a,(ix+zxmon.VARS.input_argc)
		cp		4
		jr z,	.enough_parameters
		ld		a,CMD_ENUMPARAMS
		ret
		;
.enough_parameters:
		ld		d,ixh
		ld		e,(ix+zxmon.VARS.input_argv+1)
		
		; Get start address
		call	zxmon.string.str_to_number
		jr nc,	.start_conversion_ok
.num_conversion_failed:
		ld		a,CMD_ENUMCONV
		ret
		; 
.start_conversion_ok:
		ld		(ix+zxmon.VARS.mem_addr+0),l
		ld		(ix+zxmon.VARS.mem_addr+1),h

		ld		d,ixh
		ld		e,(ix+zxmon.VARS.input_argv+2)
		
		; Get end address
		call	zxmon.string.str_to_number
		jr c,	.num_conversion_failed
		;
.end_conversion_ok:
		push	hl
		;
		;
		;  fill byte
		ld		d,ixh
		ld		e,zxmon.VARS.input_argv+3
.args_loop:
		ld		a,(de)
		ld		e,a
		ld		a,(de)
		;cp		"'"
		cp		0x27
		jr nz,	.got_number
		; C_flag = 0.. following code does not change flags
		inc		de
		ld		a,(de)
		ld		l,a
		jr		.do_fill
		;
.got_number:
		call	zxmon.string.str_to_number
.do_fill:
		pop		de
		jr c,	.num_conversion_failed
		ld		b,l
		ld		l,(ix+zxmon.VARS.mem_addr+0)
		ld		h,(ix+zxmon.VARS.mem_addr+1)
		; 
		;  B = byte to fill woth
		; DE = end address
		; HL = start address
		;
.fill_loop:
		ld		(hl),b
		inc		hl
		ld		a,e
		sub		l
		jr nz,	.fill_loop
		ld		a,d
		sub		h
		jr nz,	.fill_loop
		;
		ret


;-----------------------------------------------------------------------------
;
; Change memory bank at $c000. The command also updates Spectrum's
; SYSVARs (23388) with the active page number.
;
; Input:
;  IX = ptr to sysvars, which contains tokenized ARGV[]..
;
; Returns:
;  A = 0 when no error and A contains file handle.
;  A > 0 and A contains error code.
;
f_bank:
		ld		d,ixh
		ld		e,(ix+zxmon.VARS.input_argv+1)
		call	zxmon.string.str_to_number
		jr nc,	.num_conversion_ok
.num_conversion_failed:
		ld		a,CMD_ENUMCONV
		ret
		; 
.num_conversion_ok:
		ld		a,l
		cp		8
		jr c,	.value_in_bounds

		ld		a,CMD_EBANK
		ret
		;
.value_in_bounds:
		di
		ld		a,(PAGE_VAR)
		and		11111000b
		or		l
		ld		(PAGE_VAR),a
		ld		bc,0x7ffd
		out		(c),a
		ei
		xor		a
		ret


;-----------------------------------------------------------------------------
;
; CALL a subroutine
;
; Input:
;  IX = ptr to sysvars, which contains tokenized ARGV[]..
;
; Returns:
;  A = 0 when no error and A contains file handle.
;  A > 0 and A contains error code.
;
f_call:
		ld		a,(ix+zxmon.VARS.input_argc)
		cp		2
		jr nc,	.enough_parameters
		ld		a,CMD_ENUMPARAMS
		ret
		;
.enough_parameters:
		ld		d,ixh
		ld		e,(ix+zxmon.VARS.input_argv+1)
		
		; Get CALL address
		call	zxmon.string.str_to_number
		jr nc,	.num_conversion_ok
.num_conversion_failed:
		ld		a,CMD_ENUMCONV
		ret
		; 
.num_conversion_ok:
		ld		(ix+zxmon.VARS.mem_addr+0),l
		ld		(ix+zxmon.VARS.mem_addr+1),h

		ld		de,.return
		push	ix
		push	de
		push	hl

		; Load register file..
		call	load_registers
		ret
.return:
		call	save_registers
		; restore
		pop		ix
		xor		a
		ret

;
; Inputs:
;  IX = ptr to sys_vars
;  Stack -2 = original IX
;
;
save_registers:
		di
		ld		(zxmon.sys_regs.r_sp),sp
		ld		sp,zxmon.sys_regs_end
		push	af
		push	bc
		push	de
		push	hl
		push	ix
		push	iy
		ex		af,af'
		push	af
		ex		af,af'
		exx
		push	bc
		push	de
		push	hl
		exx
		ld		hl,(zxmon.sys_regs.r_sp)
		ld		sp,hl
		; for the saved SP adjust return address from stack..
		inc		hl
		inc		hl
		ld		(zxmon.sys_regs.r_sp),hl
		ei
		ret

load_registers:
		di
		ld		(zxmon.sys_regs.r_sp_save),sp
		ld		sp,zxmon.sys_regs.r_hl_p
		exx
		pop		hl
		pop		de
		pop		bc
		exx
		ex		af,af'
		pop		af
		ex		af,af'
		pop		iy
		pop		ix
		pop		hl
		pop		de
		pop		bc
		pop		af
		ld		sp,(zxmon.sys_regs.r_sp_save)
		ei
		ret



;-----------------------------------------------------------------------------
;
; Dump current registers' values
;
; Input:
;  IX = ptr to sysvars, which contains tokenized ARGV[]..
;
; Returns:
;  A = 0 when no error.
;  A > 0 and A contains error code.
;
f_registers:
		ld		a,(ix+zxmon.VARS.input_argc)
		cp		1
		jr		z,.display_registers
		cp		3
		jr nc,	.enough_parameters
		ld		a,CMD_ENUMPARAMS
		ret
		;
.enough_parameters:
		; Find which register to change..
		ld		d,ixh
		ld		e,(ix+zxmon.VARS.input_argv+1)
		ld		a,(de)
		ld		b,a
		inc		de
		ld		a,(de)
		ld		c,a
		inc		de
		ld		a,(de)
		and		a
		jr		nz,.not_end_of_str
		ld		a,' '
.not_end_of_str:
		or		0x80
		ld		d,a
		ld		hl,s_registers
		ld		e,0
.find_register_pair_loop:
		dec		e
		dec		e
		; BCD contains user input for a register
		; D also has bit 7 set
		ld		a,(hl)
		inc		hl
		and		a
		jr		nz,.not_end_yet
		ld		a,CMD_EVALUE
		ret
.not_end_yet:
		cp		b
		jr		nz,.find_str_end2
		ld		a,(hl)
		inc		hl
		cp		c
		jr		nz,.find_str_end1
		ld		a,(hl)
		inc		hl
		cp		d
		jr		z,.found_register_pair
		jr		.find_register_pair_loop
.find_str_end2:
		inc		hl
.find_str_end1:
		inc		hl
		jr		.find_register_pair_loop
.found_register_pair
		ld		d,-1
		ld		hl,zxmon.sys_regs_end
		add		hl,de
		push	hl

		; get value to reg
		ld		d,ixh
		ld		e,(ix+zxmon.VARS.input_argv+2)
		call	zxmon.string.str_to_number
		pop		de
		jr nc,	.num_conversion_ok
.num_conversion_failed:
		ld		a,CMD_ENUMCONV
		ret
		; 
.num_conversion_ok:
		ex		de,hl
		ld		(hl),e
		inc		hl
		ld		(hl),d
		xor		a
		ret
		;
.display_registers:
		push	ix
		push	ix
		pop		hl
		ld		l,zxmon.VARS.output_buf
		ld		de,s_registers
		ld		bc,0x0403
		ld		ix,zxmon.sys_regs_end
.registers_print_loop:
		push	bc
		push	hl
.copy_string:
		ld		a,(de)
		inc		de
		add		a,a
		push	af
		rrca
		ld		(hl),a
		inc		hl
		pop		af
		jr		nc,	.copy_string
		;

		ld		(hl),' '
		inc		hl

		push	de
		dec		ix
		ld		d,(ix+0)
		dec		ix
		ld		e,(ix+0)
		call	zxmon.string.word_in_DE_to_ascii
		ld		(hl),' '
		inc		hl
		ld		(hl),' '
		inc		hl
		pop		de
		dec		c
		jr		nz,.copy_string
		ld		(hl),0
		;
		pop		hl
		; DE = ptr to next in s_registers
		; HL = ptr to start of output buffer

		push	hl
		push	de
		ld		b,0
		ld		de,AT_LOW_LEFT
		call	zxmon.input_and_screen.print_at
		call	zxmon.input_and_screen.scroll_up_whole_screen
		pop		de
		pop		hl
		pop		bc
		ld		c,3
		djnz	.registers_print_loop:

		pop		ix
		xor		a
		ret

s_registers:
		;        0   0         1         2
		;        0   4         4         4 
		dc		"af "
		dc		"bc "
		dc		"de "
		dc		"hl "
		dc		"ix "
		dc		"iy "
		dc		"af'"
		dc		"bc'"
		dc		"de'"
		dc		"hl'"
		dc		"sp "
		dc		"pc "
		db		0

		ENDMODULE
