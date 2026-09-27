; ---------------------------------------------------------------------------
; RICK DANGEROUS (Core Design / Firebird 1989): the game's whole sound, as an
; SNDH (docs/music/rick_dangerous.sndh) -- the music, the YM sound effects and
; the three Timer A digis, played by the GAME'S OWN DRIVER.
;
; The tunes and the effects share one player state (Ben Daglish's player: the
; effects start through its sfx entry $34F0C and run on its voices), and the
; game's play_sound $34750 applies the drop rule: while a tune plays, or a digi
; is busy, every effect and digi request is dropped. So the music cannot be
; one SNDH and the effects another: this image holds the driver entire.
;
;   $34692-$34B97  the game's driver code (snd_driver.bin, from the game's
;                  RAM): sound off $34692, play_sound $34750, the VBL tick
;                  $3488E, the sound table $3498A, the digi rates $34A72 and
;                  state, the Timer A install $34A88 and handler $34AA4
;   $34B98-$36617  Ben Daglish's player, the 9 tunes, the sfx records, the
;                  digi volume table (snd_player.bin = the archive's
;                  Rick_Dangerous.sndh bytes $280-$1D00, Mug UK's rip,
;                  byte-identical to the game's RAM: this EXTENDS that rip
;                  with the game's own front end)
;   $3DA18-$41C57  the gunshot, the explosion and the scream (snd_digis.bin)
;
; The code is absolute (the game runs at fixed addresses), so init copies it
; to the game's own addresses; the SNDH player's 68000 has 1 MB of RAM and
; this image sits at $10002, far below. Then everything is the game's code:
;   init   $34A88 (Timer A vector $134, IERA/IMRA), $34692 (sound off), then
;          play_sound(id, d1) exactly as the game calls it
;   play   $3488E, the tick the game's VBL interrupt $38D7C runs (TC50)
;   exit   $34692
; Timer A is the SNDH player's MFP: the tick programs TACR/TADR and the
; handler writes each sample byte through the $3524E volume table.
;
; A ZigMachine cart cannot poke the running tune, so a request is a SUBTUNE:
;   subtune = 1 + id + 29 x v,   id 0..28 (the sound table $3498A)
;   v = 0 / 1   d1 = 0, with sfx_alt ($34A85) = 0 / 1: the voice the game's
;               alternating effects take
;   v = 2       d1 = 1 (the effect's voice is 2; a tune loops)
; Loading the image restarts the driver, so an effect still sounding on
; ANOTHER voice is cut by the next request (the game would let it finish).
;
; Build (from the repository root; vasm 1.9, /home/matt/projects/MJJ/bin/vasm):
;   vasmm68k_mot -Fbin -nosym -o docs/music/rick_dangerous.sndh \
;       apps/zig/assets/screens/rick_dangerous/sound.s
; The .bin files come from tools/rick_dangerous/extract_assets.py.
; ---------------------------------------------------------------------------
NIDS		equ	29
DRIVER		equ	$34692
DIGIS		equ	$3DA18
SOUND_OFF	equ	$34692
PLAY_SOUND	equ	$34750
TICK		equ	$3488E
TIMERA_INSTALL	equ	$34A88
SFX_ALT		equ	$34A85

	bra.w	init
	bra.w	exit
	bra.w	play
	dc.b	"SNDH"
	dc.b	"TITLRick Dangerous: music, effects, digis",0
	dc.b	"COMMBen Daglish",0
	dc.b	"RIPPthe game's RAM $34692-$36617 + $3DA18-$41C57 (player: Mug UK)",0
	dc.b	"CONVZigMachine port (subtune 1+id+29*v)",0
	dc.b	"YEAR1989",0
	dc.b	"##87",0
	dc.b	"TC50",0
	dc.b	"HDNS"
	even

; d0 = subtune (1..87)
init:
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	d0,d7
	lea	driver(pc),a0			; the driver + the player, contiguous
	lea	DRIVER,a1
	move.w	#(driver_end-driver)/2-1,d0
.c1:	move.w	(a0)+,(a1)+
	dbra	d0,.c1
	lea	digis(pc),a0
	lea	DIGIS,a1
	move.w	#(digis_end-digis)/2-1,d0
.c2:	move.w	(a0)+,(a1)+
	dbra	d0,.c2
	jsr	TIMERA_INSTALL			; the game's own start-up call
	jsr	SOUND_OFF
	subq.w	#1,d7
	bmi.s	.none
	and.l	#$FFFF,d7
	divu.w	#NIDS,d7			; d7 = id << 16 | v
	moveq	#0,d1
	cmp.w	#2,d7
	bne.s	.alt
	moveq	#1,d1				; v = 2: d1 = 1
	bra.s	.go
.alt:	move.b	d7,SFX_ALT			; v = 0 / 1: the alternating voice
.go:	swap	d7
	move.w	d7,d0				; the sound id
	jsr	PLAY_SOUND
.none:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

exit:
	movem.l	d0-d7/a0-a6,-(sp)
	jsr	SOUND_OFF
	movem.l	(sp)+,d0-d7/a0-a6
	rts

play:
	jsr	TICK
	rts

	even
driver:
	incbin	"apps/zig/assets/screens/rick_dangerous/snd_driver.bin"
	incbin	"apps/zig/assets/screens/rick_dangerous/snd_player.bin"
driver_end:
	even
digis:
	incbin	"apps/zig/assets/screens/rick_dangerous/snd_digis.bin"
digis_end:
