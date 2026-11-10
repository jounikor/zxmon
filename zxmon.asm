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
m:
	IFDEF DOTCMD
		push	hl
	ENDIF
		ld		ix,sys_vars
		call	init_sys_vars
		; Magic copyright and version greeting output
		ld		hl,s_copyright
		ld		de,AT_LOW_LEFT
		ld		b,0
		call	input_and_screen.print_at
		call	input_and_screen.scroll_up_whole_screen
		ei

	IFDEF DOTCMD
		; Check for command line parameters in case of .command
		pop		hl
		ld		hl,fake
		ld		a,h
		or		l						; Clears C_flag
		call	nz,parse_cmdline
	ENDIF
		; Main loop does scanning of keys, parsing the input buffer and 
		; calling the appropriate command function. For "conveniense" the
		; loop is synced to 50Hz..
		db		$fe
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

		xor		a
_gonna_exit_to_basic:
		ld		bc,0
		ret

;
; Inputs:
;  IX = prt to system variables
;
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

	IFDEF DOTCMD
		; Check for command line parameters in case of .command
parse_cmdline:
		ex		de,hl
		push	ix
		pop		hl
		push	hl
		; inject 'r'ead command 
		ld		(hl),'r'
		inc		l
		ld		(hl),' '
		inc		l
		ld		b,MAXX-3
.copy_loop:
		ld		a,(de)
		and		a			; '\0'
		jr		z,.cmd_end
		cp		':'
		jr		z,.cmd_end
		bit		7,a
		res		7,a
		ld		(hl),a
		inc		hl
		jr		nz,.cmd_end
		inc		de
		djnz	.copy_loop
.cmd_end:
		xor		a
		ld		(hl),a
		; Fake enter
		set		zxmon.BUF_ENTER_F,(ix+zxmon.VARS.input_buf_flags)
		ld		(ix+zxmon.VARS.input_buf_end),l
		ld		(ix+zxmon.VARS.input_cur_oldx),a
		ld		(ix+zxmon.VARS.input_buf_pend),0
		; Output for beatification..
		pop		hl
		ld		de,AT_LOW_LEFT
		ld		b,0
		jp		input_and_screen.print_at

fake:
		dc		"bin/ls c000"
	ENDIF

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


