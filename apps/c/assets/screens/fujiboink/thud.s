; ---------------------------------------------------------------------------
; FujiBoink!'s one sound effect, as an SNDH (docs/music/fujiboink_thud.sndh).
;
; FUJIBOIN.C makes exactly one noise ("I know, I know, there's only one sound
; effect" - Behind the Bit Planes, START Fall 1986). soundiniz() programs the
; PSG once through XBIOS Giaccess:
;     reg 7 = 63-9 (tone+noise on A)   reg 8 = 16 (A follows the envelope)
;     reg 0/1 = 255/15 (period $FFF)   reg 6 = 31 (noise period)
;     reg 11/12 = 0/16 (env period $1000 = 0.52 s)
; and every bounce thud() writes reg 13 = 0: shape \___, a half-second decay.
;
; A ZigMachine cart cannot write the YM itself: the chip lives on the audio
; thread and the only door to it is the song bridge. So the bounce REQUESTS
; this image and its init does what soundiniz()+thud() did, register for
; register, through $FF8800 like Giaccess: loading it runs init, init writes
; reg 13, and the envelope restarts. play does nothing, as the original had no
; replay routine. Registers the original never set (B/C tone, B/C volume) are
; written 0; the mixer keeps B and C off either way.
;
; Build: vasmm68k_mot -Fbin -o docs/music/fujiboink_thud.sndh thud.s
; ---------------------------------------------------------------------------
	bra.w	init
	bra.w	exit
	bra.w	play
	dc.b	"SNDH"
	dc.b	"TITLFujiBoink! thud",0
	dc.b	"COMMXanth Park",0
	dc.b	"RIPPsoundiniz()+thud() of FUJIBOIN.C",0
	dc.b	"YEAR1986",0
	dc.b	"##01",0
	dc.b	"TC50",0
	dc.b	"HDNS"
	even
init:
	lea	regs(pc),a0
	moveq	#0,d0
.loop:
	move.b	d0,$ffff8800.w
	move.b	(a0)+,$ffff8802.w
	addq.w	#1,d0
	cmp.w	#14,d0
	bne.s	.loop
	rts
exit:
	move.b	#8,$ffff8800.w		; volume A off
	move.b	#0,$ffff8802.w
	rts
play:
	rts
;		 r0  r1 r2 r3 r4 r5 r6  r7  r8 r9 r10 r11 r12 r13
regs:	dc.b	255,15,0, 0, 0, 0, 31, 54, 16,0, 0,  0,  16, 0
	even
