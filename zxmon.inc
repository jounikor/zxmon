;
;
;
;

						;0         1         2         3         4
						;012345678901234567890123456789012345678901
COPYRIGHT		db		"ZXMON V0.01 (C) 20260830 Mr.Spiv/ScoopeX",0

; Constants
MAXX			equ		42
MAXY			equ		32
BLINK_T			equ		20
AT_LOW_LEFT		equ		((MAXY-1)<<8)
SZ_WHOLE_SCR	equ		((MAXY-1)<<8)|32
SZ_CONV_STR		equ		10

; VARS.flags
VARS_EXIT_F		equ		7

; VARS.inout_buf_flags
BUF_ENTER_F		equ		1
BUF_DIRTY_F		equ		0

; Input buffer special key codes
KEY_CURSOR_LEFT	equ		0x80+19	; raw keycodes
KEY_CURSOR_RGHT	equ		0x80+22	;
KEY_DELETE		equ		0x80+20	;
KEY_ENTER		equ		30
RAW_KEY_NONE	equ		0x00	; 6 lowest bits count

; return codes
CMD_EOK             equ     0
CMD_ESYNTAX         equ     1       ; generic SYNTAX ERROR
CMD_ENUMPARAMS      equ     2       ; too few parameters for the command
CMD_ENUMCONV        equ     3       ; hex/dec number conversion failed
CMD_EATARI          equ     4
CMD_EC64            equ     5
CMD_EESXDOS			equ		6
CMD_EVALUE			equ		7		; Inout value is invalid / out of bounds


		STRUCT	VARS
		; these two buffer must fit into 256 bytes, and indexin 
input_buf			TEXT MAXX+1,{0,0,0}
output_buf			TEXT MAXX+1,{0,0,0}
conversion_buf		ds	SZ_CONV_STR+1
input_argc			db	0
input_buf_end		db	0
input_buf_pend		db	0
input_cur_oldx		db	0
input_cur_newx		db	0
input_buf_flags		db	0
input_cur_timer		db	BLINK_T

flags				db	0
key_raw_pressed		db	0
key_raw_previous	db	0
key_cooked			db	0
cmd_func			dw	0
mem_addr			dw	0
mem_bank			db	0
cmd_len				db	0
file_handle			db	0
file_errno			db	0
; Note: dir_entry, stat_entry and ARGV all are overlaid using the memory area
dir_entry			ds	0
stat_entry			ds	0
input_argv			ds	(MAXX/2)+1
extra_space			ds	136-MAXX/2
		ENDS

		DISPLAY	"VARS size: ",/H,VARS
		DISPLAY	"dir_entry: ",/H,VARS.dir_entry
		ASSERT	VARS<=256,VARS structure over 256 bytes
		ASSERT	VARS.dir_entry<128,VARS.dir_entry index over 127


