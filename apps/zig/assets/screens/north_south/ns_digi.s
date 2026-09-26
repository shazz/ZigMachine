; ---------------------------------------------------------------------------
; NORTH & SOUTH (Infogrames 1989): the battle's digitised sounds, as an SNDH
; (docs/music/north_south_digi.sndh).
;
; The battle has no music. Every sound is a sample from the bank carte.ech
; played through the three YM volume registers by a Timer A interrupt, one
; level byte per tick, each level turned into registers 8/9/10 by a 256-entry
; table (ns.app flat $41D4). A VBL routine chains the samples of a SEQUENCE:
; (sample, Timer A data) pairs, $FF-terminated, the next one starting at the
; first VBL after the previous has ended.
;
; A ZigMachine cart cannot write the YM itself, so the battle REQUESTS a
; subtune of this image whenever the game calls play_seq: SUBTUNE n+1 PLAYS
; SEQUENCE n. Loading the image cuts whatever was playing and init arms
; sequence n; its first sample starts on the next play call (the next VBL),
; as play_seq ($4BD6) followed by the VBL sequencer did. There is one voice
; and no priority: the last request wins, exactly as in the game.
;
; The routines below are ns.app's own, transcribed instruction for
; instruction (flat addresses in the comments; RAM = flat + $D0A8):
;   $40FE   YM setup: registers 0-6 and 8-10 to 0, mixer (old & $C0) | $3F
;   $49D4   the VBL sequencer (called here as the SNDH play routine, TC50)
;   $40B4   start a sample: Timer A stop, pointer, TADR, vector $134, TACR = 1
;   $417E   the Timer A interrupt: a level byte -> movep.l/movep.w into the
;           PSG through the $FF8800 mirrors; byte 0 stops the timer
; The pointer the interrupt reads is patched into its own movea.l, as the
; original does at $4186.
;
; Data: ns_battle_digi.bin (the rip's export of carte.ech: 47 sequences, 41
; samples) and voltab.bin (ns.app $41D4..$49D3, 256 x 8 bytes
; "8, v8, 9, v9, 10, v10, 0, 0"), both built by
; tools/private_tools/north_south_assets.py.
;
; Build: vasmm68k_mot -Fbin -nosym -o docs/music/north_south_digi.sndh \
;            apps/zig/assets/screens/north_south/ns_digi.s
; ---------------------------------------------------------------------------
NSEQ	equ	47
NSMP	equ	41

	bra.w	init
	bra.w	exit
	bra.w	play
	dc.b	"SNDH"
	dc.b	"TITLNorth & South: battle sounds",0
	dc.b	"COMMInfogrames",0
	dc.b	"RIPPcarte.ech + ns.app $40B4-$49D4",0
	dc.b	"CONVZigMachine port (subtune n+1 = sequence n)",0
	dc.b	"YEAR1989",0
	dc.b	"##47",0
	dc.b	"TC50",0
	dc.b	"HDNS"
	even

; d0 = subtune (1..47): arm sequence d0-1, as play_seq(n, $81) does.
init:
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	d0,d7
	bsr	build_tables
	bsr	ym_setup			; $40FE, from the bank install $402E
	clr.b	$fffffa19.w			; Timer A stopped
	bset	#5,$fffffa07.w			; IERA: Timer A enabled
	bset	#5,$fffffa13.w			; IMRA: unmasked
	lea	playing(pc),a0
	sf	(a0)
	subq.w	#1,d7
	bmi.s	.none
	cmp.w	#NSEQ,d7			; $4C2E: cmp.w nseq / bge
	bge.s	.none
	lea	seq_tab(pc),a0			; $4C50: index 0, sequence n, no loop, active
	lsl.w	#2,d7
	lea	seq_ptr(pc),a1
	move.l	0(a0,d7.w),(a1)
	lea	seq_index(pc),a0
	clr.w	(a0)
	lea	seq_loop(pc),a0
	sf	(a0)
	lea	seq_active(pc),a0
	move.b	#1,(a0)
.none:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

exit:
	clr.b	$fffffa19.w
	bsr	ym_setup
	rts

; $49D4, the VBL sequencer.
play:
	movem.l	d0-d2/a0-a1,-(sp)
	move.b	seq_active(pc),d0
	beq.s	.out
	move.b	playing(pc),d0
	bne.s	.out
	move.w	sr,-(sp)
	move.w	#$2700,sr
	movea.l	seq_ptr(pc),a0
	move.w	seq_index(pc),d0
	add.w	d0,d0
	clr.w	d1
	clr.w	d2
	move.b	0(a0,d0.w),d1
	move.b	1(a0,d0.w),d2
	cmp.w	#$ff,d1
	bne.s	.go
	lea	seq_loop(pc),a1
	tst.b	(a1)
	beq.s	.over
	lea	seq_index(pc),a1
	clr.w	(a1)
	move.b	0(a0),d1
	move.b	1(a0),d2
.go:
	lea	seq_index(pc),a1
	addq.w	#1,(a1)
	lea	cur_smp(pc),a1
	move.w	d1,(a1)
	lea	cur_rate(pc),a1
	move.w	d2,(a1)
	bsr	start_sample
	move.w	(sp)+,sr
