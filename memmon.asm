

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
		ld		b,16
		db		00010001b		; LD DE,nn
f_mon8:
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

		ld		a,CMD_EVALUE
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

		ENDMODULE
