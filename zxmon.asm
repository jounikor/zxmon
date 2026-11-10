;-----------------------------------------------------------------------------
;
; (c) 2026 Jouni 'Mr.Spiv' Korhonen
;
;
;
; This code is supposed to be ROMable.
;

		DEVICE	ZXSPECTRUM128
		SLDOPT	COMMENT WPMEM, LOGPOINT, ASSERTION

		org		$8000


		MODULE	zxmon

main:
		; We reference the sysvars via IX. sysvars are 256 byte alogned and
		; the size of the struct never exceeds 256 bytes.
m:		ld		ix,sys_vars
		call	init_sys_vars

		; Magic copyright and version greeting output
		ld		hl,s_copyright
		ld		de,AT_LOW_LEFT
		ld		b,0
		call	input_and_screen.print_at
		call	input_and_screen.scroll_up_whole_screen
		ei

		; Main loop does scanning of keys, parsing the input buffer and 
		; calling the appropriate command function. For "conveniense" the
		; loop is synced to 50Hz..
main_loop:
		halt
		; Read keys and update the input buffer line accordingly
		call	input_and_screen.scan_keys
		call	input_and_screen.update_input_buffer
		; Dispatch command while input buffer still exists
		bit		BUF_ENTER_F,(ix+VARS.input_buf_flags)
		push	af

		; If enter was pressed scan for commands..
		call nz,	commands.command_dispatcher

		; print input buffer and possibly scroll screen.
		call	input_and_screen.print_input_buffer
		
		; Execute wanted commands here.. if enter was pressed.
		pop		af
		call nz,	commands.command_execute
		call nz,	commands.command_error

		; Commandline update and cursor blinking
		call	input_and_screen.blink_cursor
		bit		VARS_EXIT_F,(ix+VARS.flags)
		jr z,	main_loop
		ld		bc,0
_gonna_exit_to_basic:
		ret

;
; Inputs:
;  IX = prt to system variables
init_sys_vars:
		push	ix
		pop		hl

		; clear structure
		ld		b,VARS
.zero_mem:
		ld		(hl),0
		inc		hl
		djnz	.zero_mem

		; place constants
		ld		(ix+VARS.input_cur_timer),BLINK_T
		ld		(ix+VARS.key_rep_timer1),KEY_REP_TIMER1
		ld		(ix+VARS.key_rep_timer2),KEY_REP_TIMER2
		ret

s_copyright:	dc	"esxMON V0.01 (C) 20261109 Mr.Spiv/ScoopeX"

		INCLUDE	"zxmon.inc"		
		INCLUDE "string.asm"
		INCLUDE "math.asm"
		INCLUDE	"memmon.asm"
		INCLUDE	"commands.asm"
		INCLUDE	"fileio.asm"
		INCLUDE	"disasm.asm"
		INCLUDE	"input_and_screen.asm"

; System variables must be 256 bytes aligned.
;
		ALIGN	256
sys_vars:	zxmon.VARS

		SAVETAP	"zxmon.tap",main
		SAVESNA	"zxmon.sna",main
		ENDMODULE


