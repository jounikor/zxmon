		DEVICE	ZXSPECTRUM128
		SLDOPT	COMMENT WPMEM, LOGPOINT, ASSERTION

		MODULE	commands

		INCLUDE	"zxmon.inc"


;-----------------------------------------------------------------------------
;
; Tokenize input buffer and find out the command given in ARGV[0].
;
; Inputs:
;  IX = system variables
;
; Returns:
;   Z_flag = 1 if ARGC == 0 i.e. no command or parameters was given.
;   Z_flag = 0 if ARGC > 0
;   A = ARGC
;  DE = input_argv[0] if argc > 0
;  HL = ptr to function to call if argc > 0
;
command_dispatcher:
		call	zxmon.input_and_screen.tokenize_input_buffer
		and		a
		; Return if ARGC == 0
		ret z
		;
		; Prepare for a brute for search..
		; D = IXH
		; H = IXH
		push	af
		ld		hl,s_command_array
		ld		e,(ix+VARS.input_argv)
		push	de
		; DE = ptr to argv[0]
		; HL = s_command_array
.command_search_loop:
		ld		b,(hl)
		push	hl
		inc		hl
		push	de
		call	zxmon.string.strncmp
		pop		de
		jr c,	.command_found:
		pop		hl
		ld		b,0
		ld		c,(hl)
		add		hl,bc
		inc		hl
		inc		hl
		inc		hl
		jr		.command_search_loop
.command_found:
		ld		a,(hl)
		inc		hl
		ld		h,(hl)
		ld		l,a
		ld		(ix+zxmon.VARS.cmd_func+0),l
		ld		(ix+zxmon.VARS.cmd_func+1),h
		pop		de
		pop		de
		pop		af
		;  A = argc
		; DE = input_argv[0]
		; HL = ptr to found command function
		;
		ret

;-----------------------------------------------------------------------------
;
; Execute found command and set Z_flag according on return.
;
; Returns:
;  Z_flag = 0 in case of error
;       A > 0 Error code
;  Z_flag = 1 and A = 0 is a special case for ARGC = 0 and no error in general.
;
; Trashes:
;  A,BC,DE,HL
;
command_execute:
		ld		a,(ix+zxmon.VARS.input_argc)
		and		a
		ret z
		;
        ld      hl,command_error_check
        push    hl
        ld		l,(ix+zxmon.VARS.cmd_func+0)
		ld		h,(ix+zxmon.VARS.cmd_func+1)
		ld		b,0
		jp		(hl)
command_error_check:
        and     a
        ret

;-----------------------------------------------------------------------------
;
; Generic error code output dispatcher. In case of unknown error code
; standard "syntax error" is output.
;
; Input:
;  A = Error code
;
; Returns:
;  None.
;
; Trashes:
;  A,BC,DE,HL
;
command_error:
        and     a
        ret z

        dec     a
        jr nz,  .not_syntax_error
        ; CMD_ESYNTAX
        ld      hl,s_err_syntax_error
        jr      f_error_print_hl
.not_syntax_error:
        dec     a
        jr nz,  .not_num_parameters
        ; CMD_ENUMPARAMS
        ld      hl,s_err_num_params
        jr      f_error_print_hl
.not_num_parameters:
        dec     a
        jr nz,  .not_num_conversion
        ; CMD_ENUMCONV
        ld      hl,s_err_num_conversion
        jr      f_error_print_hl
.not_num_conversion:
        dec     a
        jr nz,  .not_atari
        ; CMD_EATARI
        ld      hl,s_err_atari
        jr      f_error_print_hl
.not_atari:
        dec     a
        jr nz,  .not_c64
        ; CMD_EC64
        ld      hl,s_err_c64
        jr      f_error_print_hl
.not_c64:
		dec		a
		jr nz,	.not_esxdos
		; CMD_EESXDOS
		ld		d,ixh
		ld		e,VARS.output_buf
		ld		a,(ix+VARS.file_errno)
		; Check if we have EUSERABORT
		and		a
		jr nz,	.not_user_abort
		;
		ld		hl,s_err_user_abort
		jr		f_error_print_hl
		;
.not_user_abort:
		push	de
		ld		hl,s_err_esxdos
		ld		bc,S_ERR_ESXDOS_LEN
		ldir
		push	de
		ld		h,b
		ld		l,a
		call	zxmon.string.hl_to_decstr
		pop		de
		ld		c,a
		inc		c			; add NIL
		ldir
		pop		hl
		jr		f_error_print_hl
		;
.not_esxdos:
		dec		a
		jr nz,	.not_bank
		;
		ld		hl,s_err_page
		jr		f_error_print_hl

.not_bank:


        ; generic syntax error
f_error:
        ld      hl,s_err_syntax_error
f_error_print_hl:
		ld		b,0
		call	zxmon.input_and_screen.print_at_bottom
		jp  	zxmon.input_and_screen.scroll_up_whole_screen

;
;
f_atari:
		ld		a,CMD_EATARI
        ret

f_c64:
		ld		a,CMD_EC64
        ret

f_exit:
		set		VARS_EXIT_F,(ix+VARS.flags)
		ld		a,CMD_EOK
        ret



;-----------------------------------------------------------------------------
;
; Print help
;
f_help:
        ld      hl,s_help
		ld		b,(hl)
		inc		hl
.help_loop:
		push	bc
		ld		b,0
		call	zxmon.input_and_screen.print_at_bottom
		call 	zxmon.input_and_screen.scroll_up_whole_screen
		pop		bc
		djnz	.help_loop
		xor		a
		ret


s_command_array:
		db		6,"ATARI",0
		dw		f_atari
		
		db		4,"C64",0
		dw		f_c64

		db		3,"mm",0
		dw		zxmon.memmon.f_mon16

		db		2,"m",0
		dw		zxmon.memmon.f_mon8

		db		2,"p",0
		dw		zxmon.memmon.f_poke

        db      2,"b",0
        dw      zxmon.memmon.f_bank

        db      3,"ls",0
        dw      zxmon.fileio.f_ls

        db      3,"cd",0
        dw      zxmon.fileio.f_cd

		db		2,"r",0
		dw		zxmon.fileio.f_read

		db		2,"x",0
		dw		f_exit

		db		2,"?",0
		dw		f_help
		db		2,"h",0
		dw		f_help
		
		db		0			; Must be the last..
		dw		f_error


s_err_syntax_error:
        db      "Syntax error",0
s_err_num_params:
        db      "Wrong number of parameters",0
s_err_num_conversion:
        db      "Invalid HEX/DEC number",0
s_err_atari:
		db		"IS T3H SHIT!",0
s_err_c64:
		db		"64K RAM SYSTEM 38911 BASIC BYTES FREE",0
s_err_esxdos:
		db		"ESXDOS error "
S_ERR_ESXDOS_LEN	equ	13
s_err_user_abort:
		db		"Command aborted",0
s_err_page:
		db		"Invalid RAM page",0

s_help:
		db		10
		;        0         1         2.        3          4
		;        0123456789012345678901234567890123456789012
		db		"COMMAND SYNTAX:",0
		db		"m [<addr>]                   :show 8 lines",0
		db		"mm [<addr>]                 :show 16 lines",0
		db		"p <addr> [<num>|'<str>] ..           :poke",0
		db		"b <bank>                     :set RAM page",0
		db		"ls                       :show current dir",0
		db		"cd <dir>               :change current dir",0
		db		"r <file> <addr> [<off> [<len>]] :read file",0
		db		"w <file> <addr> <len>          :write file",0
		db		"x                           :exit to BASIC",0




        ENDMODULE