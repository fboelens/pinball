; -----------------------------------------------------------------------------
; MSX2 SCREEN 5 pinball movement demo (Z80 / SJASM)
;
; Build from the repository root:
;     .\sjasm.exe -s pinball.asm
;
; Output: pinball.rom (32 KiB)
;
; Controls:
;   cursor/joystick left  - left flipper
;   cursor/joystick right - right flipper
;   space / trigger 1     - both flippers, and launch a waiting ball
;
; The ball uses signed 8.8 fixed-point position and velocity.  The high byte of
; each position is the visible pixel coordinate; the low byte is the fraction.
; Gravity, rebounds and flipper impulses therefore remain smooth on a 3.58 MHz
; Z80 without multiplication or division.
;
; Reading guide
; -------------
; 1. MainLoop synchronises to VBlank, updates graphics/input, then physics.
; 2. StepBall applies gravity and divides movement into four collision steps.
; 3. ResolveTileX/Y handles the static 8x8 collision map.
; 4. CheckMapPolygons/Circles handles objects from Tiled's PinballObjects layer.
; 5. CheckFlippers handles frame-specific polygons from maps/flippers.tmx.
; 6. The Video section uploads generated assets and updates sprites/animations.
;
; Coordinate conventions
; ----------------------
; BALL_X/BALL_Y are the top-left of the 16x16 sprite box. Collision routines
; normally add 8 to obtain the ball centre. Positive X points right; positive Y
; points down. Consequently a negative BALL_VY means that the ball is rising.
;
; 8.8 examples: 0100h=+1.0, 0040h=+0.25, FF00h=-1.0. Stored velocities and
; frame movement use the same full-speed time base, which keeps collision
; thresholds, impulses and visible travel directly comparable.
; -----------------------------------------------------------------------------

        output  pinball.rom

; MSX BIOS entry points and BIOS shadow registers used by this ROM.
CHGMOD: equ     005fh
GTSTCK: equ     00d5h
GTTRIG: equ     00d8h
LDIRVM: equ     005ch
WRTVDP: equ     0047h
RG1SAV: equ     0f3e0h

; VRAM layout used by the two overlapping ball sprites.
SPRITE_COLORS:  equ 7400h
SPRITE_ATTR:    equ 7600h
SPRITE_PATTERNS:equ 7800h

; Safety limits. The authored tilemap is authoritative; these only stop a ball
; escaping if a malformed map contains an unintended opening.
LEFT_WALL:      equ 0               ; emergency bounds outside the tile walls
RIGHT_WALL:     equ 240
TOP_WALL:       equ 0
DRAIN_Y:        equ 204

; Physics tuning. Values are signed 8.8 pixels per simulation frame.
GRAVITY:        equ 0018h           ; +0.09375 velocity per full-speed frame
PHYSICS_GRAVITY:equ GRAVITY         ; full acceleration per display frame
MAX_FALL_SPEED: equ 0500h           ; +5 pixels/frame
LAUNCH_VX:      equ 0fec0h          ; -1.25 pixels/frame, clearly toward left
LAUNCH_VY:      equ 0f900h          ; -7 pixels/frame, reaches the top arc
FLIPPER_BASE_VY:equ 0fd00h          ; -3 pixels/frame near the pivot
FLIPPER_MID_VY: equ 0fc00h          ; -4 pixels/frame halfway out
FLIPPER_TIP_VY: equ 0fb00h          ; -5 pixels/frame at the tip
TUBE_EXIT_VX:   equ 0200h           ; +2 pixels/frame
TUBE_EXIT_VY:   equ 0fe80h          ; -1.5 pixels/frame
; Writable state in RAM. Keeping variables at fixed addresses makes them easy
; to inspect from openMSX's debugger and from the automated Tcl smoke tests.
BALL_X:         equ 0c000h           ; word, 8.8 fixed point
BALL_Y:         equ 0c002h           ; word, 8.8 fixed point
BALL_VX:        equ 0c004h           ; word, signed 8.8
BALL_VY:        equ 0c006h           ; word, signed 8.8
BALL_WAITING:   equ 0c008h           ; 1 while parked in the launch lane
BUMPER_LOCK:    equ 0c009h           ; short global anti-double-trigger timer
LEFT_ACTIVE:    equ 0c00ah           ; current input state, 0 or 1
RIGHT_ACTIVE:   equ 0c00bh
BALL_SIDE:      equ 0c00ch           ; temporary contact id: normal 0..7 or flipper 1..4
BALL_IN_TUBE:   equ 0c00dh           ; covered tube owns movement while nonzero
TUBE_INDEX:     equ 0c00eh           ; byte offset into TubePath
BALL_HIT_X:     equ 0c00fh           ; signed centre-to-object delta
BALL_HIT_Y:     equ 0c010h
LEFT_FRAME:     equ 0c011h           ; 0=rest, 1=middle, 2=raised
RIGHT_FRAME:    equ 0c012h
BALL_FRAME:     equ 0c013h           ; 0=top, clockwise through 7=top-left
BALL_ROLL_ACCUM:equ 0c014h           ; word, accumulated horizontal distance
LEFT_KICK:      equ 0c016h           ; nonzero only while flipper moves upward
RIGHT_KICK:     equ 0c017h
OBJECT_RADIUS:  equ 0c018h           ; expanded object+ball collision radius
OBJECT_RADIUS_SQ:equ 0c019h          ; word
LAST_BUMPER_PTR:equ 0c01bh           ; last actively fired object record
ABS_HIT_X:      equ 0c01dh
ABS_HIT_Y:      equ 0c01eh
LAST_BUMPER_KIND:equ 0c01fh          ; 0=none, 1=circle, 2=polygon field
POLY_LOCAL_X:   equ 0c020h           ; scratch X inside a compiled polygon field
POLY_FIELD_VALUE:equ 0c021h          ; scratch nibble/normal selector
OBJECT_ANIM_TIMER:equ 0c022h         ; bit 7=pending draw, low bits=hold frames
OBJECT_ANIM_SOURCE_X:equ 0c023h       ; XOR-delta frame in hidden VRAM atlas
OBJECT_ANIM_TARGET_X:equ 0c024h
OBJECT_ANIM_TARGET_Y:equ 0c025h
FLIPPER_OLD_VX: equ 0c027h           ; scratch: velocity before passive contact
FLIPPER_OLD_VY: equ 0c029h
FLIPPER_NORMAL: equ 0c02bh           ; approach speed along flipper normal
FLIPPER_DISTANCE:equ 0c02dh          ; absolute ball-centre distance from axle
FLIPPER_PIVOT_Y:equ 0c02eh           ; current map instance pivot
FLIPPER_PIVOT_X:equ 0c02fh           ; current instance pivot for field lookup
OBJECT_ANIM_COMMAND:equ 0c030h        ; 15-byte V9938 LMMM command block
OBJECT_CONTACT: equ 0c03fh            ; polygon owns this physics substep when nonzero

; Page 2 is writable RAM in this cartridge configuration. After the temporary
; playfield decompression buffers have been uploaded to VRAM, this address is
; reused for the expanded variable-size polygon collision records.
PolygonObjects: equ 08000h
SAT_SHADOW:     equ 0c100h           ; 32 bytes

        org     4000h

        ; Standard MSX ROM header. "AB" identifies a cartridge; Start is the
        ; initialisation entry point called by the BIOS.
        db      "AB"
        dw      Start
        dw      0
        dw      0
        dw      0
        ds      6,0

Start:
        ; Use a known stack below the BIOS work area and retain normal IM 1
        ; interrupts so HALT can be used as a VBlank synchronisation point.
        di
        ld      sp,0f380h
        im      1
        ei

        ld      a,5                  ; SCREEN 5, 256x212, 16 colours
        call    CHGMOD
        ld      bc,0107h             ; dark border matching the playfield
        call    WRTVDP
        xor     a
        ld      (OBJECT_ANIM_TIMER),a
        call    ResetBall
        call    InitGraphics
        call    UpdateSprites

MainLoop:
        ; Rendering is performed immediately after VBlank. Input and physics
        ; follow, preparing state that becomes visible on the next iteration.
        halt                         ; BIOS VBlank interrupt
        call    UpdateSprites        ; update both OR planes together in VBlank
        call    UpdateObjectAnimation
        call    ReadControls
        call    UpdateFlipperAnimations
        call    StepBall
        call    UpdateBallAnimation
        jr      MainLoop

; -----------------------------------------------------------------------------
; Input
; -----------------------------------------------------------------------------

ReadControls:
        ; Rebuild the input state every frame instead of toggling it. This also
        ; makes releasing a key immediately start the flipper's return frames.
        xor     a
        ld      (LEFT_ACTIVE),a
        ld      (RIGHT_ACTIVE),a

        ; GTSTCK returns an 8-direction number. Prefer cursor keys (port 0),
        ; then read joystick port 1 when the keyboard direction is idle.
        xor     a
        call    GTSTCK
        or      a
        jr      nz,.directionReady
        ld      a,1
        call    GTSTCK
.directionReady:
        ld      c,a
        cp      7                    ; left
        jr      z,.left
        cp      8                    ; up-left
        jr      z,.left
        cp      6                    ; down-left
        jr      nz,.testRight
.left:
        ld      a,1
        ld      (LEFT_ACTIVE),a

.testRight:
        ld      a,c
        cp      3                    ; right
        jr      z,.right
        cp      2                    ; up-right
        jr      z,.right
        cp      4                    ; down-right
        jr      nz,.triggers
.right:
        ld      a,1
        ld      (RIGHT_ACTIVE),a

.triggers:
        ; Space and joystick trigger A operate both flippers. StepBall also
        ; treats either active flipper as the launch button while waiting.
        xor     a                    ; space bar
        call    GTTRIG
        push    af
        ld      a,1                  ; joystick 1 trigger A
        call    GTTRIG
        pop     bc                   ; B = space-bar result
        or      b
        ret     z
        ld      a,1
        ld      (LEFT_ACTIVE),a
        ld      (RIGHT_ACTIVE),a
        ret

