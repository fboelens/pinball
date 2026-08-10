;------------------------------------------------------------------------------------
; ball movements
;------------------------------------------------------------------------------------
doBall:
	ld a,(ballDX)
	cp 0
	jp z,doBall2b
	ld b,a
doBall2:	
	push bc
	call moveBallX
	call doCheckX
	pop bc
	djnz doBall2
doBall2b:
	ld a,(ballDY)
	cp 0
	ret z
	ld b,a
doBall3:	
	push bc
	call moveBallY
	call doCheckY	
	pop bc
	djnz doBall3
	ret

doBallStart:
    call $c0
    ld a,ball_normal
    ld (ballMove),a
    ld a,255
    ld (ballKinY),a
    ld a,up
    ld (ballY),a
    ld a,4
    ld (ballDY),a
    ld a,0
    ld (ballDX),a
    ret

doBallTopMax:
	ld hl,(bounceTablePointer)
	ld a,(hl)
	cp 128
	jp z,setBallNormal
	cp 127
	call z,setBallFall
	cp 126
	call z,checkBallRoll
	inc hl
	ld (bounceTablePointer),hl

	ld (ballDY),a
	ret

setBallNormal:
	ld a,ball_normal
	ld (ballMove),a
	ld a,4
	ld (ballDY),a
	ret

setBallFall:
	ld a,down
	ld (ballY),a
	inc hl
	ld a,(hl)
	ret

setBallFallAgain:
    ld hl,downTable2
    ld (bounceTablePointer),hl
    ld a,ball_normal
    ld (ballMove),a
    ret

setBallStop:
	ld a,ball_stop
	ld (ballMove),a
	ld a,0
	ld (ballDY),a
    ld (ballDX),a
    ret

;------------------------------------------------------------------------------------
; ball left/right movement
;------------------------------------------------------------------------------------
moveBallX:
	; X
	ld a,(ballX)
	cp left
	jp z,moveBallLeft

moveBallRight:
	ld a,(spritePositions+1)
	inc	a
	ld (spritePositions+1),a
	ld (spritePositions+5),a
	ld (spritePositions+9),a
	ld (spritePositions+13),a
	ret

moveBallLeft:
	ld a,(spritePositions+1)
	dec	a
	ld (spritePositions+1),a
	ld (spritePositions+5),a
	ld (spritePositions+9),a
	ld (spritePositions+13),a
	ret

;------------------------------------------------------------------------------------
; ball up/down movement
;------------------------------------------------------------------------------------

moveBallY:
	; Y
	ld a,(ballY)
	cp up
	jp z,moveBallUp

moveBallDown:
	ld a,(spritePositions)
	inc a
	ld (spritePositions),a
	ld (spritePositions+4),a
	ld (spritePositions+8),a
	ld (spritePositions+12),a

	ld a,(ballKinY)
	cp 255
	ret z
	inc a
	ld (ballKinY),a
	ret

moveBallUp:
	ld a,(spritePositions)
	dec a
	ld (spritePositions),a
	ld (spritePositions+4),a
	ld (spritePositions+8),a
	ld (spritePositions+12),a

	ld a,(ballMove)
	cp ball_toFall
	ret z

	ld a,(ballKinY)
	cp 0
	jp z,moveBallUpTop
	dec a
	ld (ballKinY),a

	ret

moveBallUpTop:
	ld a,ball_toFall
	ld (ballMove),a

	ld a,(ballDY)
	cp 4
	jp z,moveBallUpTop1
	cp 3
	jp z,moveBallUpTop2
	cp 2
	jp z,moveBallUpTop3

	ld hl,topTable4
	ld (bounceTablePointer),hl
	ret


	ret

moveBallUpTop1:
	ld hl,topTable
	ld (bounceTablePointer),hl
	ret

moveBallUpTop2:
	ld hl,topTable2
	ld (bounceTablePointer),hl
	ret

moveBallUpTop3:
	ld hl,topTable3
	ld (bounceTablePointer),hl
	ret

;------------------------------------------------------------------------------------
; ball rolling
;------------------------------------------------------------------------------------

