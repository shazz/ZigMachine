; ---------------------------------------------------------------------------
; SKYSTRIKE (Shadow Software 1990): the game's whole sound, as an SNDH
; (docs/music/skystrike.sndh). Everything the STOS program asks the YM for:
;
;   MUSIC n / MUSIC OFF   the three tunes of bank 3 (SKYMUSIC.MBK), played by
;                STOS's own music library: Grazey's rip Sky_Strike.sndh (the
;                archive's, Fothergill_Aaron/), which holds that library and
;                the bank, is included whole and called through its entries.
;                MUSIC OFF is STOS's ($3E012 in the game's RAM): registers 13
;                down to 0 zeroed, the mixer $38 | (old & $C0).
;   SAMPLAY n / SAMSTOP / SAMLOOP ON|OFF   the Maestro extension's digi player
;                (MAESTRO.EXD $48E-$9DE, transcribed): Timer A at the sample's
;                own speed (SAMSPEED AUTO: the "JON" header's byte 3 -> the
;                speed table + $13, TACR /4), each byte a line of the volume
;                table into registers 8, 9, 10. Bank 10 = SAMPLES.MBK (the
;                gun burst, the crash).
;   VOLUME v / NOISE p / ENVEL s,p   the engine, STOS's PSG commands
;                ($2EE12 / $2EE3E / $2EDEE): all three volumes; noise period
;                p with tones 0-5 zeroed, mixer $C0 and the envelope shape
;                rewritten; envelope period 11/12 and shape 13.
;   SOUND INIT   Maestro's Dosound table (regs 0-6 = 0, 7 = $FF, 8-11 = 0),
;                on the image's first INIT, as the game's first line does.
;
; Requests: SUBTUNE 1-3 = MUSIC n, SUBTUNE 4 = silence (a load for the other
; commands). A zg.sndhCall's d0 = $8000 + op << 8 + arg, on the RUNNING image:
;   op 0 MUSIC arg (0 = off)   1 SAMPLAY arg   2 SAMSTOP   3 SAMLOOP arg
;   op 4 VOLUME arg   5 NOISE arg   6 ENVEL shape arg (period from 7 and 8)
;   op 7 envelope period high byte   8 envelope period low byte
;   op 9 ZPLAY arg   10 ZSTOP arg: ZIG mode's samples on the STE DMA chip
;        (sound_zig.s)
; so an effect never reloads the image and what is sounding goes on.
;
; Build (from the repository root; vasm 1.9, /home/matt/projects/MJJ/bin/vasm):
;   vasmm68k_mot -Fbin -nosym -o docs/music/skystrike.sndh \
;       apps/zig/assets/screens/skystrike/sound.s
; The .bin/.bnk files come from tools/skystrike/extract_assets.py.
; ---------------------------------------------------------------------------
RESIDENT_BIT	equ	15

	bra.w	init
	bra.w	exit
	bra.w	play
	dc.b	"SNDH"
	dc.b	"TITLSky Strike: music, engine, samples",0
	dc.b	"COMMAaron Fothergill",0
	dc.b	"RIPPmusic: Grazey; STOS engine + Maestro samples: the game",0
	dc.b	"CONVZigMachine port (sub 1-3 music, 4 silence, calls $8000+op<<8+arg)",0
	dc.b	"YEAR1990",0
	dc.b	"##04",0
	dc.b	"TC50",0
	dc.b	"HDNS"
	even

init:
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	d0,d7
	lea	installed(pc),a0
	tst.b	(a0)
	bne.s	.inst
	st	(a0)
	bsr	sound_init
.inst:
	btst	#RESIDENT_BIT,d7
	bne.s	.call
	cmp.w	#4,d7
	bcc.s	.out
	move.w	d7,d0
	bsr	music
	bra.s	.out
.call:
	bsr	command
.out:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

exit:
	bsr	samstop
	moveq	#0,d0
	bsr	zstop
	bsr	music_off
	rts

play:
	movem.l	d0-d7/a0-a6,-(sp)
	move.b	music_on(pc),d0
	beq.s	.none
	jsr	grazey+8(pc)
.none:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; d7 = $8000 + op << 8 + arg
command:
	moveq	#0,d0
	move.b	d7,d0
	move.w	d7,d1
	lsr.w	#8,d1
	and.w	#$7f,d1
	cmp.w	#10,d1
	bhi.s	.bad
	add.w	d1,d1
	move.w	.tab(pc,d1.w),d1
	jmp	.tab(pc,d1.w)