; Advance one pivot-aligned bitmap frame per display frame. Pressing moves
; 0->1->2; releasing plays the same source frames backwards, 2->1->0.
UpdateFlipperAnimations:
        ; LEFT/RIGHT_KICK are one-frame edge signals, not held-button signals.
        ; Physics therefore adds a strong kick only while a frame moves upward;
        ; a ball resting on an already raised flipper merely rolls downhill.
        xor     a
        ld      (LEFT_KICK),a
        ld      (RIGHT_KICK),a
        ld      d,a                  ; nonzero when at least one frame changes

        ld      a,(LEFT_FRAME)
        ld      b,a
        ld      a,(LEFT_ACTIVE)
        or      a
        ld      a,b
        jr      z,.leftRelease
        cp      2
        jr      nc,.leftStore
        inc     a
        ld      d,1
        ld      c,a
        ld      a,1
        ld      (LEFT_KICK),a
        ld      a,c
        jr      .leftStore
.leftRelease:
        or      a
        jr      z,.leftStore
        dec     a
        ld      d,1
.leftStore:
        ld      (LEFT_FRAME),a

        ld      a,(RIGHT_FRAME)
        ld      b,a
        ld      a,(RIGHT_ACTIVE)
        or      a
        ld      a,b
        jr      z,.rightRelease
        cp      2
        jr      nc,.rightStore
        inc     a
        ld      d,1
        ld      c,a
        ld      a,1
        ld      (RIGHT_KICK),a
        ld      a,c
        jr      .rightStore
.rightRelease:
        or      a
        jr      z,.rightStore
        dec     a
        ld      d,1
.rightStore:
        ld      (RIGHT_FRAME),a
        ld      a,d
        or      a
        ret     z                    ; static frames need no repeated VRAM copy
        jp      DrawFlippers

; Rotate once per three horizontal pixels travelled. Positive VX advances
; clockwise (top -> top-right -> right); negative VX plays the frames backward.
; Accumulating 8.8 distance keeps slow rolling smooth without overspinning.
UpdateBallAnimation:
        ; Animation is distance based rather than time based. A stationary ball
        ; keeps its current artwork and a faster ball rotates more quickly.
        ld      a,(BALL_WAITING)
        or      a
        ret     nz
        ld      hl,(BALL_VX)
        ld      a,h
        or      l
        ret     z
        bit     7,h
        jr      z,.magnitudeReady
        xor     a
        sub     l
        ld      l,a
        sbc     a,a
        sub     h
        ld      h,a
.magnitudeReady:
        ; Rolling follows the full horizontal distance travelled this frame.
        ld      de,(BALL_ROLL_ACCUM)
        add     hl,de
        ld      a,h
        cp      3                    ; one eighth-turn per 3 pixels
        jr      c,.storeDistance
        ld      de,0300h
        or      a
        sbc     hl,de
        ld      (BALL_ROLL_ACCUM),hl

        ld      hl,(BALL_VX)
        ld      a,(BALL_FRAME)
        bit     7,h
        jr      nz,.counterClockwise
        inc     a
        and     7
        ld      (BALL_FRAME),a
        ret
.counterClockwise:
        dec     a
        and     7
        ld      (BALL_FRAME),a
        ret
.storeDistance:
        ld      (BALL_ROLL_ACCUM),hl
        ret

; Four collision substeps together move one complete stored velocity.
; Input DE=velocity and HL=current position; output DE=velocity/4, HL kept.
ScaleSubstepDelta:
        push    hl
        ld      h,d
        ld      l,e
        sra     h
        rr      l
        sra     h
        rr      l                   ; / 4 for one of four substeps
        ex      de,hl
        pop     hl
        ret

; -----------------------------------------------------------------------------
; Ball simulation
; -----------------------------------------------------------------------------

StepBall:
        ; The covered tube is a scripted path, so it bypasses gravity and all
        ; normal collision code. It advances one path node every display frame.
        ld      a,(BALL_IN_TUBE)
        or      a
        jr      z,.notInTube
        jp      StepTube
.notInTube:

        ld      a,(BALL_WAITING)
        or      a
        jr      z,.moving

        ; Any flipper/trigger input launches the ball from the right lane.
        ld      a,(LEFT_ACTIVE)
        ld      c,a
        ld      a,(RIGHT_ACTIVE)
        or      c
        ret     z
        xor     a
        ld      (BALL_WAITING),a
        ld      hl,LAUNCH_VX
        ld      (BALL_VX),hl
        ld      hl,LAUNCH_VY
        ld      (BALL_VY),hl
        ret

.moving:
        ; BUMPER_LOCK prevents a powerful bumper from adding its impulse four
        ; times in the four substeps of one display frame.
        ld      a,(BUMPER_LOCK)
        or      a
        jr      z,.gravity
        dec     a
        ld      (BUMPER_LOCK),a

.gravity:
        ; vy = min(vy + gravity, terminal velocity). Negative values are rising.
        ld      hl,(BALL_VY)
        ld      de,PHYSICS_GRAVITY
        add     hl,de
        bit     7,h
        jr      nz,.storeVy
        ld      a,h
        cp      5
        jr      c,.storeVy
        ld      hl,MAX_FALL_SPEED
.storeVy:
        ld      (BALL_VY),hl

        ; Four smaller movement steps prevent fast balls crossing thin objects
        ; between two collision tests. Gravity is still applied once per frame.
        ; ScaleSubstepDelta returns one quarter velocity, so the four calls
        ; together integrate one complete physics frame without tunnelling.
        ld      a,4
.substep:
        push    af

        ; Integrate one quarter of X and resolve the two vertical walls.
        ld      hl,(BALL_X)
        ld      de,(BALL_VX)
        call    ScaleSubstepDelta
        add     hl,de
        ld      (BALL_X),hl
        call    ResolveTileX
        ld      hl,(BALL_X)
        ld      a,h
        cp      LEFT_WALL
        jr      nc,.rightWall
        ld      hl,LEFT_WALL*256
        ld      (BALL_X),hl
        ld      hl,(BALL_VX)
        bit     7,h
        call    nz,NegateAndDamp
        ld      (BALL_VX),hl
        jr      .moveY

.rightWall:
        cp      RIGHT_WALL+1
        jr      c,.moveY
        ld      hl,RIGHT_WALL*256
        ld      (BALL_X),hl
        ld      hl,(BALL_VX)
        bit     7,h
        call    z,NegateAndDamp
        ld      (BALL_VX),hl

.moveY:
        ld      hl,(BALL_Y)
        ld      de,(BALL_VY)
        call    ScaleSubstepDelta
        add     hl,de
        ld      (BALL_Y),hl
        call    ResolveTileY
        ld      hl,(BALL_Y)

        ; Emergency ceiling bound in case malformed map data leaves a gap.
        ld      a,h
        cp      TOP_WALL
        jr      nc,.objects
        ld      hl,TOP_WALL*256
        ld      (BALL_Y),hl
        ld      hl,(BALL_VY)
        bit     7,h
        call    nz,NegateAndDamp
        ld      (BALL_VY),hl

.objects:
        ; Collision order is deliberate: static geometry first, authored Tiled
        ; objects second, moving flippers last. A tube hit takes ownership and
        ; aborts the remaining checks. A drain reset does the same.
        xor     a
        ld      (OBJECT_CONTACT),a
        call    CheckMapPolygons
        ld      a,(OBJECT_CONTACT)
        or      a
        jr      nz,.lowerTable        ; never resolve one overlap as bumper + flipper
        call    CheckMapCircles
        ld      a,(BALL_IN_TUBE)
        or      a
        jr      nz,.endStepBall
        call    CheckFlippers
.lowerTable:
        call    CheckLowerTable
        ld      a,(BALL_WAITING)
        or      a
        jr      nz,.endStepBall

        pop     af
        dec     a
        jp      nz,.substep
        ret

.endStepBall:
        pop     af
        ret

; Static collision_shape values generated from maps/pinball.tsx:
;   0 empty, 1 solid, 2 ceiling, 3 floor, 4 left wall, 5 right wall,
;   6 slash diagonal and 7 backslash diagonal. Shape 8 is compiled into a
;   circle object by the build tool and therefore becomes 0 in CollisionMap.
;
; Resolve horizontal movement against the leading point of the ball. Shape 1
; is solid from every side; shape 4 is the left table boundary and shape 5 the
; right boundary. The 4 physics substeps keep this point test from tunnelling.
ResolveTileX:
        ld      hl,(BALL_VX)
        ld      a,h
        or      l
        ret     z
        bit     7,h
        jr      nz,.movingLeft

        ld      a,(BALL_X+1)
        add     a,15                 ; rightmost circle point
        ld      b,a
        ld      a,(BALL_Y+1)
        add     a,8
        ld      c,a
        call    GetCollisionShape
        cp      1
        jr      z,.hitRightWall
        cp      5
        ret     nz
.hitRightWall:
        ; Snap the sprite just outside the occupied 8-pixel tile, then reflect
        ; only the horizontal velocity. NegateAndDamp retains 75% energy.
        ld      a,b
        and     0f8h
        sub     16
        ld      h,a
        ld      l,0
        ld      (BALL_X),hl
        ld      hl,(BALL_VX)
        call    NegateAndDamp
        ld      (BALL_VX),hl
        ret

.movingLeft:
        ld      a,(BALL_X+1)
        inc     a                    ; leftmost circle point
        ld      b,a
        ld      a,(BALL_Y+1)
        add     a,8
        ld      c,a
        call    GetCollisionShape
        cp      1
        jr      z,.hitLeftWall
        cp      4
        ret     nz
.hitLeftWall:
        ld      a,b
        and     0f8h
        add     a,7
        ld      h,a
        ld      l,0
        ld      (BALL_X),hl
        ld      hl,(BALL_VX)
        call    NegateAndDamp
        ld      (BALL_VX),hl
        ret

