; ---------------------------------------------------------------------------
; JOUST's sound effects, as an SNDH (docs/music/joust_sfx.sndh).
;
; JOUST (Atari Corp 1986, The Rugby Circle) has no music and no replay
; routine: every sound is an XBIOS Dosound(32) script -- 16 of them, pointer
; table at TEXT $17E2, data at $157D-$17E1 -- that TOS plays on its 50 Hz
; Timer C tick. The only other sound is the start-up siren $09AC, a tone
; sweep written straight into the PSG through Giaccess.
;
; A ZigMachine cart cannot write the YM itself: its only door to the chip is
; the song bridge. So the cart requests a subtune of this image each time
; the game starts a script, and this image plays that script with TOS's own
; Dosound semantics (the cart runs the same interpreter inside the machine,
; because the game reads the chip back: $0AC8).
;
;   subtune n (1..16)  Dosound script n-1, byte for byte (sfx_scripts.bin is
;                      TEXT $157D-$17E1 of JOUST.PRG)
;   subtune 17         the siren: 16 sweeps of tone A (period $100 -> 0, step 2)
;                      and B (+$C00), volume 15 -> 0, at the pace the game runs
;                      it (6,141,656 cycles for 2064 steps in the harness:
;                      2976 cycles a step)
;
; The Dosound interpreter (one tick):
;   $00-$7F r,v   write v to register r
;   $80 v         temp := v
;   $81 r,i,e     write temp to r, temp += i; until temp == e, stop here for
;                 this tick (one sweep step per tick)
;   $82-$FF n     n = 0: the script ends; else wait n ticks
;
; play runs at 300 Hz (TC300): the Dosound tick every 6th call is TOS's 50 Hz
; (the first one 10 ms after the request, the middle of TOS's 0-20 ms), and
; 300 Hz is a whole number of samples at both 44.1 and 48 kHz, so it never
; drifts; the siren steps on every call (9 steps a call) for a smoother sweep.
;
; Build: vasmm68k_mot -Fbin -o docs/music/joust_sfx.sndh apps/zig/assets/screens/joust/sfx.s
; (run from the repository root; vasm 1.9, /home/matt/projects/MJJ/bin/vasm)
; ---------------------------------------------------------------------------
	bra.w	init
	bra.w	exit
	bra.w	play
	dc.b	"SNDH"
	dc.b	"TITLJoust sound effects",0
	dc.b	"COMMThe Rugby Circle / Atari Corp",0
	dc.b	"RIPPDosound scripts of JOUST.PRG",0
	dc.b	"YEAR1986",0
	dc.b	"##17",0
	dc.b	"TC300",0
	dc.b	"HDNS"
	even

PSG_SEL		equ	$ffff8800
PSG_DATA	equ	$ffff8802
SIREN		equ	17
STEP_CYC	equ	2976		; one siren step, 68000 cycles
TICK_CYC	equ	26737		; one 300 Hz call, 68000 cycles (8021247 / 300)

; ---- state (PC-relative, the image is loaded anywhere) ----
v_ptr		equ	0		; .l current script byte (0 = idle)
v_delay		equ	4		; .b ticks to wait
v_temp		equ	5		; .b the $80/$81 temp
v_tick		equ	6		; .w 300 Hz calls until the next Dosound tick
v_vol		equ	8		; .w siren volume (-1 = no siren)
v_period	equ	10		; .w siren period
v_acc		equ	12		; .l siren cycle accumulator

init:					; d0.w = subtune (1..17)
	movem.l	d0-d2/a0-a1,-(a7)
	lea	vars(pc),a1
	clr.l	v_ptr(a1)
	clr.b	v_delay(a1)
	clr.b	v_temp(a1)
	move.w	#3,v_tick(a1)		; the first tick 10 ms in: TOS ticks 0-20 ms after Dosound
	move.w	#-1,v_vol(a1)
	clr.l	v_acc(a1)
	cmp.w	#SIREN,d0
	beq.s	.siren
	subq.w	#1,d0
	bmi.s	.out
	cmp.w	#16,d0
	bhs.s	.out
	add.w	d0,d0
	lea	offsets(pc),a0
	move.w	0(a0,d0.w),d1
	lea	scripts(pc),a0
	lea	0(a0,d1.w),a0
	move.l	a0,v_ptr(a1)
	bra.s	.out
.siren:
	move.w	#15,v_vol(a1)
	move.w	#$100,v_period(a1)
	move.b	#10,PSG_SEL.w		; Giaccess(0, $8A): channel C volume 0
	move.b	#0,PSG_DATA.w
.out:
	movem.l	(a7)+,d0-d2/a0-a1
	rts

exit:
	move.b	#8,PSG_SEL.w
	move.b	#0,PSG_DATA.w
	move.b	#9,PSG_SEL.w
	move.b	#0,PSG_DATA.w
	move.b	#10,PSG_SEL.w
	move.b	#0,PSG_DATA.w
	rts

play:
	movem.l	d0-d7/a0-a1,-(a7)
	lea	vars(pc),a1
	tst.w	v_vol(a1)
	bmi.s	.nosiren
	bsr	siren
.nosiren:
	subq.w	#1,v_tick(a1)
	bpl.s	.done
	move.w	#5,v_tick(a1)
	bsr	dosound
.done:
	movem.l	(a7)+,d0-d7/a0-a1
	rts

; ---- the siren ($09AC): as many steps as fit in one 300 Hz call ----
siren:
	add.l	#TICK_CYC,v_acc(a1)
.step:
	cmp.l	#STEP_CYC,v_acc(a1)
	blt.s	.rts
	sub.l	#STEP_CYC,v_acc(a1)
	move.w	v_vol(a1),d1
	move.w	v_period(a1),d2
	move.b	#1,PSG_SEL.w		; A coarse 0
	move.b	#0,PSG_DATA.w
	move.b	#3,PSG_SEL.w		; B coarse $C
	move.b	#$0c,PSG_DATA.w
	move.b	#8,PSG_SEL.w		; A volume
	move.b	d1,PSG_DATA.w
	move.b	#9,PSG_SEL.w		; B volume
	move.b	d1,PSG_DATA.w
	move.b	#0,PSG_SEL.w		; A fine = period
	move.b	d2,PSG_DATA.w
	move.b	#2,PSG_SEL.w		; B fine = period
	move.b	d2,PSG_DATA.w
	move.b	#7,PSG_SEL.w		; mixer: tones A and B on
	move.b	#$fc,PSG_DATA.w
	subq.w	#2,d2
	bpl.s	.same
	move.w	#$100,d2
	subq.w	#1,d1
	move.w	d1,v_vol(a1)
	bmi.s	.rts			; the 16th sweep ended: silent (volume 0 last)
.same:
	move.w	d2,v_period(a1)
	bra.s	.step
.rts:
	rts

; ---- one Dosound tick (TOS semantics) ----
dosound:
	move.l	v_ptr(a1),d0
	beq.w	.rts
	movea.l	d0,a0
	tst.b	v_delay(a1)
	beq.s	.run
	subq.b	#1,v_delay(a1)
	bne.w	.rts
.run:
	move.w	#511,d7
.next:
	move.b	(a0),d0
	bmi.s	.cmd
	and.b	#15,d0			; $00-$7F: write a register
	move.b	d0,PSG_SEL.w
	move.b	1(a0),PSG_DATA.w
	addq.l	#2,a0
	dbra	d7,.next
	rts
.cmd:
	cmp.b	#$80,d0
	bne.s	.sweep
	move.b	1(a0),v_temp(a1)	; $80: temp
	addq.l	#2,a0
	dbra	d7,.next
	rts
.sweep:
	cmp.b	#$81,d0
	bne.s	.wait
	move.b	1(a0),d1		; $81: write temp, temp += inc until == end
	and.b	#15,d1
	move.b	d1,PSG_SEL.w
	move.b	v_temp(a1),PSG_DATA.w
	move.b	v_temp(a1),d2
	add.b	2(a0),d2
	move.b	d2,v_temp(a1)
	cmp.b	3(a0),d2
	beq.s	.swept
	move.l	a0,v_ptr(a1)		; one sweep step per tick
	rts
.swept:
	addq.l	#4,a0
	dbra	d7,.next
	rts
.wait:
	move.b	1(a0),d1		; $82+: wait n ticks, n = 0 ends
	addq.l	#2,a0
	tst.b	d1
	bne.s	.delay
	clr.l	v_ptr(a1)
	rts
.delay:
	move.b	d1,v_delay(a1)
	move.l	a0,v_ptr(a1)
.rts:
	rts

	even
vars:
	ds.b	16

; the script offsets from TEXT $157D (the pointer table at $17E2, unrelocated)
offsets:
	dc.w	0,10,46,104,140,180,438,248,276,336,302,218,476,402,546,510
scripts:
	incbin	"apps/zig/assets/screens/joust/sfx_scripts.bin"
	even