.bad:	rts
.tab:	dc.w	music-.tab, samplay-.tab, samstop-.tab, samloop-.tab
	dc.w	volume-.tab, noise-.tab, envel-.tab, env_hi-.tab, env_lo-.tab
	dc.w	zplay-.tab, zstop-.tab

; ---- STOS music: the rip's init plays tune d0; its play is our play -------
music:
	tst.w	d0
	beq	music_off
	lea	music_on(pc),a0
	st	(a0)
	jsr	grazey(pc)
	rts

; $3E012: music off -- the library's shadow cleared, registers 13..0 written
music_off:
	lea	music_on(pc),a0
	sf	(a0)
	lea	$ffff8800.w,a3
	moveq	#13,d2
.reg:	cmp.w	#7,d2
	bne.s	.plain
	move.b	#7,(a3)
	move.b	(a3),d0
	and.b	#$c0,d0
	or.b	#$38,d0
	move.b	d0,2(a3)
	bra.s	.next
.plain:	move.b	d2,(a3)
	move.b	#0,2(a3)
.next:	dbf	d2,.reg
	rts

; ---- the STOS PSG commands ------------------------------------------------
; d0 = register, d1 = value (Giaccess write)
psg_w:
	move.b	d0,$ffff8800.w
	move.b	d1,$ffff8802.w
	rts

; $2EE12: VOLUME v -> registers 8, 9, 10
volume:
	move.b	d0,d1
	moveq	#8,d0
	bsr	psg_w
	moveq	#9,d0
	bsr	psg_w
	moveq	#10,d0
	bra	psg_w

; $2EE3E: NOISE p -> 6 = p & 31, 0-5 = 0, 7 = $C0, then 13 rewritten
noise:
	and.b	#31,d0
	move.b	d0,d1
	moveq	#6,d0
	bsr	psg_w
	moveq	#5,d2
.tone:	move.w	d2,d0
	moveq	#0,d1
	bsr	psg_w
	dbf	d2,.tone
	moveq	#7,d0
	move.b	#$c0,d1
	bsr	psg_w
	move.b	#13,$ffff8800.w
	move.b	$ffff8800.w,d1
	moveq	#13,d0
	bra	psg_w

env_hi:
	lea	env_period(pc),a0
	move.b	d0,(a0)
	rts
env_lo:
	lea	env_period+1(pc),a0
	move.b	d0,(a0)
	rts

; $2EDEE: ENVEL shape, period -> 11 = period low, 12 = high, 13 = shape & 15
envel:
	move.w	d0,d2
	move.b	env_period+1(pc),d1
	moveq	#11,d0
	bsr	psg_w
	move.b	env_period(pc),d1
	moveq	#12,d0
	bsr	psg_w
	move.b	d2,d1
	and.b	#15,d1
	moveq	#13,d0
	bra	psg_w

; Maestro's SOUND INIT: Dosound(regs 0-6 = 0, 7 = $FF, 8-11 = 0)
sound_init:
	moveq	#0,d2
.lo:	move.w	d2,d0
	moveq	#0,d1
	bsr	psg_w
	addq.w	#1,d2
	cmp.w	#7,d2
	bne.s	.lo
	moveq	#7,d0
	move.b	#$ff,d1
	bsr	psg_w
	moveq	#8,d2
.hi:	move.w	d2,d0
	moveq	#0,d1
	bsr	psg_w
	addq.w	#1,d2
	cmp.w	#12,d2
	bne.s	.hi
	rts

; ---- Maestro ---------------------------------------------------------------
; $48E: SAMPLAY n (SAMSPEED AUTO)
samplay:
	lea	samples(pc),a1
	movea.l	a1,a0
	and.l	#$ff,d0
	lsl.w	#3,d0
	adda.l	d0,a1
	adda.l	(a1),a0				; the sample's start
	movea.l	4(a1),a1			; its length
	suba.l	#$14,a1
	addq.l	#8,a0				; past the name: "JON", speed, data
	move.w	sr,d7
	move.w	#$2700,sr
	lea	smp_ptr(pc),a2
	move.l	a0,(a2)+			; $DBC
	move.l	a1,(a2)+			; $DC0
	move.l	a0,(a2)+			; $DC4
	move.l	a1,(a2)+			; $DC8
	clr.b	$fffffa19.w
	move.b	#1,$fffffa19.w
	moveq	#0,d3
	move.b	3(a0),d3			; "JON" + the speed byte
	lea	speeds(pc),a2
	move.b	0(a2,d3.w),d3
	add.b	#$13,d3
	move.b	d3,$fffffa1f.w
	or.b	#$20,$fffffa13.w
	or.b	#$20,$fffffa07.w
	bclr	#3,$fffffa17.w			; automatic end of interrupt
	lea	isr_once(pc),a2
	move.w	smp_mode(pc),d0
	cmp.w	#3,d0
	bne.s	.set
	lea	isr_loop(pc),a2