; Vertical equivalent. Shape 2 is the upper table boundary, shape 3 the lower
; surface. Diagonal types are resolved against their 8-pixel height function.
ResolveTileY:
        ld      hl,(BALL_VY)
        ld      a,h
        or      l
        ret     z
        bit     7,h
        jr      nz,.movingUp

        ld      a,(BALL_X+1)
        add     a,8
        ld      b,a
        ld      a,(BALL_Y+1)
        add     a,15                 ; bottom circle point
        ld      c,a
        call    GetCollisionShape
        cp      1
        jr      z,.hitFloor
        cp      3
        jr      z,.hitFloor
        cp      6
        jp      z,ResolveSlopeFloor
        cp      7
        jp      z,ResolveSlopeFloor
        ret
.hitFloor:
        ; BALL_Y is the sprite top-left. Subtracting 16 places its bottom edge
        ; exactly on the top of the contacted tile row.
        ld      a,c
        and     0f8h
        sub     16
        ld      h,a
        ld      l,0
        ld      (BALL_Y),hl
        ld      hl,(BALL_VY)
        call    NegateAndDamp
        ld      (BALL_VY),hl
        ret

.movingUp:
        ; Curved/diagonal ceilings are touched by a top corner before the
        ; centre reaches a flat ceiling. This lets the launcher curve turn
        ; upward velocity into a strong horizontal component.
        ld      a,(BALL_Y+1)
        inc     a
        ld      c,a
        ld      a,(BALL_X+1)
        add     a,15
        ld      b,a
        call    GetCollisionShape
        cp      6
        jp      z,ResolveSlopeCeiling
        cp      7
        jp      z,ResolveSlopeCeiling

        ld      a,(BALL_X+1)
        inc     a
        ld      b,a
        call    GetCollisionShape
        cp      6
        jp      z,ResolveSlopeCeiling
        cp      7
        jp      z,ResolveSlopeCeiling

        ld      a,(BALL_X+1)
        add     a,8
        ld      b,a
        ld      a,(BALL_Y+1)
        inc     a                    ; top circle point
        ld      c,a
        call    GetCollisionShape
        cp      1
        jr      z,.hitCeiling
        cp      2
        ret     nz
.hitCeiling:
        ld      a,c
        and     0f8h
        add     a,7
        ld      h,a
        ld      l,0
        ld      (BALL_Y),hl
        ld      hl,(BALL_VY)
        call    NegateAndDamp
        ld      (BALL_VY),hl
        ret

; A=6 for '/', A=7 for '\\'; B/C are the sampled pixel coordinates.
ResolveSlopeFloor:
        ; Each diagonal tile is an exact one-pixel height function. Comparing
        ; local Y with that height avoids treating its transparent half as solid.
        ld      (BALL_SIDE),a
        ld      a,b
        and     7
        ld      d,a                  ; local X
        ld      a,(BALL_SIDE)
        cp      7
        ld      a,d
        jr      z,.surfaceReady
        ld      a,7
        sub     d                    ; '/' height = 7-localX
.surfaceReady:
        ld      d,a                  ; local surface Y
        ld      a,c
        and     7
        cp      d
        ret     c                    ; bottom point has not reached the line

        ld      a,c
        and     0f8h
        add     a,d
        sub     16
        ld      h,a
        ld      l,0
        ld      (BALL_Y),hl

        ; Reflection against a 45-degree line swaps X/Y velocity components.
        ; Their signs depend on which of the two diagonals was touched.
        ld      hl,(BALL_VX)
        push    hl
        ld      a,(BALL_SIDE)
        cp      7
        ld      hl,(BALL_VY)
        jr      z,.backslash
        call    NegateAndDamp         ; '/' : vx=-vy, vy=-vx
        ld      (BALL_VX),hl
        pop     hl
        call    NegateAndDamp
        ld      (BALL_VY),hl
        ret
.backslash:
        call    DampHL                ; '\\' : vx=vy, vy=vx
        ld      (BALL_VX),hl
        pop     hl
        call    DampHL
        ld      (BALL_VY),hl
        ret

; Upward counterpart for diagonal ceilings. A=shape and B/C are the top-corner
; sample. Reflection is identical, but the ball is separated below the line.
ResolveSlopeCeiling:
        ld      (BALL_SIDE),a
        ld      a,b
        and     7
        ld      d,a
        ld      a,(BALL_SIDE)
        cp      7
        ld      a,d
        jr      z,.surfaceReady
        ld      a,7
        sub     d
.surfaceReady:
        ld      d,a
        ld      a,c
        and     7
        cp      d
        jr      c,.hit
        ret     nz
.hit:
        ld      a,c
        and     0f8h
        add     a,d
        ld      h,a
        ld      l,0
        ld      (BALL_Y),hl

        ld      hl,(BALL_VX)
        push    hl
        ld      a,(BALL_SIDE)
        cp      7
        ld      hl,(BALL_VY)
        jr      z,.backslash
        call    NegateAndDamp         ; '/' : vx=-vy, vy=-vx
        ld      (BALL_VX),hl
        pop     hl
        call    NegateAndDamp
        ld      (BALL_VY),hl
        ret
.backslash:
        call    DampHL                ; '\\' : vx=vy, vy=vx
        ld      (BALL_VX),hl
        pop     hl
        call    DampHL
        ld      (BALL_VY),hl
        ret

; B=pixel X, C=pixel Y. Return A=compiled collision shape, or zero below the
; 32x24 map. Tile index = (Y>>3)*32 + (X>>3).
GetCollisionShape:
        ; A row contains 32 bytes, hence (Y/8)*32. X/8 selects the column.
        ; Shifts and additions are cheaper than a general Z80 multiplication.
        ld      a,c
        cp      192
        jr      nc,.empty
        srl     a
        srl     a
        srl     a
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      a,b
        srl     a
        srl     a
        srl     a
        ld      e,a
        ld      d,0
        add     hl,de
        ld      de,CollisionMap
        add     hl,de
        ld      a,(hl)
        ret
.empty:
        xor     a
        ret

; Return HL = -(HL * 3/4). All table tiles share this material response.
NegateAndDamp:
        xor     a
        sub     l
        ld      l,a
        sbc     a,a
        sub     h
        ld      h,a                  ; HL = -HL

        ld      b,h
        ld      c,l                  ; BC = reflected velocity
        sra     h
        rr      l
        sra     h
        rr      l                    ; HL = reflected velocity / 4
        ex      de,hl
        ld      h,b
        ld      l,c
        or      a
        sbc     hl,de                ; retain 3/4 of the energy
        ret

; Return HL = HL * 3/4 while preserving its sign.
DampHL:
        ld      b,h
        ld      c,l
        sra     h
        rr      l
        sra     h
        rr      l
        ex      de,hl
        ld      h,b
        ld      l,c
        or      a
        sbc     hl,de                ; retain 3/4 of the energy
        ret

; -----------------------------------------------------------------------------
; Tiled object collisions
; -----------------------------------------------------------------------------
;
; Objects live separately from the static collision tiles. The build script
; reads ellipses and polygons from the PinballObjects layer and emits compact
; records. This allows differently sized objects without adding tile types.
;
; Polygon bumpers are compiled to small per-pixel fields. Each four-bit value
; contains normal+1; zero means no physical contact. Two pixels share a byte.
CheckMapPolygons:
        ; Byte zero is the object count. IX starts at the first variable-size
        ; record; its leading size word is used to advance to the next record.
        call    MaybeRearmLastPolygon
        ld      ix,PolygonObjects+1
        ld      a,(PolygonObjects)
        or      a
        ret     z
        ld      b,a
.loop:
        push    bc
        call    LookupPolygonField
        pop     bc
        jr      nc,.next
        ld      (POLY_FIELD_VALUE),a
        and     00fh
        jr      z,.next               ; release margin, not a collision
        dec     a
        ld      (BALL_SIDE),a
        ; The expanded fields of nearby objects may overlap (for example the
        ; new upper-left flipper and bumper1). Claim the current substep so a
        ; second collider cannot immediately undo this bumper's response.
        ld      a,1
        ld      (OBJECT_CONTACT),a
        ; Polygon fields already include the seven-pixel ball radius. The field
        ; therefore answers a ball-centre query directly and supplies a normal.
        call    SeparateCircleOnePixel
        ld      a,(ix+3)
        add     a,7
        ld      b,a
        ld      a,(ix+4)
        add     a,7
        ld      c,a
        ld      a,(ix+10)
        call    QueueObjectAnimation

        ; A post/type 0 or kick 0 uses reflection only. An active bumper first
        ; reflects the incoming component, then adds an outward impulse.
        ld      a,(ix+2)
        or      a
        jr      z,.passive
        ld      a,(ix+7)
        or      a
        jr      z,.passive
        ld      a,(BUMPER_LOCK)
        or      a
        jr      nz,.passive
        ld      a,(LAST_BUMPER_KIND)
        cp      2
        jr      nz,.newActive
        push    ix
        pop     de
        ld      hl,(LAST_BUMPER_PTR)
        or      a
        sbc     hl,de
        jr      z,.passive
.newActive:
        ; Kick property 1/2/3+ maps to 2/3/4 internal pixels per frame. Keeping
        ; this mapping here makes Tiled properties simple integer values.
        call    PassiveCircleResponse
        ld      a,(ix+7)
        cp      2
        ld      hl,0200h
        jr      c,.kickReady
        ld      hl,0300h
        jr      z,.kickReady
        ld      hl,0400h
.kickReady:
        call    AddCircleImpulse
        call    ClampBallVelocity
        push    ix
        pop     hl
        ld      (LAST_BUMPER_PTR),hl
        ld      a,2
        ld      (LAST_BUMPER_KIND),a
        ld      a,12
        ld      (BUMPER_LOCK),a
        ret
.passive:
        jp      PassiveCircleResponse
.next:
        ld      e,(ix+0)
        ld      d,(ix+1)
        add     ix,de
        dec     b
        jp      nz,.loop
        ret