checkBallRoll:
    call checkBallBottom
    
    ld a,(ballTotal)    
    cp %00000000
    jp z,noRoll

    ld a,(ballTotal)
    cp %00001111
    jp z,setBallStop

    ld a,1
    ld (ballDX),a
    ld (ballDY),a

    ld a,ball_roll
    ld (ballMove),a
    ret z

noRoll:
	inc hl
	ld a,(hl)

	ret


checkBallBottom:
    ld a,0
    ld (ballTotal),a
    ld c,1

    ld a,(ballCheckBottomR)
    cp 0
    call nz,checkBallRollAdd
	ld a,(ballCheckBottomRM)
    cp 0    
    call nz,checkBallRollAdd
	ld a,(ballCheckBottomLM)
	cp 0
    call nz,checkBallRollAdd
	ld a,(ballCheckBottomL)
	cp 0
    call nz,checkBallRollAdd
    ret

checkBallRollAdd:
    ld a,(ballTotal)
    add a,c
    ld (ballTotal),a
    sla c
    ret


doBallRoll:
   	call checkBall	
    ld ix,ballChecks

	ld de,1281
	add hl,de 
	call VRAM_Peek	
	ld (ix+12),a ; dot 13 (bottom left)
	inc hl
	call VRAM_Peek	
	ld (ix+13),a ; dot 14 (bottom left middle)
	inc hl
	call VRAM_Peek	
	ld (ix+14),a ; dot 15 (bottom right middle)
	inc hl
	call VRAM_Peek	
	ld (ix+15),a ; dot 16 (bottom right)

    call checkBallBottom

    ld a,(ballTotal)
    cp %00000000
    jp z,setBallFallAgain

    call moveBallDown
    
    ld a,(ballTotal)
    cp %00001000
    call z,moveBallRight

    ld a,(ballTotal)
    cp %00001100
    call z,moveBallRight

    ld a,(ballTotal)
    cp %00001110
    call z,moveBallRight

    ld a,(ballTotal)    
    cp %00000001
    call z,moveBallLeft

    ld a,(ballTotal)
    cp %00000011
    call z,moveBallLeft
    
    ld a,(ballTotal)
    cp %00000111
    call z,moveBallLeft


	ret

;------------------------------------------------------------------------------------
; ball checks left/right
;------------------------------------------------------------------------------------
doCheckX:
	ld a,(ballX)
	cp left
	jp z,doCheckLeft

doCheckRight:
	call checkBall	
    ld ix,ballChecks
	ld de,261
	add hl,de
	call VRAM_Peek	
	ld (ix+5),a ; dot 6 (right  1)
	ld de,256
	add hl,de
	call VRAM_Peek	
	ld (ix+7),a ; dot 8 (right  2)
	ld de,256
	add hl,de
	call VRAM_Peek	
	ld (ix+9),a ; dot 10 (right  3)
	ld de,256
	add hl,de
	call VRAM_Peek	
	ld (ix+11),a ; dot 12 (right  4)

	; check right side	
	ld a,(ballCheckRight1)
	cp 0
	jp nz,doCheckRight2
	ld a,(ballCheckRight2)
	cp 0
	jp nz,doCheckRight2
	ld a,(ballCheckRight3)
	cp 0
	jp nz,doCheckRight2
	ld a,(ballCheckRight4)
	cp 0
	jp nz,doCheckRight2
	ret

doCheckRight2
	ld a,left
	ld (ballX),a
	ret


doCheckLeft:
	call checkBall	
    ld ix,ballChecks

	ld de,256
	add hl,de 
	call VRAM_Peek	
	ld (ix+4),a ; dot 5 (left  1)
	ld de,256
	add hl,de
	call VRAM_Peek	
	ld (ix+6),a ; dot 7 (left 2)
	ld de,256
	add hl,de
	call VRAM_Peek	
	ld (ix+8),a ; dot 9 (left 3)
	ld de,256
	add hl,de
	call VRAM_Peek	
	ld (ix+10),a ; dot 11 (left 4)


	; check lift side	
	ld a,(ballCheckLeft1)
	cp 0
	jp nz,doCheckLeft2
	ld a,(ballCheckLeft2)
	cp 0
	jp nz,doCheckLeft2
	ld a,(ballCheckLeft3)
	cp 0
	jp nz,doCheckLeft2
	ld a,(ballCheckLeft4)
	cp 0
	jp nz,doCheckLeft2
	ret

