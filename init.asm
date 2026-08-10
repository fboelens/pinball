init:
	call	RSLREG	; Read the primary slots register
	rrca
	rrca
	and	3
	ld	c,a
	ld	b,0
	ld	hl,EXPTBL	; HL = Address of the secondary slot flags table
	add	hl,bc
	ld	a,(hl)
	and	80h	; Keep the bit 7 (secondary slot flag)
	or	c
	ld	c,a
	inc	hl
	inc	hl
	inc	hl
	inc	hl	; HL =  Address of the secondary slot register in the secondary slot register table
	ld	a,(hl)
	and	0Ch
	or	c
	ld	h,080h
	call	ENASLT	; Select the ROM on page 8000h-BFFFh

	ld	hl,00000h
	call	ram_srch
	ld	(RAMAD0),a

init_start:
	ld a,5
	call CHGMOD
	call disableScreen
	call disableSprites

	call memload_pinball
	call memload_pinball2
	call set60hz

	ld b,5
	call wait

    ld a,0
    ld (forclr),a
    ld a,15
    ld (bakclr),a
    ld (bdrclr),a
    call CHGCLR

	ld hl,gamePalette
	call SetPalette

    ld hl,spritePosOrg
    ld de,spritePositions
    ld bc,48
    ldir

	; copies
    ld hl,copysOrg
    ld de,copys
    ld bc,2*15
    ldir

	ld hl,flData
	call DoCopy
	ld hl,frData
	call DoCopy

    ld a,0
	ld (ADDR_CLIKSW), a

	di
	ld a,(RG1SAV)	; set spritemode op 16x16
	or %00000010
	and %11111110
	ld (RG1SAV),a
	out ($99),a
	ld a,1+128
	out ($99),a

    ld a,31		; (*2048) ($7800)
	out ($99),a
	ld a,6+128
	out ($99),a		; set register 6
	
	ld a,%11101111 ; 11101100 *80h = 7600 (2 LSB's are ignored) ($7600)
	out ($99),a
	ld a,5+128
	out ($99),a		; set register 5
	
	ld a,%00000001 ; page?
	out ($99),a
	ld a,11+128
	out ($99),a		; set register 11
	ei

	jp game