; IX points at a polygon record:
;   +0 size low, +1 size high, +2 type
;   +3 field X, +4 field Y, +5 width, +6 height
;   +7 kick, +8/+9 score, +10 animation-atlas X
;   +11... packed collision nibbles in row-major order
; Return carry set and A=field byte when the ball centre lies inside the field.
LookupPolygonField:
        ld      a,(BALL_X+1)
        add     a,8
        sub     (ix+3)
        jr      c,.outside
        cp      (ix+5)
        jr      nc,.outside
        ld      (POLY_LOCAL_X),a

        ld      a,(BALL_Y+1)
        add     a,8
        sub     (ix+4)
        jr      c,.outside
        cp      (ix+6)
        jr      nc,.outside
        ld      c,a                   ; local Y
        ld      e,(ix+5)              ; row width
        ld      d,0
        ld      hl,0
        ld      a,c
        or      a
        jr      z,.rowReady
.rowLoop:
        add     hl,de
        dec     a
        jr      nz,.rowLoop
.rowReady:
        ; Linear pixel index = localY*width + localX. Division by two selects
        ; the packed byte; index bit zero selects its low or high nibble.
        ld      a,(POLY_LOCAL_X)
        ld      e,a
        ld      d,0
        add     hl,de
        ld      a,l
        and     1
        ld      (POLY_FIELD_VALUE),a  ; select low/even or high/odd nibble
        srl     h
        rr      l
        push    ix
        pop     de
        add     hl,de
        ld      de,11
        add     hl,de
        ld      a,(hl)
        ld      c,a
        ld      a,(POLY_FIELD_VALUE)
        or      a
        ld      a,c
        jr      z,.lowNibble
        rrca
        rrca
        rrca
        rrca
.lowNibble:
        and     00fh
        scf
        ret
.outside:
        or      a                     ; clear carry
        ret

MaybeRearmLastPolygon:
        ; A fired bumper is latched until the ball has genuinely left it. This
        ; avoids another kick when position correction leaves a one-pixel overlap.
        ld      a,(LAST_BUMPER_KIND)
        cp      2
        ret     nz
        ld      ix,(LAST_BUMPER_PTR)
        ; Keep the latch inside the field bounding box plus four pixels. The
        ; exact collision remains polygon-shaped; only rearming is rectangular.
        ld      a,(BALL_X+1)
        add     a,8
        ld      c,a
        ld      a,(ix+3)
        sub     4
        ld      d,a
        ld      a,c
        cp      d
        jr      c,.rearm
        ld      a,(ix+3)
        add     a,(ix+5)
        add     a,4
        ld      d,a
        ld      a,c
        cp      d
        jr      nc,.rearm
        ld      a,(BALL_Y+1)
        add     a,8
        ld      c,a
        ld      a,(ix+4)
        sub     4
        ld      d,a
        ld      a,c
        cp      d
        jr      c,.rearm
        ld      a,(ix+4)
        add     a,(ix+6)
        add     a,4
        ld      d,a
        ld      a,c
        cp      d
        ret     c                     ; still inside the release rectangle
.rearm:
        ld      hl,0
        ld      (LAST_BUMPER_PTR),hl
        xor     a
        ld      (LAST_BUMPER_KIND),a
        ret

; Tiled PinballObjects. Each eight-byte record is:
; type, centre X, centre Y, radius, kick, score low/high, animation-atlas X.
; Type 0 is a passive post; type 1 is a bumper (kick 0 is also passive).
CheckMapCircles:
        call    MaybeRearmLastBumper
        ld      ix,CircleObjects+1
        ld      a,(CircleObjects)
        or      a
        ret     z
.haveObjects:
        ld      b,a
.loop:
        ; Broad phase: compare absolute X/Y distances with the combined radius.
        ; Only candidates inside that square need the more expensive squares.
        ld      a,(ix+3)
        add     a,7                  ; object radius + effective ball radius
        cp      20                   ; SquareTable currently covers 0..19
        jr      c,.radiusReady
        ld      a,19
.radiusReady:
        ld      (OBJECT_RADIUS),a
        call    SquareA
        ld      (OBJECT_RADIUS_SQ),hl

        ld      a,(BALL_X+1)
        add     a,8                  ; the smaller ball remains centred in 16x16
        sub     (ix+1)
        ld      c,a                  ; retain signed horizontal side
        ld      (BALL_HIT_X),a
        call    AbsA
        ld      (ABS_HIT_X),a
        ld      c,a
        ld      a,(OBJECT_RADIUS)
        ld      d,a
        ld      a,c
        cp      d
        jp      nc,.next
        ld      a,c
        ld      e,a                  ; absolute horizontal distance
        call    SquareA
        push    hl

        ld      a,(BALL_Y+1)
        add     a,8
        sub     (ix+2)
        ld      d,a                  ; retain signed vertical side
        ld      (BALL_HIT_Y),a
        call    AbsA
        ld      (ABS_HIT_Y),a
        ld      c,a
        ld      a,(OBJECT_RADIUS)
        ld      d,a
        ld      a,c
        cp      d
        jp      nc,.discardNext
        ld      h,c                  ; retain absolute vertical distance

        ; Narrow phase: dx^2 + dy^2 < combinedRadius^2.
        ld      a,h
        call    SquareA
        pop     de                   ; DE = horizontal distance squared
        add     hl,de
        ld      de,(OBJECT_RADIUS_SQ)
        or      a
        sbc     hl,de
        jp      nc,.next

        call    SelectCircleNormal
        ; Circle/polygon objects use one-pixel separation to escape overlap.
        ; Flippers intentionally do not: separation at their pivot caused loops.
        call    SeparateCircleOnePixel
        ld      a,(ix+1)
        sub     8
        ld      b,a
        ld      a,(ix+2)
        sub     8
        ld      c,a
        ld      a,(ix+7)
        call    QueueObjectAnimation

        ld      a,(ix+0)
        or      a
        jr      z,.passive
        ld      a,(ix+4)
        or      a
        jr      z,.passive
        ld      a,(BUMPER_LOCK)
        or      a
        jr      nz,.passive          ; short debounce after a genuine release
        ld      a,(LAST_BUMPER_KIND)
        cp      1
        jr      nz,.newActive
        push    ix
        pop     de
        ld      hl,(LAST_BUMPER_PTR)
        or      a
        sbc     hl,de
        jr      z,.passive           ; same bumper stays passive until re-armed
.newActive:

        ; Reflect the incoming component, then add one outward bumper impulse.
        call    PassiveCircleResponse
        ld      a,(ix+4)             ; reload kick; A was used by the latch test
        cp      2
        ld      hl,0200h
        jr      c,.kickReady
        ld      hl,0300h
        jr      z,.kickReady
        ld      hl,0400h
.kickReady:
        call    AddCircleImpulse
        call    ClampBallVelocity
        jr      .activeHit

.passive:
        jp      PassiveCircleResponse
.activeHit:
        push    ix
        pop     hl
        ld      (LAST_BUMPER_PTR),hl
        ld      a,1
        ld      (LAST_BUMPER_KIND),a
        ld      a,12                 ; 0.2 s debounce for tight wall corners
        ld      (BUMPER_LOCK),a
        ret

.discardNext:
        pop     hl
.next:
        inc     ix
        inc     ix
        inc     ix
        inc     ix
        inc     ix
        inc     ix
        inc     ix
        inc     ix
        dec     b
        jp      nz,.loop
        ret

; Rearm only after the ball centre is four pixels beyond the collision radius.
; This hysteresis prevents a wall/bumper corner from firing again after a
; single substep that merely grazed the exact mathematical boundary.
MaybeRearmLastBumper:
        ld      a,(LAST_BUMPER_KIND)
        cp      1
        ret     nz
        ld      hl,(LAST_BUMPER_PTR)
        ld      a,h
        or      l
        ret     z
        push    hl
        pop     ix
        ld      a,(ix+3)
        add     a,11                 ; ball radius 7 + release margin 4
        cp      20
        jr      c,.radiusReady
        ld      a,19
.radiusReady:
        ld      (OBJECT_RADIUS),a
        call    SquareA
        ld      (OBJECT_RADIUS_SQ),hl

        ld      a,(BALL_X+1)
        add     a,8
        sub     (ix+1)
        call    AbsA
        ld      c,a
        ld      a,(OBJECT_RADIUS)
        cp      c
        jr      c,.rearm
        jr      z,.rearm
        ld      a,c
        call    SquareA
        push    hl

        ld      a,(BALL_Y+1)
        add     a,8
        sub     (ix+2)
        call    AbsA
        ld      c,a
        ld      a,(OBJECT_RADIUS)
        cp      c
        jr      c,.discardRearm
        jr      z,.discardRearm
        ld      a,c
        call    SquareA
        pop     de
        add     hl,de
        ld      de,(OBJECT_RADIUS_SQ)
        or      a
        sbc     hl,de
        ret     c                    ; still inside the expanded release zone
.rearm:
        ld      hl,0
        ld      (LAST_BUMPER_PTR),hl
        xor     a
        ld      (LAST_BUMPER_KIND),a
        ret
.discardRearm:
        pop     hl
        jr      .rearm

; Choose the nearest of eight outward normals. BALL_SIDE is clockwise:
; 0=right, 1=down-right, 2=down, 3=down-left, 4=left, 5=up-left,
; 6=up, 7=up-right. A 2:1 boundary keeps shallow contacts on an axis.
SelectCircleNormal:
        ld      a,(ABS_HIT_X)
        add     a,a
        ld      c,a                  ; C = 2*abs(dx)
        ld      a,(ABS_HIT_Y)
        cp      c
        jr      nc,.vertical
        add     a,a                  ; A = 2*abs(dy)
        ld      c,a
        ld      a,(ABS_HIT_X)
        cp      c
        jr      nc,.horizontal

        ld      a,(BALL_HIT_X)
        bit     7,a
        jr      nz,.diagLeft
        ld      a,(BALL_HIT_Y)
        bit     7,a
        ld      a,1                  ; down-right
        jr      z,.store
        ld      a,7                  ; up-right
        jr      .store
.diagLeft:
        ld      a,(BALL_HIT_Y)
        bit     7,a
        ld      a,3                  ; down-left
        jr      z,.store
        ld      a,5                  ; up-left
        jr      .store
.horizontal:
        ld      a,(BALL_HIT_X)
        bit     7,a
        ld      a,0
        jr      z,.store
        ld      a,4
        jr      .store
