; Dune Gen4 Demo (1990): the four 520 "Soundtracker" (Quartet) tunes as an SNDH.
; The replay is SINGSONG.PRG's own TEXT, byte for byte, plus its voice set and the
; four songs exactly as DUNE.PRG holds them. mk_sndh.py writes the incbin files.
;
; SingSong's API (Audio Visual Research's EXAMPLE2.S): TEXT+12 = song, +16 = voice
; set, jsr 4 = start (installs Timer A at the song's rate, Timer C = sequencer at
; TOS's 200 Hz), jsr 8 = stop. Its Timer A handler keeps the four voices in
; d0-d3/a0-a3 and a4 = $FFFF8800 ACROSS interrupts: the foreground must not touch
; them. The SNDH engine calls PLAY with d0 = 0, so every exit that can be followed
; by an engine call saves d0, and PLAY puts it back.

	bra.w	init
	bra.w	exit
	bra.w	play
	dc.b	'SNDH'
	dc.b	'TITLDune Gen4 Demo - Soundtracker',0
	dc.b	'COMM520',0
	dc.b	'RIPPripped from the Dune Gen4 Demo disk (DUNEGEN4.MSA)',0
	dc.b	'CONVAVR SingSong (Quartet) + SOUND2.SET, glue by ZigMachine',0
	dc.b	'YEAR1990',0
	dc.b	'##04',0
	dc.b	'TC200',0
	dc.b	'FLAG~acy',0
	even
	dc.b	'HDNS'

; d0 = subtune 1..4 = the songs in DUNE.PRG's order ($1DF2, $24F2, $2A1E, $3316).
init:	lea	ss(pc),a6
	lea	relocd(pc),a5
	tst.b	(a5)
	bne.s	.reloc_done
	st	(a5)
	bsr	reloc
.reloc_done:
	move.l	d0,d7
	bsr	halt			; INIT again on a running image: stop first
	bsr	worksong		; a5 = the song, copied into the work buffer
	lea	ss(pc),a6
	move.l	a5,12(a6)
	lea	vset(pc),a5
	move.l	a5,16(a6)
	jsr	4(a6)			; start: d0-d5/a0-a4 belong to Timer A from here
	lea	ta_orig(pc),a5
	move.l	$134.w,(a5)
	lea	ta_wrap(pc),a5
	move.l	a5,$134.w
	lea	playing(pc),a5
	st	(a5)
	lea	saved_d0(pc),a5
	move.l	d0,(a5)
	rts

exit:	bsr	halt
	rts

; Stop SingSong if it plays. Its stop saves the Timer A vector (our wrapper) as
; the one the next start installs: put the replay's own handler back there.
halt:	lea	playing(pc),a5
	tst.b	(a5)
	beq.s	.idle
	sf	(a5)
	lea	ss(pc),a6
	jsr	8(a6)
	lea	ss+$518(pc),a5
	move.l	ta_orig(pc),(a5)
	move.b	#8,$ffff8800.w
	move.b	#0,$ffff8802.w
	move.b	#9,$ffff8800.w
	move.b	#0,$ffff8802.w
	move.b	#10,$ffff8800.w
	move.b	#0,$ffff8802.w
.idle:	rts

; d7 = subtune. SingSong rewrites a song in place (loops unrolled, voice names
; turned into addresses), so it plays a fresh copy in a Malloc'd buffer.
worksong:
	lea	work(pc),a5
	tst.l	(a5)
	bne.s	.have
	move.l	#WORK,-(sp)
	move.w	#$48,-(sp)
	trap	#1
	addq.l	#6,sp
	lea	work(pc),a5
	move.l	d0,(a5)
.have:	subq.w	#1,d7
	and.w	#3,d7
	add.w	d7,d7
	add.w	d7,d7
	lea	songtab(pc),a4
	lea	songs(pc),a3
	add.w	(a4,d7.w),a3		; from
	move.w	2(a4,d7.w),d6		; length
	move.l	work(pc),a5
	move.l	a5,a2
	lsr.w	#1,d6
	subq.w	#1,d6
.copy:	move.w	(a3)+,(a2)+
	dbra	d6,.copy
	move.w	#WORK,d6		; the rest zeroed: room to unroll
	sub.w	2(a4,d7.w),d6
	lsr.w	#1,d6
	subq.w	#1,d6
.zero:	clr.w	(a2)+
	dbra	d6,.zero
	rts

; Apply SINGSONG.PRG's GEMDOS fixups: each word is a TEXT offset of a long.
reloc:	lea	fixups(pc),a5
	move.l	a6,d6
.next:	move.w	(a5)+,d7
	bmi.s	.done
	add.l	d6,(a6,d7.w)
	bra.s	.next
.done:	rts

play:	move.l	saved_d0(pc),d0
	pea	.back(pc)
	move.w	sr,-(sp)
	move.l	$114.w,-(sp)		; SingSong's Timer C handler, as an interrupt
	rts
.back:	move.l	a5,-(sp)
	lea	saved_d0(pc),a5
	move.l	d0,(a5)
	move.l	(sp)+,a5
	rts

ta_wrap:
	pea	.post(pc)
	move.w	sr,-(sp)
	move.l	ta_orig(pc),-(sp)
	rts
.post:	move.l	a5,-(sp)
	lea	saved_d0(pc),a5
	move.l	d0,(a5)
	move.l	(sp)+,a5
	rte

saved_d0:	dc.l	0
ta_orig:	dc.l	0
work:		dc.l	0
relocd:		dc.b	0
playing:	dc.b	0
	even
	include	"songtab.i"
fixups:	incbin	"fixups.bin"
	dc.w	-1
	even
ss:	incbin	"singsong.bin"
	even
songs:	incbin	"songs.bin"
	even
vset:	incbin	"vset.bin"