.set:	move.l	a2,$134.w
	move.w	d7,sr
	rts

; $988: SAMSTOP. Maestro only disables and masks Timer A (IERA / IMRA);
; the timer is also STOPPED here (TACR = 0), which on an ST changes nothing
; heard. It was added because the sealed player's MFP once ran a timer on its
; control register alone and the digi never stopped; the player now honours
; IERA/IMRA as the chip does (libs/zig/players/mfp.zig), so the IERA/IMRA
; clears alone would do. The TACR write is kept: harmless, and belt and braces.
samstop:
	move.w	sr,d7
	move.w	#$2700,sr
	clr.b	$fffffa19.w
	bclr	#5,$fffffa07.w
	bclr	#5,$fffffa0b.w
	bclr	#5,$fffffa0f.w
	bclr	#5,$fffffa13.w
	move.w	d7,sr
	rts

; $9BA / $9DE: SAMLOOP OFF (3 -> 1) / ON (1 -> 3), the mode word $DCC
samloop:
	lea	smp_mode(pc),a0
	tst.b	d0
	bne.s	.on
	cmp.w	#2,(a0)
	ble.s	.done
	subq.w	#2,(a0)
.done:	rts
.on:	cmp.w	#3,(a0)
	bge.s	.done
	addq.w	#2,(a0)
	rts

; $710: mode 1, forward once. The count runs out -> Timer A off.
isr_once:
	movem.l	d7/a3,-(sp)
	movea.l	smp_ptr(pc),a3
	move.b	(a3),d7
	lea	smp_left(pc),a3
	subq.l	#1,(a3)
	beq.s	.end
	lea	smp_ptr(pc),a3
	addq.l	#1,(a3)
	bra.s	out_level
.end:	lea	smp_ptr(pc),a3
	addq.l	#1,(a3)
	clr.b	$fffffa19.w			; stopped too (see SAMSTOP)
	bclr	#5,$fffffa07.w
	movem.l	(sp)+,d7/a3
	rte

; $79A: mode 3, forward looping: past the end, back to the start.
isr_loop:
	movem.l	d7/a3,-(sp)
	movea.l	smp_ptr(pc),a3
	move.b	(a3),d7
	lea	smp_left(pc),a3
	subq.l	#1,(a3)
	bmi.s	.wrap
	lea	smp_ptr(pc),a3
	addq.l	#1,(a3)
	bra.s	out_level
.wrap:	lea	smp_ptr(pc),a3
	move.l	smp_start(pc),(a3)
	lea	smp_left(pc),a3
	move.l	smp_len(pc),(a3)
	; falls into out_level

; d7 = the sample byte: its volume-table line into registers 8, 9, 10
out_level:
	and.w	#$ff,d7
	lea	voltab(pc),a3
	lsl.w	#4,d7
	move.l	0(a3,d7.w),$ffff8800.w
	move.l	4(a3,d7.w),$ffff8800.w
	move.l	8(a3,d7.w),$ffff8800.w
	movem.l	(sp)+,d7/a3
	rte

	even
smp_ptr:	dc.l	0			; $DBC
smp_left:	dc.l	0			; $DC0
smp_start:	dc.l	0			; $DC4
smp_len:	dc.l	0			; $DC8
smp_mode:	dc.w	1			; $DCC
env_period:	dc.w	0
installed:	dc.b	0
music_on:	dc.b	0
	even
voltab:		incbin	"maestro.bin"		; $DEA: 256 x 16 bytes, then
speeds		equ	voltab+4096		; $1DEA: the speed table
	even
samples:	incbin	"samples.bnk"		; bank 10, "MAESTRO!"
	even
grazey:		incbin	"sky_strike_grazey.sndh"
	even
	include	"sound_zig.s"