.vertical:
        ld      a,(BALL_HIT_Y)
        bit     7,a
        ld      a,2
        jr      z,.store
        ld      a,6
.store:
        ld      (BALL_SIDE),a
        ret

; Correct only one pixel along the selected normal. This prevents persistent
; overlap without the visible multi-pixel axis snap used by the old resolver.
SeparateCircleOnePixel:
        ld      a,(BALL_SIDE)
        cp      2
        jr      z,.down
        cp      6
        jr      z,.up
        cp      4
        jr      z,.left
        or      a
        jr      z,.right
        bit     2,a
        jr      z,.diagRight
.diagLeft:
        call    MoveBallLeftOne
        jr      .diagY
.diagRight:
        call    MoveBallRightOne
.diagY:
        ld      a,(BALL_SIDE)
        cp      4
        jr      c,.down
.up:
        ld      hl,(BALL_Y)
        ld      de,0ff00h
        add     hl,de
        ld      (BALL_Y),hl
        ret
.down:
        ld      hl,(BALL_Y)
        ld      de,0100h
        add     hl,de
        ld      (BALL_Y),hl
        ret
.left:
        jp      MoveBallLeftOne
.right:
        jp      MoveBallRightOne

MoveBallLeftOne:
        ld      hl,(BALL_X)
        ld      de,0ff00h
        add     hl,de
        ld      (BALL_X),hl
        ret
MoveBallRightOne:
        ld      hl,(BALL_X)
        ld      de,0100h
        add     hl,de
        ld      (BALL_X),hl
        ret

; Reflect only while velocity points into the selected surface. Axis normals
; use the existing material damping. For a 45-degree normal the exact fixed-
; point reflection is a (possibly negated) swap of VX and VY.
PassiveCircleResponse:
        ld      a,(BALL_SIDE)
        bit     0,a
        jr      nz,.diagonal
        cp      2
        jr      z,.down
        cp      6
        jr      z,.up
        cp      4
        jr      z,.left
.right:
        ld      hl,(BALL_VX)
        bit     7,h
        ret     z
        call    NegateAndDamp
        ld      (BALL_VX),hl
        ret
.left:
        ld      hl,(BALL_VX)
        bit     7,h
        ret     nz
        call    NegateAndDamp
        ld      (BALL_VX),hl
        ret
.down:
        ld      hl,(BALL_VY)
        bit     7,h
        ret     z
        call    NegateAndDamp
        ld      (BALL_VY),hl
        ret
.up:
        ld      hl,(BALL_VY)
        bit     7,h
        ret     nz
        call    NegateAndDamp
        ld      (BALL_VY),hl
        ret
.diagonal:
        cp      1
        jr      z,.testSE
        cp      3
        jr      z,.testSW
        cp      5
        jr      z,.testNW
        ; NE: approaching when VX-VY < 0; reflect to (VY,VX).
        ld      hl,(BALL_VX)
        ld      de,(BALL_VY)
        or      a
        sbc     hl,de
        bit     7,h
        ret     z
        jr      .swap
.testSE:
        ; SE: approaching when VX+VY < 0; reflect to (-VY,-VX).
        ld      hl,(BALL_VX)
        ld      de,(BALL_VY)
        add     hl,de
        bit     7,h
        ret     z
        jr      .negSwap
.testSW:
        ; SW: approaching when VX-VY > 0; reflect to (VY,VX).
        ld      hl,(BALL_VX)
        ld      de,(BALL_VY)
        or      a
        sbc     hl,de
        bit     7,h
        ret     nz
        ld      a,h
        or      l
        ret     z
        jr      .swap
.testNW:
        ; NW: approaching when VX+VY > 0; reflect to (-VY,-VX).
        ld      hl,(BALL_VX)
        ld      de,(BALL_VY)
        add     hl,de
        bit     7,h
        ret     nz
        ld      a,h
        or      l
        ret     z
        jr      .negSwap
.swap:
        ld      hl,(BALL_VX)
        push    hl
        ld      hl,(BALL_VY)
        call    DampHL
        ld      (BALL_VX),hl
        pop     hl
        call    DampHL
        ld      (BALL_VY),hl
        ret
.negSwap:
        ld      hl,(BALL_VX)
        push    hl
        ld      hl,(BALL_VY)
        call    NegateAndDamp
        ld      (BALL_VX),hl
        pop     hl
        call    NegateAndDamp
        ld      (BALL_VY),hl
        ret

; HL is the bumper strength in 8.8 pixels/frame. Diagonal impulses use 3/4
; per axis, closely approximating a normalised 45-degree vector.
AddCircleImpulse:
        ld      a,(BALL_SIDE)
        bit     0,a
        jr      nz,.diagonal
        cp      2
        jr      z,.down
        cp      6
        jr      z,.up
        cp      4
        jr      z,.left
.right:
        ld      de,(BALL_VX)
        add     hl,de
        ld      (BALL_VX),hl
        ret
.left:
        call    NegateHL
        jr      .right
.down:
        ld      de,(BALL_VY)
        add     hl,de
        ld      (BALL_VY),hl
        ret
.up:
        call    NegateHL
        jr      .down
.diagonal:
        call    DampHL
        push    hl                   ; positive diagonal component
        ld      a,(BALL_SIDE)
        cp      3
        jr      c,.xPositive
        cp      7
        jr      z,.xPositive
        call    NegateHL
.xPositive:
        ld      de,(BALL_VX)
        add     hl,de
        ld      (BALL_VX),hl
        pop     hl
        ld      a,(BALL_SIDE)
        cp      5
        jr      c,.yPositive
        call    NegateHL
.yPositive:
        ld      de,(BALL_VY)
        add     hl,de
        ld      (BALL_VY),hl
        ret

; Active bumpers add energy, but repeated wall contacts must never accumulate
; beyond the same five-pixel component limit used for terminal fall speed.
ClampBallVelocity:
        ld      hl,(BALL_VX)
        call    ClampHLToFive
        ld      (BALL_VX),hl
        ld      hl,(BALL_VY)
        call    ClampHLToFive
        ld      (BALL_VY),hl
        ret

ClampHLToFive:
        bit     7,h
        jr      nz,.negative
.positive:
        ld      a,h
        cp      5
        ret     c
        jr      nz,.positiveLimit
        ld      a,l
        or      a
        ret     z
.positiveLimit:
        ld      hl,0500h
        ret
.negative:
        call    NegateHL
        ld      a,h
        cp      5
        jr      c,.restoreNegative
        jr      nz,.negativeLimit
        ld      a,l
        or      a
        jr      z,.restoreNegative
.negativeLimit:
        ld      hl,0500h
.restoreNegative:
        jp      NegateHL

NegateHL:
        xor     a
        sub     l
        ld      l,a
        sbc     a,a
        sub     h
        ld      h,a
        ret

AbsA:
        bit     7,a
        ret     z
        neg
        ret

; Return HL = A*A for A in the range 0..19.
SquareA:
        push    de
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,SquareTable
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        pop     de
        ret

SquareTable:
        dw      0,1,4,9,16,25,36,49,64,81
        dw      100,121,144,169,196,225,256,289,324,361

; -----------------------------------------------------------------------------
; Flipper collisions
; -----------------------------------------------------------------------------
;
; maps/flippers.tmx supplies one convex polygon for every left/right animation
; frame. The build expands each polygon by the ball radius and compiles it into
; a packed per-pixel normal field, so runtime collision is just one lookup.
; Fields are pivot-relative and therefore reusable at another table position.
; Flipper collision changes velocity only; it never rewrites BALL_X/BALL_Y.
CheckFlippers:
        ld      a,(FlipperInstances)
        or      a
        ret     z
        ld      b,a
        ld      iy,FlipperInstances+1
.loop:
        push    bc
        call    GetInstanceFrame
        ld      (FLIPPER_NORMAL+1),a  ; temporary current frame, overwritten later
        ld      c,a
        ld      a,(iy+0)             ; visual/collision side: 0 left, 1 right
        or      a
        ld      a,c
        jr      z,.fieldReady
        add     a,3                  ; right fields occupy header slots 3..5
.fieldReady:
        call    LoadFlipperCollisionField
        ld      a,(iy+2)
        ld      (FLIPPER_PIVOT_X),a
        ld      a,(iy+3)
        ld      (FLIPPER_PIVOT_Y),a
        call    LookupFlipperCollisionField
        jp      nc,.next
        and     00fh
        jp      z,.next
        dec     a
        ld      (BALL_SIDE),a
        call    MeasureFlipperDistance
        call    GetInstanceKick
        or      a
        jr      nz,.activeHit

        ; Normal 6 is the long upper blade edge. It uses slope-aware rolling;
        ; cap, underside and polygon corners use their generated normal directly.
        ld      a,(BALL_SIDE)
        cp      6
        jr      nz,.genericPassive
        ld      a,(iy+0)
        or      a
        jr      nz,.rightBlade
        ld      a,(FLIPPER_NORMAL+1)
        or      a
        ld      a,3                  ; resting left: downhill right
        jr      z,.bladeReady
        ld      a,1                  ; raised left: downhill toward left pivot
        jr      .bladeReady
.rightBlade:
        ld      a,(FLIPPER_NORMAL+1)
        or      a
        ld      a,4                  ; resting right: downhill left
        jr      z,.bladeReady
        ld      a,2                  ; raised right: downhill toward right pivot
.bladeReady:
        ld      (BALL_SIDE),a
        call    PassiveFlipperHit
        pop     bc
        ret
.genericPassive:
        call    PassiveCircleResponse
        pop     bc
        ret

.activeHit:
        ; Close to the axle the horizontal component points outward; farther
        ; along the blade it points inward. The generated base threshold makes
        ; this decision independent of the flipper's world position.
        ld      a,(FLIPPER_DISTANCE)
        cp      (ix+4)
        jr      nc,.inwardKick
        ld      a,(iy+0)
        or      a
        ld      hl,0fec0h            ; left base pushes left
        jr      z,.storeKickX
        ld      hl,0140h             ; right base pushes right
        jr      .storeKickX
