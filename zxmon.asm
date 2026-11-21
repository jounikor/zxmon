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

	IFDEF DOTCMD
		org		$2000
	ELSE
		org		$8000
	ENDIF


		MODULE	zxmon

zxmon_sta:
main:
	IFDEF REGCMD
		ld		(zxmon.sys_regs.r_sp_save),sp
		call	zxmon.memmon.save_registers
	ENDIF
		; We reference the sysvars via IX. sysvars are 256 byte alogned and
		; the size of the struct never exceeds 256 bytes.
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
		ld		hl,(zxmon.sys_regs.r_hl)
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
		call	nz,commands.command_dispatcher

		; print input buffer and possibly scroll screen.
		call	input_and_screen.print_input_buffer
		
		; Execute wanted commands here.. if enter was pressed.
		pop		af
		call	nz,commands.command_execute
		call	nz,commands.command_error

		; Commandline update and cursor blinking
		call	input_and_screen.blink_cursor
		bit		VARS_EXIT_F,(ix+VARS.flags)
		jr		z,main_loop

		xor		a
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
		xor		a
		ld		b,a
.zero_mem:
		ld		(hl),a
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
		; inject 'l'ead command 
		ld		(hl),'l'
		inc		l
		ld		(hl),' '
		inc		l
		ld		b,MAXX-3
.copy_loop:
		ld		a,(de)
		and		a			; '\0'
		jr		z,.cmd_end
		cp		0x0d
		jr		z,.cmd_end
		cp		':'
		jr		z,.cmd_end
		ld		(hl),a
		inc		hl
		inc		de
		djnz	.copy_loop
.cmd_end:
		xor		a
		ld		(hl),a
		; Fake enter
		set		zxmon.BUF_ENTER_F,(ix+zxmon.VARS.input_buf_flags)
		ld		(ix+zxmon.VARS.input_buf_end),l
		ld		(ix+zxmon.VARS.input_cur_oldx),a
		ld		(ix+zxmon.VARS.input_buf_pend),a
		; Output for beatification..
		pop		hl
		ld		de,AT_LOW_LEFT
		ld		b,a
		jp		input_and_screen.print_at

	ENDIF

s_copyright:	dc	"esxMON V0.03 (C) 20261121 Mr.Spiv/ScoopeX"

		INCLUDE	"zxmon.inc"		
		INCLUDE "string.asm"
		INCLUDE "math.asm"
		INCLUDE	"memmon.asm"
		INCLUDE	"commands.asm"
		INCLUDE	"fileio.asm"
		INCLUDE	"disasm.asm"
		INCLUDE	"input_and_screen.asm"
		ds		zxmon.REGS
		ALIGN	512
zxmon_end:

; System variables must be 256 bytes aligned.
;
	IFDEF REGCMD
		ORG		(($ + 255) & 0xff00) - zxmon.REGS
sys_regs:	zxmon.REGS
sys_regs_end:
	ELSE
		ALIGN	256
	ENDIF
sys_vars:	zxmon.VARS

		;SAVETAP	"zxmon.tap",main
		SAVESNA	"zxmon.sna",main
		SAVEBIN	"esxmon",zxmon_sta,zxmon_end-zxmon_sta
		ENDMODULE


