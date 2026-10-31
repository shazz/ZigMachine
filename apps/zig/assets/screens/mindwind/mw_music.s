; ---------------------------------------------------------------------------
; MIND REWIND (Reservoir Gods, EIL 2003): Count Zero's STE DMA music, as an SNDH
; (docs/music/mindwind.sndh).
;
; The demo's music is four sample voices summed in software into a 500-byte
; stereo frame (250 pairs, 12517 Hz) each VBL and played by the STE DMA chip.
; Its sequencer, voices, DMA buffers and init are one self-contained block of
; the depacked PRG, $75FE-$8ACC (TEXT-relative), copied here VERBATIM as
; mw_code.bin with its data ($1EDC2-$271C8, mw_data.bin). Only the MIXER is new:
; the original ($51F0-$75FA) is cut into ~100 slices welded into the fullscreen
; kernel's border switches, so it cannot run outside the demo. The loop below
; does the same thing per output byte: (voice a) + (voice b), each voice
; stepping by its pitch's precomputed step table; left = voices 1+3 at even
; bytes, right = voices 2+4 at odd bytes (the original wrote with (a7)+, which
; steps by 2 for a byte, to interleave the channels for free).
;
; The per-frame order is the demo's: VBL $55A runs the tick ($7664), the kernel
; mixes into the buffer at $59C, and the Timer A tail ($70A-$758) saves the
; voices' advanced pointers, swaps the two buffers and starts DMA on the one
; just mixed ($7F9E). PLAY does those three steps in that order.
;
; Subtunes and calls (zg.sndhCall(name, d0) runs INIT on the loaded image):
;   1  the demo's first half: song 1, music on            (main $48, $BAE8)
;   2  the second half alone: samples reversed, song 2    ($80E8 + $2F2)
;   d0 = $8001 (resident) REWIND: music off, the tape-rewind one-shot plays
;              (mono 12517 Hz, $2A4)
;   d0 = $8002 (resident) REVERSE: every sample reversed in place, song 2
;              starts, music on ($80E8 then $2F2)
; The demo's parts wait on the song position (voice 1's event count, $771E);
; the cart keeps those as frame counts instead.
;
; Build: vasmm68k_mot -Fbin -nosym -o docs/music/mindwind.sndh \
;            apps/zig/assets/screens/mindwind/mw_music.s
; ---------------------------------------------------------------------------
M_INIT	equ	$0		; $75FE: microwire, buffers, step tables, voices, song 1
M_TICK	equ	$66		; $7664: sequencer tick, then a1-a4 -> the 4 voice pointers
M_DMA	equ	$9A0		; $7F9E: d1 = buffer: DMA frame start/end, stereo 12517, play
M_REV	equ	$AEA		; $80E8: reverse every sample in place, then song 2 ($88F8)
M_VOICE	equ	$108		; $7706: 4 voices x $28 (+2 step offset, +$12 on, +$24 pointer)
M_VPTR	equ	$1A8		; $77A6: the 4 voices' sample pointers, as the tick leaves them
D_ON	equ	$0		; $1EDC2: music on (word)
NSTEP	equ	250

sndh:	bra.w	init
	bra.w	exit
	bra.w	play
	dc.b	"SNDH"
	dc.b	"TITLMind Rewind",0
	dc.b	"COMMCount Zero",0
	dc.b	"RIPPMINDWIND.TOS $75FE-$8ACC, $1EDC2-$271C8",0
	dc.b	"CONVZigMachine port, mixer unwelded from the fullscreen",0
	dc.b	"YEAR2003",0
	dc.b	"FLAG~e",0
	dc.b	"##02",0
	dc.b	"TC50",0
	dc.b	"HDNS"
	even

init:	movem.l	d0-d7/a0-a6,-(sp)
	move.w	d0,d7
	bmi.s	.resident
	bsr	relocate
	jsr	mcode+M_INIT(pc)
	lea	mdata+D_ON(pc),a0
	move.w	#1,(a0)
	cmp.w	#2,d7
	bne.s	.done
	jsr	mcode+M_REV(pc)
	bra.s	.done
.resident:
	cmp.w	#$8001,d7
	bne.s	.rev
	bsr	rewind
	bra.s	.done
.rev:	cmp.w	#$8002,d7
	bne.s	.done
	jsr	mcode+M_REV(pc)
	lea	mdata+D_ON(pc),a0
	move.w	#1,(a0)
.done:	movem.l	(sp)+,d0-d7/a0-a6
	rts

exit:	clr.w	$ffff8900.w
	rts