.out:
	movem.l	(sp)+,d0-d2/a0-a1
	rts
.over:
	lea	seq_active(pc),a1
	sf	(a1)
	move.w	(sp)+,sr
	bra.s	.out

; $40B4: start sample cur_smp at Timer A data cur_rate.
start_sample:
	lea	smp_tab(pc),a0
	move.w	cur_smp(pc),d0
	add.w	d0,d0
	add.w	d0,d0
	move.w	d0,d1
	add.w	d0,d0
	add.w	d1,d0				; x 12: [start, end, length]
	lea	irq_addr(pc),a1
	move.l	0(a0,d0.w),(a1)			; patched into the interrupt's movea.l
	move.b	#0,$fffffa19.w
	move.w	cur_rate(pc),d0
	move.b	d0,$fffffa1f.w
	lea	timer_a(pc),a1
	move.l	a1,$134.w
	move.b	#1,$fffffa19.w			; delay mode, prescaler /4
	lea	playing(pc),a1
	st	(a1)
	bclr	#5,$fffffa0f.w
	rts

; $40FE
ym_setup:
	move.l	a0,-(sp)
	lea	$ffff8800.w,a0
	moveq	#0,d1
.zero:
	move.b	d1,(a0)
	move.b	#0,2(a0)
	addq.b	#1,d1
	cmp.b	#7,d1
	bne.s	.zero
	move.b	#7,(a0)
	move.b	(a0),d1
	and.b	#$c0,d1
	or.b	#$3f,d1
	move.b	d1,2(a0)
	move.b	#8,(a0)
	move.b	#0,2(a0)
	move.b	#9,(a0)
	move.b	#0,2(a0)
	move.b	#10,(a0)
	move.b	#0,2(a0)
	move.l	(sp)+,a0
	rts

; $417E, the Timer A interrupt.
timer_a:
	move.w	d0,-(sp)
	move.l	d1,-(sp)
	move.l	a0,-(sp)
	move.l	a1,-(sp)
	dc.w	$207c				; movea.l #irq_addr,a0 ($4184)
irq_addr:
	dc.l	0				; the sample pointer lives here ($4186)
	clr.w	d0
	move.b	(a0)+,d0
	beq.s	.stop
	lea	irq_addr(pc),a1
	move.l	a0,(a1)
	lea	$ffff8800.w,a0
	lsl.w	#3,d0
	move.l	voltab(pc,d0.w),d1		; 8, v8, 9, v9
	move.w	voltab+4(pc,d0.w),d0		; 10, v10
	movep.l	d1,0(a0)
	movep.w	d0,0(a0)
	bclr	#5,$720f(a0)			; $FFFFFA0F: in-service bit (software EOI)
	movea.l	(sp)+,a1
	movea.l	(sp)+,a0
	move.l	(sp)+,d1
	move.w	(sp)+,d0
	rte
.stop:
	move.b	#0,$fffffa19.w
	lea	playing(pc),a1
	sf	(a1)
	bclr	#5,$fffffa0f.w
	movea.l	(sp)+,a1
	movea.l	(sp)+,a0
	move.l	(sp)+,d1
	move.w	(sp)+,d0
	rte

; ns.app $41D4: level -> "8, v8, 9, v9, 10, v10, 0, 0". It sits right after
; the interrupt, as in the original, so the (pc,d0.w) reach holds.
voltab:
	incbin	"voltab.bin"

; The bank loader's tables ($1C432 sequence pointers, $1C52A sample records),
; built once from the bank's offset table.
build_tables:
	lea	bank(pc),a0
	lea	12(a0),a1			; u32 seq_off[NSEQ]
	lea	seq_tab(pc),a2
	moveq	#NSEQ-1,d0
.seq:
	move.l	(a1)+,d1
	add.l	a0,d1
	move.l	d1,(a2)+
	dbf	d0,.seq
	lea	12+4*NSEQ(a0),a1		; u32 smp_off[NSMP]
	lea	12+4*NSEQ+4*NSMP(a0),a3		; u32 smp_len[NSMP]
	lea	smp_tab(pc),a2
	moveq	#NSMP-1,d0
.smp:
	move.l	(a1)+,d1
	add.l	a0,d1
	move.l	(a3)+,d2
	move.l	d1,(a2)+			; start
	add.l	d2,d1
	move.l	d1,(a2)+			; end
	move.l	d2,(a2)+			; length
	dbf	d0,.smp
	rts

	even
seq_active:	dc.b	0			; $1CED2
seq_loop:	dc.b	0			; $1C427
playing:	dc.b	0			; $1C426
	even
seq_index:	dc.w	0			; $1C428
cur_smp:	dc.w	0			; $1C42A
cur_rate:	dc.w	0			; $1C42C
seq_ptr:	dc.l	0			; $1C526
seq_tab:	ds.l	NSEQ			; $1C432
smp_tab:	ds.l	3*NSMP			; $1C52A
	even
bank:
	incbin	"ns_battle_digi.bin"