.inwardKick:
        ld      a,(iy+0)
        or      a
        ld      hl,0140h             ; left blade points inward/right
        jr      z,.storeKickX
        ld      hl,0fec0h            ; right blade points inward/left
.storeKickX:
        ld      (BALL_VX),hl
        ld      a,(FLIPPER_DISTANCE)
        cp      (ix+4)
        ld      hl,FLIPPER_BASE_VY
        jr      c,.storeKick
        cp      (ix+5)
        ld      hl,FLIPPER_MID_VY
        jr      c,.storeKick
        ld      hl,FLIPPER_TIP_VY
.storeKick:
        ld      (BALL_VY),hl
        ld      a,5
        ld      (BUMPER_LOCK),a
        pop     bc
        ret
.next:
        pop     bc
        ld      de,8
        add     iy,de
        dec     b
        jp      nz,.loop
        ret

; Map instance control 0 uses the left state; control 1 uses the right state.
GetInstanceFrame:
        ld      a,(iy+1)
        or      a
        ld      a,(LEFT_FRAME)
        ret     z
        ld      a,(RIGHT_FRAME)
        ret

GetInstanceKick:
        ld      a,(iy+1)
        or      a
        ld      a,(LEFT_KICK)
        ret     z
        ld      a,(RIGHT_KICK)
        ret

; Collision with a stationary flipper. The former circular collision samples
; are gone; this response remains only for the polygon's long upper blade edge:
; roughly 8 horizontal pixels for every 3 vertical pixels. This avoids treating
; the flipper as a sticky horizontal shelf.
PassiveFlipperHit:
        ld      hl,(BALL_VX)
        ld      (FLIPPER_OLD_VX),hl
        ld      hl,(BALL_VY)
        ld      (FLIPPER_OLD_VY),hl

        ; Normal approach speed is 8*VY-3*VX for a \ slope and 8*VY+3*VX
        ; for a / slope. If it is zero or negative, the ball already travels
        ; away from the surface; responding again would cause contact jitter.
        add     hl,hl
        add     hl,hl
        add     hl,hl                 ; HL = 8*VY
        ex      de,hl
        ld      hl,(FLIPPER_OLD_VX)
        ld      b,h
        ld      c,l
        add     hl,hl
        add     hl,bc                 ; HL = 3*VX
        ld      a,(BALL_SIDE)
        cp      2
        jr      z,.positiveSlope
        cp      3
        jr      z,.positiveSlope
        ex      de,hl
        add     hl,de                 ; / slope: 8*VY + 3*VX
        jr      .normalReady
.positiveSlope:
        ex      de,hl
        or      a
        sbc     hl,de                 ; \ slope: 8*VY - 3*VX
.normalReady:
        ld      (FLIPPER_NORMAL),hl
        bit     7,h
        ret     nz
        ld      a,h
        or      l
        ret     z
        ld      a,h
        cp      4                    ; small normal speed is resting contact
        jp      c,PassiveFlipperRoll

        ; Tangential velocity loses very little energy. In this inexpensive
        ; fixed-point approximation:
        ;   VX' = 7/8*VX +/- 3/8*VY
        ; The sign mirrors with the flipper slope.
        ld      hl,(FLIPPER_OLD_VX)
        call    DampHLSevenEighths
        push    hl
        ld      hl,(FLIPPER_OLD_VY)
        call    ScaleHLThreeEighths
        call    NegateForNegativeFlipperSlope
        ex      de,hl
        pop     hl
        add     hl,de
        ld      (BALL_VX),hl

        ; A hard impact returns about 1/4 of the normal component:
        ;   VY' = +/-3/8*VX - 1/8*VY
        ld      hl,(FLIPPER_OLD_VX)
        call    ScaleHLThreeEighths
        call    NegateForNegativeFlipperSlope
        ex      de,hl
        ld      hl,(FLIPPER_OLD_VY)
        sra     h
        rr      l
        sra     h
        rr      l
        sra     h
        rr      l                    ; HL = 1/8*old VY
        call    NegateHL
        add     hl,de
        ld      (BALL_VY),hl
        ret

; A gentle contact is a support constraint, not a bounce and not glue. Project
; velocity onto the blade tangent with coefficients close to the 8:3 slope.
; Sixteenth-based fractions deliberately keep more useful low bits than a more
; exact /64 approximation would on this 8.8 fixed-point Z80 simulation.
PassiveFlipperRoll:
        ld      hl,(FLIPPER_OLD_VX)
        call    DampHLSevenEighths
        push    hl
        ld      hl,(FLIPPER_OLD_VY)
        call    ScaleHLFiveSixteenths
        call    NegateForNegativeFlipperSlope
        ex      de,hl
        pop     hl
        add     hl,de
        ; This +/-3/256 impulse is gravity projected along the blade. It is an
        ; acceleration rather than a minimum/fixed roll speed, so momentum is
        ; preserved and the ball naturally gathers speed while descending.
        ld      a,(BALL_SIDE)
        cp      2
        ld      de,0003h
        jr      z,.addRollGravity
        cp      3
        jr      z,.addRollGravity
        ld      de,0fffdh
.addRollGravity:
        add     hl,de
        ld      (BALL_VX),hl

        ld      hl,(FLIPPER_OLD_VX)
        call    ScaleHLFiveSixteenths
        call    NegateForNegativeFlipperSlope
        ex      de,hl
        ld      hl,(FLIPPER_OLD_VY)
        sra     h
        rr      l
        sra     h
        rr      l
        sra     h
        rr      l                    ; +1/8*old VY: no restitution at rest
        add     hl,de
        ld      (BALL_VY),hl
        ret

; Side ids 2 (held right) and 3 (resting left) use a positive transfer term.
; Sides 1 and 4 are their exact mirrors and therefore negate that term.
NegateForNegativeFlipperSlope:
        ld      a,(BALL_SIDE)
        cp      2
        ret     z
        cp      3
        ret     z
        jp      NegateHL

; Return HL = HL * 7/8 while preserving its sign. This is deliberately much
; less friction than the 3/4 damping used for a direct wall rebound.
DampHLSevenEighths:
        ld      b,h
        ld      c,l
        sra     h
        rr      l
        sra     h
        rr      l
        sra     h
        rr      l                   ; HL = original / 8
        ex      de,hl
        ld      h,b
        ld      l,c
        or      a
        sbc     hl,de               ; original - original/8
        ret

; Return HL = HL * 3/8 using signed arithmetic shifts. Flipper response uses
; this for the small amount of velocity transferred across its diagonal slope.
ScaleHLThreeEighths:
        sra     h
        rr      l
        sra     h
        rr      l
        sra     h
        rr      l                    ; HL = original / 8
        ld      d,h
        ld      e,l
        add     hl,hl                ; original / 4
        add     hl,de                ; original * 3/8
        ret

; Return HL = HL * 5/16. This is slightly below the exact cross coefficient of
; an 8:3 slope, ensuring contacts are stable while retaining precision at crawl
; speeds (where a six-bit right shift would quantise the result to zero).
ScaleHLFiveSixteenths:
        sra     h
        rr      l
        sra     h
        rr      l
        sra     h
        rr      l
        sra     h
        rr      l                    ; HL = original / 16
        ld      d,h
        ld      e,l
        add     hl,hl                ; 2/16
        add     hl,hl                ; 4/16
        add     hl,de                ; 5/16
        ret

; Select one of the six generated records. A is 0..2 for left frames and 3..5
; for right frames. The binary header contains six offsets relative to its base.
LoadFlipperCollisionField:
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,FlipperCollisionData
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      hl,FlipperCollisionData
        add     hl,de
        push    hl
        pop     ix
        ret

; Record layout:
;   +0/+1 signed field origin relative to pivot, +2 width, +3 height
;   +4 base distance limit, +5 tip distance start, +6 packed normal field
; Return carry set and A=normal+1 when the current ball centre is in the field.
LookupFlipperCollisionField:
        ld      a,(ix+0)
        ld      c,a
        ld      a,(FLIPPER_PIVOT_X)
        add     a,c                   ; absolute field origin X
        ld      c,a
        ld      a,(BALL_X+1)
        add     a,8
        sub     c
        jr      c,.outside
        cp      (ix+2)
        jr      nc,.outside
        ld      (POLY_LOCAL_X),a

        ld      a,(ix+1)
        ld      c,a
        ld      a,(FLIPPER_PIVOT_Y)
        add     a,c                   ; absolute field origin Y
        ld      c,a
        ld      a,(BALL_Y+1)
        add     a,8
        sub     c
        jr      c,.outside
        cp      (ix+3)
        jr      nc,.outside
        ld      c,a                   ; local Y

        ld      e,(ix+2)
        ld      d,0
        ld      hl,0
        ld      a,c
        or      a
        jr      z,.rowReady
.rowLoop:
        add     hl,de
        dec     a
        jr      nz,.rowLoop
.rowReady:
        ld      a,(POLY_LOCAL_X)
        ld      e,a
        ld      d,0
        add     hl,de
        ld      a,l
        and     1
        ld      (POLY_FIELD_VALUE),a
        srl     h
        rr      l
        push    ix
        pop     de
        add     hl,de
        ld      de,6
        add     hl,de
        ld      a,(hl)
        ld      c,a
        ld      a,(POLY_FIELD_VALUE)
        or      a
        ld      a,c
        jr      z,.lowNibble
        rrca
        rrca
        rrca
        rrca
.lowNibble:
        and     00fh
        scf
        ret
.outside:
        or      a
        ret

; Store the absolute horizontal ball-centre distance from the current pivot.
; Generated thresholds in the selected record make kick zones asset-driven.
MeasureFlipperDistance:
        ld      a,(BALL_X+1)
        add     a,8
        ld      c,a
        ld      a,(FLIPPER_PIVOT_X)
        ld      b,a
        ld      a,c
        sub     b
        call    AbsA
        ld      (FLIPPER_DISTANCE),a
        ret

