		DEVICE	ZXSPECTRUM128
		SLDOPT	COMMENT WPMEM, LOGPOINT, ASSERTION

        MODULE  math
;-----------------------------------------------------------------------------
; Multiple a number by 10
;
; Input:
;  HL = number
;
; Returns:
;  HL = number
;
; Trashes:
;  None

mul_HLx10:
		push	de
		add		hl,hl
		push	hl
		add		hl,hl
		add		hl,hl
		pop		de
		add		hl,de
		pop		de
		ret

;-----------------------------------------------------------------------------
; Multiple a number by 10
;
; Input:
;  DEHL = number
;
; Returns:
;  DEHL = number
;
; Trashes:
;  None
mul_DEHLx10:
		push	bc
		add		hl,hl
		rl		e
		rl		d
		push	de
		push	hl
		add		hl,hl
		rl		e
		rl		d
		add		hl,hl
		rl		e
		rl		d
		pop		bc
		add		hl,bc
		pop		bc
		ex		de,hl
		adc		hl,bc
		ex		de,hl
		pop		bc
		ret



;-----------------------------------------------------------------------------
;
; Inputs:
;     DEHL = value to divide
;
; Return:
;     DEHL is the quotient
;     A is the remainder
;     BC is 10
;
; Trashes:
;   BC
;
; Note:
;  Shamelesly taken from https://learn.cemetech.net/index.php/Z80:Math_Routines
;
div_HL_by_10:
		ld		de,0
div_DEHL_by_10:
		ld		bc,$0D0A
		xor		a
		ex		de,hl
		add		hl,hl
		rla
		add		hl,hl
		rla
		add		hl,hl
		rla
		;
.loop1:
		add		hl,hl
		rla
		cp		c
		jr c,	.skip1
		sub		c
		inc		l
.skip1:
		djnz	.loop1		; $-7
   
		ex		de,hl
		ld		b,16
		;
.loop2:   
		add		hl,hl
		rla
		cp		c
		jr c,	.skip2
		sub		c
		inc		l
.skip2:
		djnz	.loop2		; $-7
		ret

;-----------------------------------------------------------------------------
;
; Inputs:
;  C = divident
;
; Returns:
;  A = reminder
;  B = 0
;  C = result
; Trashes:
;  B
;
div_C_by_10:
		ld		b,8
		xor		a
.div_loop:
		sla		c
		rla
		cp		10
		jr c,	.smaller
		inc		c
		sub		10
.smaller:
		djnz	.div_loop
		ret


		ENDMODULE

