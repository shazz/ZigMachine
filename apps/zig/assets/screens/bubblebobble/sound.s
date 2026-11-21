; ---------------------------------------------------------------------------
; BUBBLE BOBBLE (Firebird 1987): the game's whole sound, as an SNDH
; (docs/music/bubble_bobble_st.sndh) -- the nine tunes and the six YM effects,
; played by the GAME'S OWN DRIVER (Tim & Mike Follin's music, David
; Broadhurst's player).
;
;   $1A7AE-$1AFC9  the driver (snd_driver.bin: BUBBLE.PRG's TEXT $A7AE-$AFC9
;                  relocated to $10000, as the cart loads it): start tune
;                  $1A7AE (tune # in $1AC06), the VBL tick $1A810 (music
;                  $1A81A, effect $1AC5A), start effect $1AC12 (effect # in
;                  $1AC10), the hurry flag $1AC08 (tune 0 at full speed), the
;                  tune table $1AB76 (nine tunes, three voices each)
;   $1EE76-$20175  MUSIC.DAT, where the game loads it, with the two bytes the
;                  game patches after loading ($1EE7A = 13, $1F14E = 31, $370C)
; Grazey's archive rip (Follin_Tim/Bubble_Bobble.sndh, 9 subtunes) is the same
; driver and data; this image keeps the game's addresses so that the effects,
; which the rip lacks, start exactly as the game starts them.
;
; The cart (bubblebobble/sound.zig) hears every call the game's code makes to
; the driver (st/cpu.zig hook) and makes the same call here:
;   subtune 1-9    load + start tune 0-8 (zg.requestSongTune; the first request)
;   subtune 10     load, silent (an effect before any tune)
;   d0 = RESIDENT + $000 + t   start tune t on the running driver (zg.sndhCall)
;   d0 = RESIDENT + $100 + e   start effect e
;   d0 = RESIDENT + $200 + h   the hurry flag: tune 0 at full speed (Baron)
; The game's own copy of the driver runs in the cart too, silent: the game
; waits on its end-of-jingle flag ($AC0B), so both play the same frames.
;
; Build (from the repository root; vasm 1.9, /home/matt/projects/MJJ/bin/vasm):
;   vasmm68k_mot -Fbin -nosym -o docs/music/bubble_bobble_st.sndh \
;       apps/zig/assets/screens/bubblebobble/sound.s
; snd_driver.bin and music.dat come from tools/bubblebobble/rip_st.py.
; ---------------------------------------------------------------------------
DRIVER		equ	$1A7AE
MUSIC		equ	$1EE76
START_TUNE	equ	$1A7AE
TUNE		equ	$1AC06
HURRY		equ	$1AC08
TICK		equ	$1A810
START_FX	equ	$1AC12
EFFECT		equ	$1AC10
RESIDENT_BIT	equ	15

	bra.w	init
	bra.w	exit
	bra.w	play
	dc.b	"SNDH"
	dc.b	"TITLBubble Bobble: music and effects",0
	dc.b	"COMMTim & Mike Follin",0
	dc.b	"RIPPthe game's TEXT $A7AE-$AFC9 + MUSIC.DAT",0
	dc.b	"CONVZigMachine port (the game's own driver)",0
	dc.b	"YEAR1987",0
	dc.b	"##10",0
	dc.b	"TC50",0
	dc.b	"HDNS"
	even

init:
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	d0,d7
	bclr	#RESIDENT_BIT,d7
	beq.s	.install
	lea	installed(pc),a0
	tst.b	(a0)
	bne.s	.request
	bsr.s	install
.request:
	move.w	d7,d6
	lsr.w	#8,d6				; the op
	and.w	#$FF,d7				; its argument
	cmp.w	#1,d6
	beq.s	.effect
	cmp.w	#2,d6
	beq.s	.hurry
	move.b	d7,TUNE
	jsr	START_TUNE
	bra.s	.done
.effect:
	move.b	d7,EFFECT
	jsr	START_FX
	bra.s	.done
.hurry:
	move.b	d7,HURRY
	bra.s	.done
.install:
	bsr.s	install
	subq.w	#1,d7				; subtune 1-9: tune 0-8; 10: silent
	cmp.w	#9,d7
	bcc.s	.done
	move.b	d7,TUNE
	jsr	START_TUNE
.done:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; The driver and the music where the game keeps them, the game's patches, the YM quiet.
install:
	lea	driver(pc),a0
	lea	DRIVER,a1
	move.w	#(driver_end-driver)/2-1,d0
.c1:	move.w	(a0)+,(a1)+
	dbra	d0,.c1
	lea	music(pc),a0
	lea	MUSIC,a1
	move.w	#(music_end-music)/2-1,d0
.c2:	move.w	(a0)+,(a1)+
	dbra	d0,.c2
	move.b	#13,MUSIC+4			; $370C: move.b #13,$1EE7A
	move.b	#31,MUSIC+$2D8			; $370C: move.b #31,$1F14E
	clr.b	HURRY
	bsr.s	quiet
	lea	installed(pc),a0
	st	(a0)
	rts

quiet:
	lea	$FFFF8800.w,a0
	move.b	#7,(a0)
	move.b	#$3F,2(a0)
	moveq	#8,d0
.q:	move.b	d0,(a0)
	clr.b	2(a0)
	addq.b	#1,d0
	cmp.b	#11,d0
	bne.s	.q
	rts

exit:
	movem.l	d0-d7/a0-a6,-(sp)
	bsr.s	quiet
	movem.l	(sp)+,d0-d7/a0-a6
	rts

play:
	movem.l	d0-d7/a0-a6,-(sp)
	jsr	TICK
	movem.l	(sp)+,d0-d7/a0-a6
	rts

installed:
	dc.b	0
	even
driver:
	incbin	"apps/zig/assets/screens/bubblebobble/snd_driver.bin"
driver_end:
	even
music:
	incbin	"apps/zig/assets/screens/bubblebobble/music.dat"
music_end:
	even