; Enter the covered pipe only from its open right-hand side while travelling
; left. Normal collisions are suspended until StepTube reaches the exit.
CheckTubeEntrance:
        ; The entrance is a small centre-coordinate rectangle. Requiring VX<0
        ; prevents a ball travelling outwards from being recaptured immediately.
        ld      hl,(BALL_VX)
        bit     7,h
        ret     z
        ld      a,(BALL_X+1)
        add     a,8
        cp      48
        ret     c
        cp      69
        ret     nc
        ld      a,(BALL_Y+1)
        add     a,8
        cp      128
        ret     c
        cp      138
        ret     nc

        ld      a,1
        ld      (BALL_IN_TUBE),a
        xor     a
        ld      (TUBE_INDEX),a
        ld      (BUMPER_LOCK),a
        ld      hl,0
        ld      (BALL_VX),hl
        ld      (BALL_VY),hl
        ret

StepTube:
        ; TubePath stores top-left byte coordinates as X,Y pairs. Scripted
        ; movement is deterministic and avoids collisions with the covered art.
        ld      a,(TUBE_INDEX)
        ld      e,a
        ld      d,0
        ld      hl,TubePath
        add     hl,de
        ld      a,(hl)
        cp      0ffh
        jr      z,.exit
        ld      b,a
        inc     hl
        ld      c,(hl)
        ld      h,b
        ld      l,0
        ld      (BALL_X),hl
        ld      h,c
        ld      l,0
        ld      (BALL_Y),hl
        ld      a,(TUBE_INDEX)
        add     a,2
        ld      (TUBE_INDEX),a
        ret
.exit:
        ; Restore ordinary physics with a small upward/rightward exit velocity.
        xor     a
        ld      (BALL_IN_TUBE),a
        ld      hl,TUBE_EXIT_VX
        ld      (BALL_VX),hl
        ld      hl,TUBE_EXIT_VY
        ld      (BALL_VY),hl
        ret

; Top-left ball positions through the covered L-shaped pipe.  FF terminates it.
TubePath:
        db      40,124,36,124,32,124,28,124,24,124,20,124
        db      20,120,20,116,20,112,20,108,20,104,20,100
        db      20,96,20,92,20,88,20,84,20,80,20,76
        db      20,72,20,68,20,64,20,60,20,56,20,52
        db      20,48,20,44,20,40,20,36
        db      0ffh

; The tilemap ends at Y=191. Anything continuing below the flippers reaches
; the shared drain line; static lower guides now come from collision tiles.
CheckLowerTable:
        ; The authored map is 192 pixels high, while the drain threshold lies
        ; below the flippers. Crossing it parks a new ball in the launch lane.
        ld      a,(BALL_Y+1)
        cp      DRAIN_Y
        ret     c
        jp      ResetBall

ResetBall:
        ; Reset gameplay state but deliberately leave an active object flash
        ; alone: UpdateObjectAnimation will still restore its original pixels.
        ld      hl,224*256           ; two pixels farther right in launch lane
        ld      (BALL_X),hl
        ld      hl,184*256
        ld      (BALL_Y),hl
        ld      hl,0
        ld      (BALL_VX),hl
        ld      (BALL_VY),hl
        ld      a,1
        ld      (BALL_WAITING),a
        xor     a
        ld      (BUMPER_LOCK),a
        ld      (BALL_IN_TUBE),a
        ld      (TUBE_INDEX),a
        ld      (LEFT_ACTIVE),a
        ld      (RIGHT_ACTIVE),a
        ld      (LEFT_FRAME),a
        ld      (RIGHT_FRAME),a
        ld      (LEFT_KICK),a
        ld      (RIGHT_KICK),a
        ld      (BALL_FRAME),a
        ld      (LAST_BUMPER_KIND),a
        ld      hl,0
        ld      (BALL_ROLL_ACCUM),hl
        ld      (LAST_BUMPER_PTR),hl
        ret

; Queue one 16x16 object flash. A is the delta frame's X in the hidden atlas,
; B/C are its playfield destination. Ignore another hit until this brief flash
; has restored the first object, preventing abandoned highlighted graphics.
QueueObjectAnimation:
        ; The build tool stores XOR differences, not complete frames. Source X
        ; therefore identifies one 16x16 delta in hidden scanlines 212..227.
        cp      0ffh
        ret     z
        ld      d,a
        ld      a,(OBJECT_ANIM_TIMER)
        or      a
        ret     nz
        ld      a,d
        ld      (OBJECT_ANIM_SOURCE_X),a
        ld      a,b
        ld      (OBJECT_ANIM_TARGET_X),a
        ld      a,c
        ld      (OBJECT_ANIM_TARGET_Y),a
        ld      a,088h               ; pending draw plus eight visible frames
        ld      (OBJECT_ANIM_TIMER),a
        ret

; Run in VBlank. XOR the normal/hit delta once to show the hit frame, hold it
; for eight frames, then XOR the same pixels again to restore the original.
UpdateObjectAnimation:
        ; Timer bit 7 means "not drawn yet". This defers the VDP command from
        ; the middle of physics to the next VBlank-safe video update.
        ld      a,(OBJECT_ANIM_TIMER)
        or      a
        ret     z
        bit     7,a
        jr      z,.count
        and     07fh
        ld      (OBJECT_ANIM_TIMER),a
        ld      a,(OBJECT_ANIM_SOURCE_X)
        jr      .draw
.count:
        dec     a
        ld      (OBJECT_ANIM_TIMER),a
        ret     nz
        ld      a,(OBJECT_ANIM_SOURCE_X)
.draw:
        ld      (OBJECT_ANIM_COMMAND+0),a
        ld      a,(OBJECT_ANIM_TARGET_X)
        ld      (OBJECT_ANIM_COMMAND+4),a
        ld      a,(OBJECT_ANIM_TARGET_Y)
        ld      (OBJECT_ANIM_COMMAND+6),a
        ld      hl,OBJECT_ANIM_COMMAND
        jp      VDP_LMMM_XOR

; -----------------------------------------------------------------------------
; Video
; -----------------------------------------------------------------------------

InitGraphics:
        ; Copy the mostly constant VDP command once; later flashes patch only
        ; source X and destination X/Y in this writable RAM block.
        ld      hl,ObjectAnimationCommandTemplate
        ld      de,OBJECT_ANIM_COMMAND
        ld      bc,15
        ldir
        call    InitPalette

        ; Enable 16x16, non-magnified sprites.
        ld      a,(RG1SAV)
        and     %11111110
        or      %00000010
        ld      (RG1SAV),a
        ld      b,a
        ld      c,1
        call    WRTVDP

        ; Upload the tile-rendered table composed from maps/pinbalmap.tmx and
        ; gfx/tileset.png. The last hidden rows contain animation XOR deltas.
        call    UploadPlayfield
        call    UploadPolygonObjects
        call    DrawFlippers

        ; Eight ball frames use two overlapping OR-sprites each.
        ld      hl,SpritePatterns
        ld      de,SPRITE_PATTERNS
        ld      bc,8*2*32
        call    CopyToVRAMPage1

        ; SCREEN 5 uses the MSX2 per-scanline sprite colour table.
        ld      hl,SpriteColors
        ld      de,SPRITE_COLORS
        ld      bc,2*16
        call    CopyToVRAMPage1

        ; Copy static X/pattern fields and the end marker to writable RAM.
        ld      hl,InitialSAT
        ld      de,SAT_SHADOW
        ld      bc,12
        ldir
        ret

; Expand each compressed half through the reusable 16 KiB RAM window and copy
; it to VRAM. Both source streams stay below CPU address 8000h.
UploadPlayfield:
        ; Page 2 (8000h-BFFFh) is RAM in this cartridge setup. It is a temporary
        ; buffer only: both compressed streams and live collision data remain
        ; directly readable below 8000h in the ROM page.
        ld      hl,PlayfieldBank0
        ld      de,08000h
        call    UnpackPletterRAM
        ld      hl,08000h
        ld      de,00000h
        ld      bc,04000h
        call    LDIRVM
        ld      hl,PlayfieldBank1
        ld      de,08000h
        call    UnpackPletterRAM
        ld      hl,08000h
        ld      de,04000h
        ld      bc,04000h
        jp      LDIRVM

; Polygon normal fields compress very well but can grow when the map gains
; objects. Keeping the packed stream in cartridge page 1 and expanding it into
; the now-free page-2 RAM avoids silently reading FFh beyond address 7FFFh.
UploadPolygonObjects:
        ld      hl,PackedPolygonObjects
        ld      de,PolygonObjects
        jp      UnpackPletterRAM

; Pletter v0.5c depacker. Each 16 KiB bank is unpacked to the free RAM window
; at 8000h-BFFFh and then copied to VRAM by UploadPlayfield.
UnpackPletterRAM:
        ; Pletter combines literal bytes with backward copies. EXX keeps the
        ; compressed source and decompressed destination in separate register
        ; sets; IX selects the encoded offset mode and IY returns to the loop.
        push    ix
        push    iy
        ld      a,(hl)
        inc     hl
        exx
        ld      de,0
        add     a,a
        inc     a
        rl      e
        add     a,a
        rl      e
        add     a,a
        rl      e
        rl      e
        ld      hl,.modes
        add     hl,de
        ld      e,(hl)
        ld      ixl,e
        inc     hl
        ld      e,(hl)
        ld      ixh,e
        ld      e,1
        exx
        ld      iy,.loop
.literal:
        ldi
.loop:
        add     a,a
        call    z,.getbit
        jr      nc,.literal
        exx
        ld      h,d
        ld      l,e
.getlen:
        add     a,a
        call    z,.getbitexx
        jr      nc,.lenok
.lenloop:
        add     a,a
        call    z,.getbitexx
        adc     hl,hl
        jp      c,.done
        add     a,a
        call    z,.getbitexx
        jr      nc,.lenok
        add     a,a
        call    z,.getbitexx
        adc     hl,hl
        jp      c,.done
        add     a,a
        call    z,.getbitexx
        jp      c,.lenloop
.lenok:
        inc     hl
        exx
        ld      c,(hl)
        inc     hl
        ld      b,0
        bit     7,c
        jp      z,.offsetReady
        jp      ix
.mode6:
        add     a,a
        call    z,.getbit
        rl      b
.mode5:
        add     a,a
        call    z,.getbit
        rl      b
