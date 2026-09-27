; ---------------------------------------------------------------------------
; SKYSTRIKE, ZIG mode's sound effects (included by sound.s): synthesized
; samples (tools/skystrike/make_sfx.py, sfx/*.raw) played by the STE's DMA
; sound chip, which this machine plays on its Paula sample channels
; (libs/zig/players/ste_dma.zig). The YM is not touched, so the music (and
; the engine's PSG note) goes on under them. The cart's zig_sound.zig says
; which sample each of the game's effect routines (990-998) plays.
;
;   op 9  ZPLAY arg: sample arg & $7F (ztab below), looped when bit 7 is set;
;         a sample already playing is cut
;   op 10 ZSTOP arg: 0 stops the chip; 1 stops it only if it is looping
;
; The chip: start / end addresses in $FF8903/5/7 and $FF890F/11/13 (end
; exclusive), mode $FF8921 (bit 7 mono, bits 0-1 the rate: 0 = 6258 Hz,
; 1 = 12517 Hz), control $FF8901 (bit 0 play, bit 1 loop).
; ---------------------------------------------------------------------------
DMA		equ	$ffff8900
ZNUM		equ	6

; d0 = arg
zplay:
	lea	DMA.w,a1
	clr.b	1(a1)				; stop: a new frame starts clean
	move.w	d0,d2
	and.w	#$7f,d0
	cmp.w	#ZNUM,d0
	bcc.s	.out
	mulu	#10,d0
	lea	ztab(pc),a2
	lea	0(a2,d0.w),a0
	move.l	a2,d1
	add.l	(a0),d1				; the start
	move.l	a2,d3
	add.l	4(a0),d3			; the end
	moveq	#3,d0
	bsr.s	dma_addr			; d1 -> $FF8903/5/7
	move.l	d3,d1
	moveq	#$f,d0
	bsr.s	dma_addr			; d3 -> $FF890F/11/13
	move.b	9(a0),$21(a1)			; mono, the sample's rate
	moveq	#1,d0
	btst	#7,d2
	beq.s	.go
	moveq	#3,d0
.go:	move.b	d0,1(a1)
.out:	rts

; d1 = a 24-bit address into the three byte registers from d0(a1), two apart
dma_addr:
	swap	d1
	move.b	d1,0(a1,d0.w)
	swap	d1
	move.w	d1,d4
	lsr.w	#8,d4
	move.b	d4,2(a1,d0.w)
	move.b	d1,4(a1,d0.w)
	rts

; d0 = arg
zstop:
	lea	DMA.w,a1
	tst.b	d0
	beq.s	.stop
	btst	#1,1(a1)			; only a looping sample
	beq.s	.out
.stop:	clr.b	1(a1)
.out:	rts

; per sample: start and end (from ztab), a pad byte, the mode byte
	even
ztab:
	dc.l	z_gun-ztab, z_gun_end-ztab
	dc.b	0, $81
	dc.l	z_bang-ztab, z_bang_end-ztab
	dc.b	0, $81
	dc.l	z_crash-ztab, z_crash_end-ztab
	dc.b	0, $80
	dc.l	z_bomb-ztab, z_bomb_end-ztab
	dc.b	0, $80
	dc.l	z_splash-ztab, z_splash_end-ztab
	dc.b	0, $81
	dc.l	z_hit-ztab, z_hit_end-ztab
	dc.b	0, $81

z_gun:		incbin	"sfx/gun.raw"
z_gun_end:
z_bang:		incbin	"sfx/bang.raw"
z_bang_end:
z_crash:	incbin	"sfx/crash.raw"
z_crash_end:
z_bomb:		incbin	"sfx/bomb.raw"
z_bomb_end:
z_splash:	incbin	"sfx/splash.raw"
z_splash_end:
z_hit:		incbin	"sfx/hit.raw"
z_hit_end:
	even
