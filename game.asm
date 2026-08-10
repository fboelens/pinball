game:
	ld hl,topTable
	ld (bounceTablePointer),hl
	ld hl,isr
	call setInterrupt

	ld a,false
	ld (flipLeftOn),a
	ld (flipRightOn),a

	ld a,ball_start
	ld (ballMove),a

	ld a,4
	ld (ballDY),a
	ld a,1
	ld (ballDX),a

	ld a,down
	ld (ballY),a
	ld a,right
	ld (ballX),a

	ld b,50
	ld (ballKinY),a


	call enableScreen
	call enableSprites
	call updateSpriteData

main:
	halt
	jp main

isr:
	call updateSpritesPositions

	; handle input
	call checkJoyStick

    call checkTrigger
    call z,tilt

	ld a,(joyStickValueX)
	cp left
	call z,flipLeft

	ld a,(joyStickValueX)
	cp right
	call z,flipRight

	ld a,(flipLeftOn)
	cp false
	call nz,doFlipLeft

	ld a,(flipRightOn)
	cp false
	call nz,doFlipRight

	ld a,(isrCounter)
	inc a
	ld (isrCounter),a

	ld a,(ballMove)
	cp ball_stop
	ret z
    cp ball_start
    ret z
	cp ball_toFall
	call z,doBallTopMax

	; handle ball movement
	ld a,(ballMove)
	cp ball_roll
	jp z,doBallRoll
	call nz,doBall

	ret

;----------------------------------------------
tilt:
    ld a,(ballMove)
    cp ball_start
    jp z,doBallStart
    cp ball_stop
    ret nz
    
    ld a,40
    ld (ballKinY),a
    ld a,1
    ld (ballDX),a
	ld a,2
	ld (ballDY),a
	ld a,up
	ld (ballY),a

    ld a,ball_normal
    ld (ballMove),a

    ld a,r
    bit 0,a
    jp z,tilt2

    ld a,left
    ld (ballX),a

tilt2:
    ld a,right
    ld (ballX),a
    ret



flipLeft:
	ld a,(flipLeftOn)
	cp false
	ret nz
	ld a,4
	ld (flipLeftOn),a

	ld a,4
	ld (ballDY),a
	ld a,up
	ld (ballY),a
	ld a,ball_normal
	ld (ballMove),a
	ld a,255
	ld (ballKinY),a

	ret

doFlipLeft:
	ld a,(isrCounter)
	and %00000011
	cp 0
	ret nz

	ld hl,flData

	ld a,(flipLeftOn)
	cp 4
	jp z,doFlipLeft1
	cp 3
	jp z,doFlipLeft2
	cp 2
	jp z,doFlipLeft1
	cp 1
	jp z,doFlipLeft3
	ret

doFlipLeftB:
	ld a,(flipLeftOn)
	dec a
	ld (flipLeftOn),a
	ret

doFlipLeft1:
	ld a,32
	ld (flsx),a
	call DoCopy
	jp doFlipLeftB

doFlipLeft2:
	ld a,64
	ld (flsx),a
	call DoCopy

	ld a,(joyStickValueX)
	cp left
	ret z
	jp doFlipLeftB

doFlipLeft3:
	ld a,0
	ld (flsx),a
	call DoCopy
	jp doFlipLeftB

flipRight:
	ld a,(flipRightOn)
	cp false
	ret nz

	ld a,4
	ld (flipRightOn),a
	ret

doFlipRight:
	ld a,(isrCounter)
	and %00000011
	cp 0
	ret nz

	ld hl,frData
	ld a,(flipRightOn)
	cp 4
	jp z,doFlipRight1
	cp 3
	jp z,doFlipRight2
	cp 2
	jp z,doFlipRight1
	cp 1
	jp z,doFlipRight3
	ret

doFlipRightB:
	ld a,(flipRightOn)
	dec a
	ld (flipRightOn),a
	ret

doFlipRight1:
	ld a,128
	ld (frsx),a
	call DoCopy
	jp doFlipRightB

doFlipRight2:
	ld a,160
	ld (frsx),a
	call DoCopy

	ld a,(joyStickValueX)
	cp right
	ret z

	jp doFlipRightB

doFlipRight3:
	ld a,96
	ld (frsx),a
	call DoCopy
	jp doFlipRightB

updateSpritesPositions:
    ld a,3
    ld  hl,$7600
    call SetVramWrite
    ld hl,spritePositions
    ld b,4*(4)
    ld c,$98
    otir
    ret


updateSpriteData:
	di
	ld	hl,spriteBallData
	ld	de,$7800
	ld	bc,64*2
	ld	a,3
    call	CopyRamVram

	ld	hl,spriteBallColors
	ld	de,$7400
	ld	bc,32*2
	ld	a,3
    call	CopyRamVram

	ld	hl,spriteBallData
	ld	de,$7600
	ld	bc,16
	ld	a,3
    call	CopyRamVram
	ei

    ret