; Add the load address to each absolute long the block holds (once a load).
relocate:
	lea	relocated(pc),a0
	tas	(a0)
	bne.s	.r
	lea	sndh(pc),a0
	move.l	a0,d1
	lea	mcode(pc),a1
	lea	reltab(pc),a2
	moveq	#NRELOC-1,d7
.l:	move.w	(a2)+,d0
	move.l	(a2)+,d2
	add.l	d1,d2
	move.l	d2,0(a1,d0.w)
	dbra	d7,.l
	lea	farp(pc),a2			; the far labels, out of (pc) reach
	moveq	#2,d7
.f:	add.l	d1,(a2)+
	dbra	d7,.f
.r:	rts

; $2A4: music off, DMA stopped, the rewind one-shot mono at 12517 Hz.
rewind:	lea	mdata+D_ON(pc),a0
	clr.w	(a0)
	andi.b	#$fe,$ffff8901.w
	move.l	farp+4(pc),d0
	move.b	d0,$ffff8907.w
	lsr.l	#8,d0
	move.b	d0,$ffff8905.w
	lsr.l	#8,d0
	move.b	d0,$ffff8903.w
	move.l	farp+8(pc),d0
	move.b	d0,$ffff8913.w
	lsr.l	#8,d0
	move.b	d0,$ffff8911.w
	lsr.l	#8,d0
	move.b	d0,$ffff890f.w
	move.b	#$81,$ffff8921.w
	move.b	#1,$ffff8901.w
	rts

play:	movem.l	d0-d7/a0-a6,-(sp)
	jsr	mcode+M_TICK(pc)			; VBL $55A
	lea	mdata+D_ON(pc),a0
	tst.w	(a0)
	beq.s	.off
	bsr	mix				; the kernel's slices
	bsr	keep				; Timer A tail $70A-$73E
	lea	bufp(pc),a5			; $742: swap, DMA the buffer just mixed
	movem.l	(a5),d0-d1
	exg	d0,d1
	movem.l	d0-d1,(a5)
	jsr	mcode+M_DMA(pc)
.off:	movem.l	(sp)+,d0-d7/a0-a6
	rts

; Left: voices 1 and 3 into the even bytes; right: voices 2 and 4 into the odd.
mix:	lea	mcode+M_VPTR(pc),a6
	lea	mcode+M_VOICE(pc),a5
	movea.l	bufp(pc),a0
	movea.l	(a6),a1				; voice 1
	movea.l	8(a6),a2			; voice 3
	move.w	2(a5),d2
	move.w	$50+2(a5),d3
	bsr.s	mix2
	move.l	a1,(a6)
	move.l	a2,8(a6)
	movea.l	bufp(pc),a0
	addq.l	#1,a0
	movea.l	4(a6),a1			; voice 2
	movea.l	12(a6),a2			; voice 4
	move.w	$28+2(a5),d2
	move.w	$78+2(a5),d3
	bsr.s	mix2
	move.l	a1,4(a6)
	move.l	a2,12(a6)
	rts

; a0 = output (every other byte), a1/a2 = voices, d2/d3 = their step-table offsets
mix2:	movea.l	farp(pc),a3
	movea.l	a3,a4
	adda.w	d2,a3
	adda.w	d3,a4
	move.w	#NSTEP-1,d7
.s:	move.b	(a1),d1
	add.b	(a2),d1
	move.b	d1,(a0)
	addq.l	#2,a0
	adda.w	(a3)+,a1
	adda.w	(a4)+,a2
	dbra	d7,.s
	rts

; An active voice keeps the pointer it was mixed to ($70A: move.l $77A6,$772A ...).
keep:	lea	mcode+M_VPTR(pc),a6
	lea	mcode+M_VOICE(pc),a5
	moveq	#3,d7
.k:	tst.w	$12(a5)
	beq.s	.n
	move.l	(a6),$24(a5)
.n:	addq.l	#4,a6
	lea	$28(a5),a5
	dbra	d7,.k
	rts

relocated:
	dc.b	0
	even
bufp:	dc.l	0,0				; $59C/$5A0
farp:	dc.l	steps-sndh,sfx-sndh,sfx_end-sndh	; + the load address
reltab:
	include	"mw_reloc.i"
	even
mcode:	incbin	"mw_code.bin"
	even
mdata:	incbin	"mw_data.bin"
	even
sfx:	incbin	"mw_sfx.bin"
sfx_end:
	even
steps:	ds.b	64*256*2			; built by the init ($88C4)