.mode4:
        add     a,a
        call    z,.getbit
        rl      b
.mode3:
        add     a,a
        call    z,.getbit
        rl      b
.mode2:
        add     a,a
        call    z,.getbit
        rl      b
        add     a,a
        call    z,.getbit
        jr      nc,.offsetReady
        or      a
        inc     b
        res     7,c
.offsetReady:
        inc     bc
        push    hl
        exx
        push    hl
        exx
        ld      l,e
        ld      h,d
        sbc     hl,bc
        pop     bc
        ldir
        pop     hl
        jp      iy
.done:
        pop     iy
        pop     ix
        ret

.getbit:
        ld      a,(hl)
        inc     hl
        rla
        ret
.getbitexx:
        exx
        ld      a,(hl)
        inc     hl
        exx
        rla
        ret
.modes:
        dw      .offsetReady,.mode2,.mode3,.mode4,.mode5,.mode6

; Copy BC bytes to an address in VRAM bank 1. Sprite tables live between
; 07400h and 07800h; setting R#14 explicitly prevents BIOS/VDP bank state from
; turning uninitialised SAT data into a screen full of stray sprites.
CopyToVRAMPage1:
        ; R#14 selects the 16 KiB VRAM bank. The following two writes set the
        ; 14-bit address with bit 6 marking a write operation.
        di
        push    hl
        ld      a,1
        out     (099h),a
        ld      a,14+128
        out     (099h),a
        ld      a,e
        out     (099h),a
        ld      a,d
        and     03fh
        or      040h
        out     (099h),a
        pop     hl
.byte:
        ld      a,(hl)
        out     (098h),a
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,.byte
        ei
        ret

; Draw every map instance. Each owns three 34x23 frames baked over the local
; playfield background, so arbitrary placements restore their swept area.
DrawFlippers:
        ld      a,(FlipperInstances)
        or      a
        ret     z
        ld      b,a
        ld      iy,FlipperInstances+1
.loop:
        push    bc
        call    GetInstanceFrame
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,FlipperFrameOffsets
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      l,(iy+6)
        ld      h,(iy+7)
        add     hl,de                 ; instance frame base + selected frame
        ld      de,FlipperFrameData
        add     hl,de
        ld      e,(iy+4)
        ld      d,(iy+5)             ; packed SCREEN 5 destination address
        call    DrawFlipperFrame
        pop     bc
        ld      de,8
        add     iy,de
        djnz    .loop
        ret

DrawFlipperFrame:
        ; SCREEN 5 packs two horizontal pixels per byte, hence 34 pixels=17
        ; bytes. Adding 128 bytes advances one complete 256-pixel scanline.
        di
        ; Destination bit 14 selects physical VRAM bank 0 or 1. The original
        ; two instances both lived below Y=128 and could hardcode bank 1; map
        ; instances may be anywhere on screen.
        ld      a,d
        and     040h
        rlca
        rlca                         ; D bit 6 -> R#14 value 0 or 1
        out     (099h),a
        ld      a,14+128
        out     (099h),a
        ld      a,23                 ; full pivot-aligned swept height
.row:
        push    af
        ld      a,e
        out     (099h),a
        ld      a,d
        and     03fh
        or      040h
        out     (099h),a
        ld      c,098h
        ld      b,17                 ; 34 SCREEN 5 pixels
        otir
        ld      a,e
        add     a,128                ; next 256-pixel bitmap scanline
        ld      e,a
        jr      nc,.noCarry
        inc     d
.noCarry:
        pop     af
        dec     a
        jr      nz,.row
        ei
        ret

InitPalette:
        di
        xor     a                    ; start at palette entry 0
        out     (099h),a
        ld      a,128+16
        out     (099h),a
        ld      hl,Screen5Palette
        ld      bc,32*256+09ah
        otir
        ei
        ret

; HL points to SX,SY,DX,DY,NX,NY (words), colour, ARG and LMMM-XOR command.
VDP_LMMM_XOR:
        ; LMMM performs a logical pixel copy. XORing normal^hit over the normal
        ; image produces hit; applying the identical command again restores it.
        call    WaitVDPCommand
        ld      bc,(15+128)*256+099h
        ld      de,(17+128)*256+32
        di
        out     (c),e                ; indirect writes start at VDP R#32
        out     (c),d
        ld      c,09bh
        ld      b,15
        otir                         ; R#32 through R#46, command last
        ei
        ret

WaitVDPCommand:
        ; Status register 2 bit CE is one while a command-engine operation runs.
        ; Restore status-register selection to zero before returning to BIOS.
.wait:
        ld      bc,(15+128)*256+099h
        ld      de,2                 ; select status register 2
        di
        out     (c),e
        out     (c),b
        in      a,(099h)
        rra                          ; CE flag -> carry
        ld      a,0                  ; select status register 0 again
        out     (c),a
        out     (c),b
        ei
        jr      c,.wait
        ret

UpdateSprites:
        ; Both sprite planes always receive the same X/Y. During tube travel Y
        ; is moved off-screen while retaining the SAT end marker at entry three.
        ld      a,(BALL_IN_TUBE)
        or      a
        jr      z,.ballVisible
        ld      a,212                ; off-screen, without terminating the SAT
        ld      (SAT_SHADOW+0),a
        ld      (SAT_SHADOW+4),a
        jr      .ballX
.ballVisible:
        ld      a,(BALL_Y+1)
        dec     a                    ; MSX SAT stores Y-1
        ld      (SAT_SHADOW+0),a
        ld      (SAT_SHADOW+4),a
.ballX:
        ld      a,(BALL_X+1)
        ld      (SAT_SHADOW+1),a
        ld      (SAT_SHADOW+5),a

        ; Each frame occupies two 16x16 pattern slots: grey first, then the
        ; black CC/OR layer. Pattern numbers therefore advance by eight.
        ld      a,(BALL_FRAME)
        add     a,a
        add     a,a
        add     a,a
        ld      (SAT_SHADOW+2),a
        add     a,4
        ld      (SAT_SHADOW+6),a

.copySAT:
        ld      hl,SAT_SHADOW
        ld      de,SPRITE_ATTR
        ld      bc,12
        jp      CopyToVRAMPage1

InitialSAT:
        ; SAT entries are Y, X, pattern, flags. Two entries draw the overlapping
        ; colour planes; Y=216 terminates the hardware sprite list.
        db      0,0,0,0               ; grey/white ball plane
        db      0,0,4,0               ; black/white CC plane
        db      216,0,0,0             ; end marker

SpritePatterns:
        ; 8 directions * 2 overlapping 16x16 planes. Each plane contains a left
        ; and right 8-pixel pattern, hence 32 pattern bytes per plane/frame.
        incbin  "gfx/ball_frames.spr"

SpriteColors:
        ; Colour 41h enables colour-combine (CC). Where the black plane overlaps
        ; grey colour 14, the V9938 OR trick produces white as a third colour.
        ds      16,14                 ; first plane: grey
        ds      16,041h               ; second: black + CC; 14 OR 1 = white

; V9938 palette bytes: RRR0BBBB, 00000GGG.
Screen5Palette:
        db      000h,0                ; 0 transparent
        db      000h,0                ; 1 black
        db      010h,7                ; 2 asset green
        db      006h,6                ; 3 asset cyan
        db      014h,0                ; 4 asset dark blue
        db      007h,1                ; 5 asset blue
        db      060h,1                ; 6 asset red
        db      063h,4                ; 7 tileset beige
        db      071h,4                ; 8 asset orange
        db      062h,0                ; 9 asset pink
        db      070h,7                ; 10 yellow
        db      074h,6                ; 11 pale yellow
        db      022h,2                ; 12 tileset dark grey
        db      052h,1                ; 13 dark red
        db      055h,5                ; 14 light grey
        db      077h,7                ; 15 white

; The build stores normal-XOR-hit deltas in hidden VRAM scanlines 212..227.
; Only SX, DX and DY are changed for each flash.
ObjectAnimationCommandTemplate:
        dw      0                    ; SX
        dw      212                  ; SY
        dw      0                    ; DX
        dw      0                    ; DY
        dw      16                   ; NX
        dw      16                   ; NY
        db      0,0,093h             ; colour, ARG, LMMM with XOR operation

; Offset of logical frame 0/1/2 inside each instance's three-frame block.
FlipperFrameOffsets:
        dw      0,391,782

; Count byte plus eight-byte map instance records: side, control, pivot X/Y,
; packed VRAM destination and CPU graphics offset.
FlipperInstances:
        incbin  "gfx/flipper_instances.bin"

; Three pivot-aligned 34x23 SCREEN 5 frames per map instance.
FlipperFrameData:
        incbin  "gfx/flipper_frames.cor"

; Six pivot-relative polygon normal fields generated from maps/flippers.tmx.
; A twelve-byte offset header selects left0..2 followed by right0..2.
FlipperCollisionData:
        incbin  "gfx/flipper_collisions.bin"

; Static tile shapes plus Tiled PinballObjects. Object records also preserve
; kick and score metadata for gameplay extensions.
CollisionMap:
        ; Exactly 32*24 bytes, one collision_shape value per background tile.
        incbin  "gfx/collision_map.bin"
CircleObjects:
        ; Count byte followed by fixed eight-byte ellipse/circle records.
        incbin  "gfx/collision_circles.bin"

; Pletter-compressed SCREEN 5 banks generated from the tileset and TMX map.
PlayfieldBank0:
        ; Decompresses to physical VRAM 0000h-3FFFh.
        incbin  "gfx/playfield_assets_0.plet5"
PlayfieldBank1:
        ; Decompresses to physical VRAM 4000h-7FFFh, including hidden atlas rows.
        incbin  "gfx/playfield_assets_1.plet5"

; The packed stream stays below 8000h; UploadPolygonObjects expands its count
; byte and variable-size lookup records to page-2 RAM at startup.
PackedPolygonObjects:
        incbin  "gfx/collision_polygons.plet5"

        ; A 32 KiB plain ROM is mapped unambiguously at 4000h-BFFFh by MSX
        ; emulators and real cartridge hardware.
        ds      0c000h-$,0ffh
