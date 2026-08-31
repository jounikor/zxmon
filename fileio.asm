		DEVICE	ZXSPECTRUM128
		SLDOPT	COMMENT WPMEM, LOGPOINT, ASSERTION

		MODULE	fileio

        INCLUDE "errors.inc"
        INCLUDE "esxdos.inc"
        INCLUDE "zxmon.inc"

;-----------------------------------------------------------------------------
;
; Read and output directory content.
;
; Input:
;  IX = ptr to sysvars, which contains tokenized ARGV[] with an ls command
;       and possible path.. Only the first parameter is considered i.e.
;       ARGV[1], rest are neglected.
;
; Return:
;  C_flag = 0 when no error and A contains file handle.
;  C_fkag = 1 and A contains ESXDOS error code.
;
; Trashes:
;  VARS.output_buf content.
;
;

    DISPLAY	"ls(): ",/H,f_ls

f_ls:
        push    ix
        pop     hl
        push    hl

		; Important.. set errno to EOK
		ld		(ix+VARS.file_errno),EOK

		;
		ld		a,(ix+VARS.input_argc)
		dec		a
		jr nz,	.got_path
		ld		hl,current_dir_path
		jr		.current_path
.got_path:
        ld      l,VARS.input_argv+1
        ; if ARGC=1 then ARGV[1] points to empty NIL terminated string
        ; otherwise ARGV[1] points to NIL terminated path
        ld      l,(hl)
.current_path:
		ld      a,CUR_DRIVE
        ld      b,FA_OPEN_EX
        push    hl
        pop     ix

        rst     8
        db      F_OPENDIR
        pop     ix
        ld      (ix+VARS.file_handle),a
        jp c,   esxdos_error_no_close

.ls_loop:
        push    ix
        ld      a,(ix+VARS.file_handle)
        ld      ixl,VARS.dir_entry
		push	ix

        rst     8
        db      F_READDIR
        pop     hl
		pop		ix
        jp c,   esxdos_error

		; There was no more dir entries if A=0
        and		a           ; Clears C_flag
		jp z,	esxdos_close_and_exit
		call	zxmon.input_and_screen.scan_caps_shift_for_break
		; A=0 && C_flag==0 if break, which happens to be EUSERABORT
		; A=1 && C_flag==1 if no break, which happens to be EOK
		jp nc,	esxdos_error

		call	prep_dir_entry
		call	zxmon.input_and_screen.print_at_bottom
		call	zxmon.input_and_screen.scroll_up_whole_screen
        jr		.ls_loop

;-----------------------------------------------------------------------------
;
; Change current directory.
;
; Input:
;  IX = ptr to sysvars, which contains tokenized ARGV[] with a read command.
;
; Returns:
;  A = 0 when no error.
;  A > 0 and A contains error code.
;
; ESXDOS API:
;   F_CHDIR: Change current directory path
; 
;   A=drive
;   HL=pointer to asciiz dir/path
;

   DISPLAY	"cd(): ",/H,f_cd

f_cd:
        push    ix
		pop		hl
		push	hl

		; Important.. set errno to EOK
		ld		(ix+VARS.file_errno),EOK

		; The new path is a mandatiry parameter.. we handle case where path is not
		; given as NIL terminate empty string. ARGV[ARGC] always points at NIL.
		;
		ld		l,(ix+VARS.input_argv+1)
		push	hl
		pop		ix
		ld      a,CUR_DRIVE
        rst     8
        db      F_CHDIR
        pop     ix
        jp c,   esxdos_error_no_close
		; All ok..
		xor		a
		ret


;-----------------------------------------------------------------------------
;
; Read a file into RAM.
;
; Input:
;  IX = ptr to sysvars, which contains tokenized ARGV[] with a read command,
;       memory location, optional length and filename.
;
; Returns:
;  A = 0 when no error and A contains file handle.
;  A > 0 and A contains error code.
;
;
;
;
;
; F_FSTAT: Get file info/status to buffer at HL. 
;          A=handle
;          HL=buffer
;
; Buffer format:
;    0 <byte>  drive
;    1 <byte>  device
;    2 <byte>  file attributes (like MSDOS)
;    3 <dword> date
;    7 <dword> file size;
;   11
;
; F_STAT: Get file info/status to buffer at DE. 
; 
; A=handle
; HL=Pointer to null-terminated string containg path to dir/file
;
; F_READ: Read BC bytes at HL off file handle A.
;         On return BC=number of bytes actually read.
;         File pointer gets updated.
;
;
; F_SEEK: Seek BCDE bytes. A=handle
;         L=mode (0 from start of file, 1 fwd from current pos,
;           2 bak from current pos).
; 
;   On return BCDE=current file pointer. 
;
;
;
;

	DISPLAY	"f_read()",/H,f_read

