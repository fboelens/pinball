setInterrupt:
    push hl
	; new hook
	ld hl,$fd9f		; oude hook opslaan
	ld de,isrCurrent
	ld bc,5
	ldir
	ld a,$c9		; zet een ret (c9) neer op hook
	ld ($fd9f),a
	pop hl
	ld ($fd9f+1),hl
	ld a,$c3		; zet een jp op fd9f
	ld ($fd9f),a    
	ret

resetInterrupt:
    ld b,3
    call wait
resetInterrupt2:
	ld a,$c9		; hook terug zetten
	ld ($fd9f),a	; een ret (c9) op fd9f

	ld hl,isrCurrent+4
	ld de,$fd9f+4
	ld bc,5
	lddr
	ret

;
; Set the palette to the one HL points to...
; Modifies: AF, BC, HL (=updated)
; Enables the interrupts.
;
SetPalette:
    xor a           ; set p#pointer to zero.
    di
    out (#99),a
    ld a,16+128
    ei
    out (#99),a
    ld bc,#209A     ; out 32x to port #9A
    otir
    ret

; reg a is color number
; hl points to colordata
SetColor:
    ;xor a           ; set p#pointer to zero.
    di
    out (#99),a
    ld a,16+128
    ei
    out (#99),a
    ld bc,#029A     ; out 32x to port #9A ; color 0 only
    otir
    ret


;
; Fast DoCopy, by Grauw
; In:  HL = pointer to 15-byte VDP command data
; Out: HL = updated
;
DoCopy:
    ld a,32
    di
    out (#99),a
    ld a,17 + 128
    out (#99),a
    ld c,#9B
VDPready:
    ld a,2
    di
    out (#99),a     ; select s#2
    ld a,15 + 128
    out (#99),a
    in a,(#99)
    rra
    ld a,0          ; back to s#0, enable ints
    out (#99),a
    ld a,15 + 128
    ei
    out (#99),a     ; loop if vdp not ready (CE)
    jp c,VDPready
    outi            ; 15x OUTI
    outi            ; (faster than OTIR)
    outi
    outi
    outi
    outi
    outi
    outi
    outi
    outi
    outi
    outi
    outi
    outi
    outi
    ret


VRAM_Peek:
	push hl
	xor a ; always page 0
    rlc h
    rla
    rlc h
    rla
    srl h
    srl h
    
	di
	out	(0x99),a
	ld	a,14+128
	out	(0x99),a
	ld	a,l
	nop
	out	(0x99),a
	ld	a,h
	out	(0x99),a
    nop
	ei
    in	a,(0x98)
	pop hl
	ret

CopyRamVram:
	push	af

	ld	a,c
	ld	(CRVLastOut),a

	pop	af
	push	hl

	ex	de,hl
	call	SetVramWrite
	pop	hl
	ld	a,b
	or	a
	jp	z,CRVLoop1Done
	ld	d,b
	ld	c,$98

CpRamVramLp1:
	ld	b,$00
	otir

	dec	d
	jr	nz,CpRamVramLp1

CRVLoop1Done:
	ld	a,(CRVLastOut)
	or	a
	ret	z

	ld	b,a

	ld	c,$98
	otir

	ret
;--------------------------------------------------------------------------
SetVramWrite:
; routine : Set Vram Pointer in write mode.
; in      : A - page, HL - offset
; out     : none.
; cmnt    : none.

	di

	out	($99),a	 	; out page to 			register #14 of the VDP
	ld	a,14+128	;
	out	($99),a	;

	ld	a,l	; Get LSB of offset
	out	($99),a	; out to VDP

	ld	a,h	; Get MSB of offset

	and	$3f	; clear last two bits
	or	$40	; set bit 6 (write)

	out	($99),a	; iut to VDP

	ei

	ret

colorFader:
; routine : Colorfader
; in      : DE - Palette to fade from, HL - Palette to fade to.
; out     : none.
; cmnt    : none.

	push hl

	ex de,hl

	ld de,dataPalette
	ld bc,32
	ldir

	pop hl

	ld b,8
colorFader.2:
	push bc
	push hl

	ld de,dataPalette

	ld b,16
colorFader.1:
	push bc

	ld a,(de)					; $00
	srl a	
	srl a
	srl a
	srl a
	ld b,a					; $00

	ld a,(hl)					; $77
	srl a
	srl a
	srl a
	srl a						; $07

	cp b						; nc
	jp z,colorFader.NoChange1

	jp c,colorFader.Decrease1

	inc b
	inc b
colorFader.Decrease1:
	dec b
	
colorFader.NoChange1:
	ld a,(de)
	and $0f

	ld c,a

	ld a,(hl)
	and $0f

	cp c
	jp z,colorFader.NoChange2

	jp c,colorFader.Decrease2

	inc c
	inc c
colorFader.Decrease2:
	dec c
colorFader.NoChange2:
	ld a,b
	sla a
	sla a
	sla a
	sla a
	or c

	ld (de),a

	inc de
	inc hl

	ld a,(de)
	ld b,a
	ld a,(hl)
	cp b
	jp z,colorFader.NoChange3

	jp c,colorFader.Decrease3

	inc b
	inc b
colorFader.Decrease3:
	dec b

colorFader.NoChange3:
	ld a,b
	ld (de),a

	inc de
	inc hl

	pop bc

	djnz colorFader.1

    ld hl,dataPalette
    call SetPalette

	ei
	halt
	halt

	pop hl
	pop bc

	djnz colorFader.2

	ret

blackPalette:
	dw $0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	dw $0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000

; reg.: keyrow
readKey:
    di
    in a,(#AA)
    and #F0         ; only change bits 0-3
    or b            ; row xxx
    out (#AA),a
    in a,(#A9)      ; read row into A
    ei
	ret

readStick:
	; nothing happened? check joystick 0
	ld	a, 15	; Lee el puerto de joystick y almacena
	out	($A0), a	; los estados en las variables.
	in	a, ($A2)
	and	10101111b
	out	($A1), a
	ld	a, 14
	out	($A0), a
	in	a, ($A2) ;read left right up down and button 1 and 2
	ret



checkTrigger:
	ld b,8
	call readKey
	bit 0,a
	ret z

	call readStick
	bit 5,a
	ret 

checkTriggerB:
	; graph 
	ld b,6
	call readKey
	bit 2,a
	ret z

	call readStick
	bit 4,a


	ret 

checkJoyStickWait:
	call checkJoyStick
	cp 0
	jp nz,checkJoyStickWait
	ret



checkJoyStick:
	ld ix,joyStickValueY
	ld (ix),0
	ld (ix+1),0

	; check keyboard
	ld b,8
	call readKey
	or %00000001
	cp 255
	jp nz,checkJoyStick2
	

	call readStick
	cp 15
	ret z
	jp checkJoyStick3
	

; keyboard
checkJoyStick2:
    ; a = 1 - 8 -> u,ru,r,rd,d,ld,l,lu
	cp 223
	jp z,checkJoyStick_up
	cp 95
	call z,checkJoyStick_up
	jp z,checkJoyStick_right
	cp 127
	jp z,checkJoyStick_right
	cp 63
	call z,checkJoyStick_right
	jp z,checkJoyStick_down
	cp 191
	jp z,checkJoyStick_down
	cp 175
	call z,checkJoyStick_down
	jp z,checkJoyStick_left
	cp 239
	jp z,checkJoyStick_left
	cp 207
	call z,checkJoyStick_up
	jp z,checkJoyStick_left
	ret

; joystick
checkJoyStick3:
	and %00001111

	cp 14
	jp z,checkJoyStick_up
	cp 6
	call z,checkJoyStick_up
	jp z,checkJoyStick_right
	cp 7
	jp z,checkJoyStick_right
	cp 5
	call z,checkJoyStick_right
	jp z,checkJoyStick_down
	cp 13
	jp z,checkJoyStick_down
	cp 9
	call z,checkJoyStick_down
	jp z,checkJoyStick_left
	cp 11
	jp z,checkJoyStick_left
	cp 10
	call z,checkJoyStick_up
	jp z,checkJoyStick_left
	ret

checkJoyStick_up:
	ld (ix),up
	ret

checkJoyStick_right:
	ld (ix+1),right
	ret

checkJoyStick_down:
	ld (ix),down
	ret

checkJoyStick_left:
	ld (ix+1),left
	ret


; Input: HL = number to convert, DE = location of ASCII string
; Output: ASCII string at (DE)
Num2Dec:
	ld	bc,-10000
	call	Num1
	ld	bc,-1000
	call	Num1
	ld	bc,-100
	call	Num1
	ld	c,-10
	call	Num1
	ld	c,b

Num1:
	ld	a,'0'-1
Num2:
	inc	a
	add	hl,bc
	jr	c,Num2
	sbc	hl,bc

	ld	(de),a
	inc	de
	ret

enableSprites:
	ld a,$28
	out ($99),a
	ld a,8+128
	out ($99),a		; set register 8
	ret

disableSprites:
	ld a,$2a
	out ($99),a
	ld a,8+128
	out ($99),a		; set register 8
	ret

enableScreen:
	ld a,(RG1SAV)
	or %01000000
	ld (RG1SAV),a
	out ($99),a
	ld a,1+128
	out ($99),a		; set register 1
	ret

disableScreen:
	ld a,(RG1SAV)
	and %10111111
	ld (RG1SAV),a
	out ($99),a
	ld a,1+128
	out ($99),a		; set register 1
	ret

fillRam:
    ld (de),a
    inc de
    djnz fillRam
	ret

clearSprites:
	ld hl,spritePositions
    ld b,64
    ld a,218
clearSprites2
    ld (hl),a
    inc hl
    inc hl
    inc hl
    inc hl
    djnz clearSprites2

	ld	hl,spritePositions
	ld	de,$7600
	ld	bc,256 ; 3 player sprites + 3*2 enemie sprites
	ld	a,3
    call	CopyRamVram
    ret

set60hz:    
    // set 60 hz
    ld a,60
    ld (option_freq),a

    di
    ld a,($FFE8)
    res 1,a
    ld ($ffe8),a
	out ($99),a
	ld a,9+128
	out ($99),a		; set register 9
    ei

    ;call replay_equalization_on
    
    ret

wait:
    halt
    djnz wait
    ret

waitTrigger:
    push bc
    halt
    call checkTrigger
    pop bc
    ret z
    djnz waitTrigger
    ret

/*
; a = screen
resetScreen:    
    ld (cldy+1),a

	ld b,0
    ld a,0
resetScreen2:
    push bc
    ld hl,clearLine
    call DoCopy
    ld a,(cldy)
    inc a
    ld (cldy),a
    pop bc
    djnz resetScreen2
    ret
*/
setPage:
	sla a
	sla a
	sla a
	sla a
	sla a
    or %00011111
    out ($99),a
    ld a,2+128
    out ($99),a 
    ld a,0
    out ($99),a
    ld a,23+128
    out ($99),a 
	ret

; ---------------------------------------------------------

; Search RAM on a page
; Input: HL=0000h, 4000h or 8000h
; output: A=slot number and Carry = 0, Carry = 1 if Ram not found 

ram_srch:
	ld	b,4	;Slot primaire
ram_srch_loop:
	ld	a,b
	dec	a
	xor	3
	ld	(RAMSLT),a
	ld	e,a
	
	push	hl
	ld	hl,EXPTBL
	ld	d,0
	add	hl,de
	ld	a,(hl)
	ld	(KBUF),a	; Save secondary slot flag

	pop	hl
	ld	a,h
	exx
	ld	h,a
	ld	l,0		; Restore HL address

	ld	a,(KBUF)	; Restore secondary slot flag
	rlca
	ld	b,1
	ld	a,(RAMSLT)
	jr	nc,PrimSLT

	ld	b,4	;Slot secondaire
ram_srch_loop2:	
	ld	a,b
	dec	a
	xor	3
	rlca
	rlca
	ld	c,a
	ld	a,(RAMSLT)
	or	c
	or	080h	; Set bit 7
PrimSLT:
	ld	(KBUF+1),a
	push	bc
	call	RDSLT
	ld	(KBUF+2),a
	pop	bc
	cp	041h
	jr	nz,no_header	; Jump if first byte = "A" (Rom?)

	inc	hl
	ld	a,(KBUF+1)
	push	bc
	call	RDSLT
	pop	bc
	dec	hl
	cp	042h
	jr	z,no_ram	; Jump if second byte <> "B"
no_header:
	ld	a,(KBUF+1)
	push	bc
	call	RDSLT		; Read first byte
	pop	bc
	ld	e,041h
	ld	a,(KBUF+1)
	push	bc
	call	WRSLT		; Write "A" at first byte
	pop	bc
	ld	a,(KBUF+1)
	push	bc
	call	RDSLT		; Read first byte
	pop	bc
	cp	041h
	jr	z,ram_found	; Jump if first byte = "A"
	
no_ram:	
	djnz	ram_srch_loop2	; Go to next Slot if No RAM 
	exx
	djnz	ram_srch_loop	; Go to next Slot if No RAM 
	scf			; Set Carry
	ret

ram_found:
	ld	a,(KBUF+2)
	ld	e,a
	ld	a,(KBUF+1)
	push	af
	or	080h
	call	WRSLT		; Restore first byte value of RAM
	pop	af		; A=Slot of Ram found (without Bit7)
	or	a		; Reset Carry
	ret

setslotpage0:
	di
	ld		b,a					; B = Slot param in FxxxSSPP format
	in		a,(0A8h)
	and		0xFC
	ld		d,a					; D = Primary slot value
	ld		a,b
	and		3
	or		d
	ld		d,a		; D = Final Value for primary slot
	ld		a,b		; Check if expanded
	bit		7,a
	jr		z,1f	; Not Expanded
	mainslot_setup	0
1:	ld		a,d				; A = Final value
	out		(0A8h),a		; Slot Final. Ram, rom c, rom c, Main
	ret


LMCM:   
	DI                              ;disable interrupt
	LD      B,A                     ;B := LOGICAL OPERATION
	CALL    WAIT.VDP                ;wait end of command

	LD      A,(WRVDP)
	LD      C,A
	INC     C                       ;C := PORT#1's address
	LD      A,32
	OUT     (C),A
	LD      A,80H+17
	OUT     (C),A                   ;R#17 := 32
	INC     C
	INC     C                       ;C := PORT#3's address
	XOR     A
	OUT     (C),H                   ;SX
	OUT     (C),A
	OUT     (C),L                   ;SY
	OUT     (C),A
	OUT     (C),A                   ;dummy
	OUT     (C),A                   ;dummy
	OUT     (C),A                   ;dummy
	OUT     (C),A                   ;dummy

	ld h,12
	OUT     (C),H                   ;NX
	OUT     (C),A
	OUT     (C),H                   ;NY
	OUT     (C),A
	OUT     (C),A                   ;dummy


	OUT     (C),A                   ;DIX and DIY
	LD      A,7
	CALL    GET.STATUS
	ld a,%10100000               ;LMCM command
	OUT     (C),A
	LD      A,(RDVDP)
	LD      C,A                     ;C := PORT#1's address
LOOP:
	LD      A,2
	CALL    GET.STATUS
	BIT     0,A                     ;check CE bit
	JP      Z,EXIT
	BIT     7,A                     ;check TR bit
	JP      Z,LOOP
	LD      A,7
	CALL    GET.STATUS
	LD      (IX+0),A
	INC     IX
	JR      LOOP

EXIT:
	LD      A,0
	CALL    GET.STATUS
	EI
	RET

GET.STATUS:
	PUSH    BC
	LD      BC,(WRVDP)
	INC     C
	OUT     (C),A
	LD      A,8FH
	OUT     (C),A
	LD      BC,(RDVDP)
	INC     C
	IN      A,(C)
	POP     BC
	RET

WAIT.VDP:
	LD      A,2
	CALL    GET.STATUS
	AND     1
	JR      NZ,WAIT.VDP
	XOR     A
	CALL    GET.STATUS
	RET

        