doCheckLeft2:
	ld a,right
	ld (ballX),a

	ret


;------------------------------------------------------------------------------------
; ball checks up/down
;------------------------------------------------------------------------------------
doCheckY:
	ld a,(ballY)
	cp up
	jp z,doCheckUp

doCheckDown:
	call checkBall	
    ld ix,ballChecks

	ld de,1281
	add hl,de 
	call VRAM_Peek	
	ld (ix+12),a ; dot 13 (bottom left)
	inc hl
	call VRAM_Peek	
	ld (ix+13),a ; dot 14 (bottom left middle)
	inc hl
	call VRAM_Peek	
	ld (ix+14),a ; dot 15 (bottom right middle)
	inc hl
	call VRAM_Peek	
	ld (ix+15),a ; dot 16 (bottom right)

	; check down
	ld a,(ballCheckBottomL)
	cp 0
	jp nz,doCheckDown2
	ld a,(ballCheckBottomLM)
	cp 0
	jp nz,doCheckDown2
	ld a,(ballCheckBottomRM)
	cp 0
	jp nz,doCheckDown2
	ld a,(ballCheckBottomR)
	cp 0
	jp nz,doCheckDown2
	ret
doCheckDown2:
	ld a,(ballKinY)
	srl a
	srl a
	srl a
	srl a
	ld (ballKinY),a

	ld a,up
	ld (ballY),a
	ld a,ball_normal
	ld (ballMove),a

	ret

doCheckUp:
	call checkBall	
    ld ix,ballChecks
	
	inc hl
    inc hl
	call VRAM_Peek	
	ld (ix),a ; dot 1 (top left)
	inc hl
	call VRAM_Peek	
	ld (ix+1),a ; dot 2 (top middle left)
	inc hl
	call VRAM_Peek	
	ld (ix+2),a ; dot 3 (top middle right)
	inc hl
	call VRAM_Peek	
	ld (ix+3),a ; dot 4 (top right)

	; check top
	ld a,(ballCheckTopL)
	cp 0
	jp nz,doCheckUp2
	ld a,(ballCheckTopRM)
	cp 0
	jp nz,doCheckUp2
	ld a,(ballCheckTopLM)
	cp 0
	jp nz,doCheckUp2
	ld a,(ballCheckTopR)
	cp 0
	jp nz,doCheckUp2
	ret

doCheckUp2:	
    ld a,(spritePositions+1)
    sub 200
    jp nc,doCheckUp2b

	ld a,down
	ld (ballY),a

	ld a,(ballMove)
	cp ball_toFall
	jp z,doCheckUp3

	ld a,ball_normal
	ld (ballMove),a
	ret

doCheckUp2b:
    ld a,up
    ld (ballY),a
    ld a,left
    ld (ballX),a
    ld a,4
    ld (ballDX),a
    ld a,0
    ld (ballDY),a
    ret

doCheckUp3:
	ld a,(ballDY)
	cp 1
	jp z,doCheckUp3a
	cp 2
	jp z,doCheckUp3b
	cp 3
	jp z,doCheckUp3c

	ld hl,downTable4
	ld (bounceTablePointer),hl
	ret

doCheckUp3a:
	ld hl,downTable1
	ld (bounceTablePointer),hl
	ret

doCheckUp3b:
	ld hl,downTable2
	ld (bounceTablePointer),hl
	ret

doCheckUp3c:
	ld hl,downTable3
	ld (bounceTablePointer),hl
	ret

;---------------------------------------------------
; ix = table
; hl = Y and X position of ball
checkBall:
    xor l
	ld a,(spritePositions)
	ld h,a
	srl h
	rr l ; *128
	ld a,(spritePositions+1)
	srl a
	ld l,a ; top left
	ret