f_read:
		ld		(ix+VARS.file_errno),EOK
		ld		a,(ix+zxmon.VARS.input_argc)
		cp		3
		jr nc,	.enough_parameters
		ld		a,CMD_ENUMPARAMS
		ret
		;
.enough_parameters:
		; Get file name into HL and open the file
		push	ix
		pop		hl
		; all this push pop stuff is because when ran from RAM
		; ESXDOS expects IX instead of HL..
		push	hl
		ld		l,(ix+zxmon.VARS.input_argv+1)
		push	hl
		pop		ix
		ld      a,CUR_DRIVE
        ld      b,FA_OPEN_EX|FA_READ|FA_WRITE
        rst     8
        db      F_OPEN
        pop     ix
        jp c,   esxdos_error_no_close
        ld      (ix+VARS.file_handle),a
	
		; Parse load address and optional length and optional offset
		; The command syntax is:
		;  r <filename> <16-bit address> [[<32-bit seek pos> [<16-bit length>]]
		;
		; Parse load RAM address
		ld		d,ixh
		ld		e,(ix+VARS.input_argv+2)
		call	zxmon.string.str_to_number
		jr nc,	.addr_conversion_ok
		call	esxdos_close_and_exit
		ld		a,CMD_ENUMCONV
		ret
.addr_conversion_ok:
		ld		(ix+VARS.mem_addr+0),l
		ld		(ix+VARS.mem_addr+1),h

		; Parse seek position
		ld		a,(ix+VARS.input_argc)
		cp		4
		jr c,	.read_from_0

		ld		d,ixh
		ld		e,(ix+VARS.input_argv+3)
		call	zxmon.string.str_to_number
		jr nc,	.seek_conversion_ok
		call	esxdos_close_and_exit
		ld		a,CMD_ENUMCONV
		ret
.read_from_0:
		ld		hl,0
		ld		d,h
		ld		e,l
.seek_conversion_ok:
		; Seek to position in DEHL and covert it to BCDE
		ld		b,d
		ld		c,e
		ex		de,hl
		ld		a,(ix+VARS.file_handle)
		ld		l,0
		push	ix
		rst		8
		db		F_SEEK
		pop		ix
		jr c,	esxdos_error

		; Convert file length
		ld		a,(ix+VARS.input_argc)
		cp		5
		jr c,	.read_entire_file
		ld		d,ixh
		ld		e,(ix+VARS.input_argv+4)
		call	zxmon.string.str_to_number
		jr nc,	.length_conversion_ok
		call	esxdos_close_and_exit
		ld		a,CMD_ENUMCONV
		ret
.read_entire_file:
		ld		hl,0xffff
.length_conversion_ok:
		ld		d,h
		ld		e,l
		ld		l,(ix+VARS.mem_addr+0)
		ld		h,(ix+VARS.mem_addr+1)
		push	hl
		add		hl,de
		jr nc,	.file_size_ok

		ex		de,hl
		or		a
		sbc		hl,de
		ex		de,hl
.file_size_ok:
		ld		b,d
		ld		c,e
		pop		hl
		ld		a,(ix+VARS.file_handle)
		;  A = file handle
		; BC = bytes to read
		; HL = memory address
		push	ix
		push	hl
		pop		ix
		rst		8
		db		F_READ
		pop		ix
		jr c,	esxdos_error
		;
		push	bc
		ld		d,ixh
		ld		e,zxmon.VARS.output_buf
		ld		hl,read_str
		ld		bc,READ_STR_LEN
		ldir
		pop		hl
		push	de
		call	zxmon.string.hl_to_decstr
		pop		de
		ld		b,0
		ld		c,a
		ldir
		ld		hl,bytes_str
		ld		c,BYTES_STR_LEN
		ldir
		;
		ld		h,d
		ld		l,VARS.output_buf
		call	zxmon.input_and_screen.print_at_bottom
		call	zxmon.input_and_screen.scroll_up_whole_screen
		jr		esxdos_close_and_exit


;-----------------------------------------------------------------------------
;
; Generic error exit from ESXDOS with er
;
; The calling command dispatcher checks the callee error on return:
;  A = 0 no error
;  A > 0 Error code
;
esxdos_error_no_close:
		; There was an error during F_OPENDIR. No file/dir was opene
		; thus there is no file handle either.
		ld		(ix+VARS.file_errno),a
		jr		esxdos_skip_close_and_exit
esxdos_error:
		; Generic error case. There is an open file handle.
		; A contains ESXDOS error code.
		ld		(ix+VARS.file_errno),a
esxdos_close_and_exit:
		; There was no error or a generic error. Close the open file/dir.
		; Do not change the stored ESXDOS errno.
        ld      a,(ix+VARS.file_handle)
        push    ix
        rst     8
        db      F_CLOSE
        pop     ix
		ld		a,(ix+VARS.file_errno)
esxdos_skip_close_and_exit:
		; Check if there was an error..
		cp		EOK
		jr nz,	.error_found		
		xor		a			; == CMD_EOK
		ret
.error_found:
		; A = ESXDOS error
		ld		a,CMD_EESXDOS
		ret

;-----------------------------------------------------------------------------
;
; Input:
;  HL = ptr to directory entry (within 256 bytes aligned VARS structre)
;
; ESXDOS dir entry looks like below:
;   <byte>   attributes (like MSDOS)
;   <asciiz> file/dirname
;   <word>  date
;   <word>  time
;   <dword>  filesize
;
; 0         1         2 2       3  3    3 444
; 0         0         0 2       0  3    8 012
; ---- filename1234.txt 01.01.1980 0123456789
;                                       <dir>
; up to 16 chars filename
; up to 10 chars file length (left justified) / <dir>
; 10 chars date
;

	DISPLAY	"prep_dir_entry(): ",/H,prep_dir_entry
	DISPLAY	"file_size: ",/H,file_size

prep_dir_entry:
		ld		d,ixh
		ld		e,VARS.output_buf
		push	de

		;
		; Check and prepare file attributes
		ld		a,(hl)
		inc		hl

		; is it A_DIR ?
		bit		4,a
		push	af
		ex		de,hl

		ld		b,'-'
		ld		(hl),b
		jr z,	.not_A_DIR
		ld		(hl),'d'
.not_A_DIR:
		inc		l
		ld		(hl),b
		add		a,a
		jr nc,	.not_A_READ
		ld		(hl),'r'
.not_A_READ:
		inc		l
		ld		(hl),b
		bit		1,a
		jr z,	.not_A_WRITE
		ld		(hl),'w'
.not_A_WRITE:
		inc		l
		ld		(hl),b
		add		a,a
		jr nc,	.not_A_EXEC
		ld		(hl),'x'
.not_A_EXEC:
		inc		l
		ld		b,MAXX-4
		push	hl
.init_loop:
		ld		(hl),' '
		inc		l
		djnz	.init_loop
		ld		(hl),b		; NIL
		ex		de,hl
		pop		de

		; copy filename up to 16 characters
		ld		b,16
.name_loop:
		ld		a,(hl)
		inc		hl
		and		a
		jr z, 	.name_loop_exit
		inc		e
		ld		(de),a
		djnz	.name_loop
.name_loop_exit:
		; File date
		ld		e,VARS.output_buf+22
		; Skip file time
		inc		hl
		inc		hl
		; Date.. bits 0..4 are day
		ld		a,(hl)
		and		00011111b
		ld		c,a
		call	zxmon.math.div_C_by_10
		add		a,'0'
		push	af
		ld		a,c
		add		a,'0'
		ld		(de),a
		inc		e
		pop		af
		ld		(de),a
		inc		e
		;
		ld		a,'.'
		ld		(de),a
		inc		e
		;
		; Date.. bits 8..5 are month
		ld		c,(hl)
		ld		a,00000001b
		inc		hl
		and		(hl)
		sla		c
		adc		a,a
		sla		c
		adc		a,a
		sla		c
		adc		a,a
		ld		c,a
		call	zxmon.math.div_C_by_10	; returns B=0
		add		a,'0'
		push	af
		ld		a,c
		add		a,'0'
		ld		(de),a
		inc		e
		pop		af
		ld		(de),a
		inc		e
		ld		a,'.'
		ld		(de),a
		inc		e
		;
		; Date.. bits 15..9 are year
		ld		c,(hl)
		inc		hl
		push	hl
		push	de
		ld		hl,1980
		srl		c
		add		hl,bc
		call	zxmon.string.hl_to_decstr
		; B = 0
		ld		c,4			; 4 chars
		pop		de
		ldir

		ld		e,VARS.output_buf+33
		pop		hl
		pop		af
		jr z,	.normal_file
		ld		hl,dir_str
		ld		c,5
		jr		prep_dir_done
.normal_file:
		;
file_size:
		; file size
		push	de
		call	get_dword_to_dehl
		call	zxmon.string.dehl_to_decstr
		pop		de
		; HL = ptr to converted string
		;  A = string length
		ld		c,a
prep_dir_done:
		ldir
		pop		hl
		ret

;-----------------------------------------------------------------------------
;
; Get 32 bit DWORD into DE:HL
;
; Input:
;  HL = ptr to <dword> in little endian.
;
; Return:
;  DEHL = 32 bit <dword>
;
; Trashes:
;  A
;
get_dword_to_dehl:
		ld		e,(hl)
		inc		hl
		ld		d,(hl)
		inc		hl
		ld		a,(hl)
		inc		hl
		ld		h,(hl)
		ld		l,a
		ex		de,hl
		ret

current_dir_path:   db      ".",0
dir_str:		db	"<DIR>"
read_str:		db	"Read #"
bytes_str:		db	" bytes",0
READ_STR_LEN	equ	6
BYTES_STR_LEN	equ	7

        ENDMODULE