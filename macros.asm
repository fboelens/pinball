;define MSX2				; Used in speed equalization
;define SFXPLAY_ENABLED	; Enable the SFX functionality.
;define PERIOD_A445		; Modern 
;define INTERNAL_SCC		; For internal no slot select is needed.;#include 	"tt/ttreplaySCC_options.asm"

; system calls for paging
RDSLT: equ 000Ch
WRSLT: equ 0014h
SFX_WAVEBASE: equ 0
ENASLT:	equ	0024h
INIT32:	equ	006Fh
CHPUT:	equ	00A2h	; Address of character output routine of main Rom BIOS
RSLREG:	equ	0138h
LDIRVM: equ $5C
LINL32:	equ	0F3AFh
ADDR_CLIKSW:    equ $f3db
VDP:            equ 0F3DFh
CHGMOD:		    equ $005F
CHGCLR:         equ $0062

EXPTBL: equ $FCC1
SLTTBL	equ	0FCC5h	; Slot Table
KBUF:	equ	0F41Fh	; Temporary data
RAMAD0:	equ	0F341h	; Main-RAM Slot (00000h~03FFFh)
RAMAD1:	equ	0F342h	; Main-RAM Slot (04000h~07FFFh)
RAMAD2:	equ	0F343h	; Main-RAM Slot (08000h~0BFFFh)
RAMAD3:	equ	0F344h	; Main-RAM Slot (0C000h~0FFFFh)
RAMSLT:	equ	KBUF+3

RAM_8K:         equ 02000h;
RAM_16K:        equ 04000h;
RAM_24K:        equ 06000h;
RAM_32K:        equ 08000h;
RAM_64K:        equ 0FFFFh;

; ROM Page switching
ROM_SelectPage2a: equ 04000h ; 4000 - 5fff (page 2)
ROM_SelectPage2b: equ 06000h ; 6000 - 7fff (page 2)
ROM_SelectPage3a: equ 08000h ; 8000 - 9fff (page 3)
ROM_SelectPage3b: equ 0A000h ; a000 - bfff (page 3)

; without SCC
;ROM_Switch1: equ $4000
;ROM_Switch2: equ $6000  
;ROM_Switch3: equ $8000  
;ROM_Switch4: equ $A000  

; with SCC
ROM_Switch1: equ $5000
ROM_Switch2: equ $7000  
ROM_Switch3: equ $9000  
ROM_Switch4: equ $B000  

worldData: 		equ $0100	; $100-$3000 
worldSprites: 	equ $2000 ; $2000-$4000
worldMusic:		equ $a000

left:           equ 00000010b
right:          equ 00000100b
down:           equ 00000001b
up:             equ 00001000b

sfx_whip: equ 00ffh
sfx_heart: equ 0200h
sfx_hit: equ 06ffh
sfx_boomerang: equ 070Ah
sfx_enemyhit: equ 080Ah
sfx_getobject: equ 0900h

true:           equ 1
false:          equ 0

interruptLine: equ 189
scrollBuildLine: equ 208

ball_stop: equ 1
ball_start: equ 2
ball_toFall: equ 4
ball_normal: equ 5
ball_roll: equ 6


accellerate1: equ 50
accellerate2: equ 100
accellerate3: equ 150

forclr      equ $f3e9
bakclr      equ $feea
bdrclr      equ $f3eb

// MSX 1 
RG0SAV  equ 0xF3DF  
RG1SAV  equ 0xF3E0  
RG2SAV  equ 0xF3E1
RG3SAV  equ 0xF3E2
RG4SAV  equ 0xF3E3
RG5SAV  equ 0xF3E4
RG6SAV  equ 0xF3E5
RG7SAV  equ 0xF3E6
// MSX 2
RG8SAV  equ 0xFFE7 
RG9SAV  equ 0xFFE8 
RG10SAV equ 0xFFE9 
RG11SAV equ 0xFFEA 
RG12SAV equ 0xFFEB 
RG13SAV equ 0xFFEC 
RG14SAV equ 0xFFED 
RG15SAV equ 0xFFEE 
RG16SAV equ 0xFFEF 
RG17SAV equ 0xFFF0 
RG18SAV equ 0xFFF1 
RG19SAV equ 0xFFF2 
RG20SAV equ 0xFFF3 
RG21SAV equ 0xFFF4 
RG22SAV equ 0xFFF5 
RG23SAV equ 0xFFF7 

RDVDP:  EQU     0006H
WRVDP:  EQU     0007H
; ----------------------------
; pre-set main slot for page 3
; and set sub-slot for page 3
; ----------------------------
	macro	mainslot_setup n
	and		3
[2]	rrca
	and		0xC0
	ld		c,a
	ld		a,d
	and		0x3F
	or		c
	ld		c,a					; Primary slot value with main slot in page 3

	ld		a,b
	and		0x0C
[2]	rrca
	and		3
	ld		b,a					; B = Expanded slot in page 3
	ld		a,c
	out		(0A8h),a			; Slot : Main Slot, xx, xx, Main slot
	ld		a,(0FFFFh)
	cpl
	if (n<=4)
[n]	RLCA
	else
[8-n] RRCA	
	endif
	and		0xFC
	or		b
	if (n<=4)
[n]	RRCA
	else
[8-n] RLCA
	endif
	ld		(0FFFFh),a		; Expanded slot selected
	ld		b,a				; save for later	
	endmacro
