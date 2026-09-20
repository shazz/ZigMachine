# The B.I.G. Demo — what is left

All five screens behind the jukebox are built and gated. Everything below is a
refinement to something that already runs: **nothing here is a known-wrong
mechanism**, it is all either unread 68000 code or a measured anomaly with no
explanation yet.

Addresses are in the real demo's memory, read by the ShirazMCP session driving
it in an emulator (2026-09-19/20). Reference captures and dumps live in
`prototypes/codef/23/atarimania/` — gitignored, main checkout only.

**The standing division of labour**, which is what made this work: measurements
off the captures on one side, code readings out of the emulator on the other,
and neither side guessing across the boundary. Every one of the eight
corrections either session made this round was found because the *other* one
had an independent source.

---

## Key 1 — Colorright

### The selector at $14780 — the one VISIBLE gap
Thirteen dispatch arms write the 15-line rainbow band's colour into thirteen
*different* palette entries, so the band's colour walks across the pen range.

    read   $1439C   move.w $14780(pc),d1      the HBL dispatch
    write  $146EE   addi.w #$1,$14780
    read   $146F6   cmpi.w #$d,$14780         wraps 12 -> 0 at $14702

**It is gated on the flag at $14788**, which the VBL sets when the sweep counter
bottoms out at 3 — so it advances ONCE PER FULL SWEEP: 3 -> 180 -> 3 is 354
frames, 7.08 s. Thirteen pens is about **92 seconds for the full walk**.

Jump table at **$147AA** (not $147AC — `lea` has one extension word and is
right; only `movem.l (d16,PC)` is off by two on this demo):

    $143AC $143BC $143F2 $14426 $14458 $14488 $144B6
    $144E2 $1450C $1453A $1456C $145A2 $145DC

Two arms are read: `$143AC` writes entry 0, `$143BC` writes entry 4. **Eleven
are unknown.** The port drives pen 0 always, which is right for the first seven
seconds of a visit and wrong after — see `big/key1.zig`.

### The star validity test at $14118 — and a real anomaly
Placement is rejection-sampled and all three constants are confirmed in the
bitmap: y rejects >$98 then +$17 (range 23..175), x masks to EVEN and rejects
>$E7 then +$2C (range 44..274), pen rejects <= 3. Stars ACCUMULATE — 5,656
shared between consecutive frames with ZERO removed, and every one still
present 400 frames later.

$14118 decides whether a candidate is valid and is **not read**. The port
rejects an already-occupied pixel, inferred from the fill rate falling as the
field fills, not from code.

**The anomaly:** of the 116 even columns in 44..274, exactly ONE never holds a
star — **x = 44** — while x = 46 carries roughly double the mean (50 against
26). That is what you would see if d0 = 0 were remapped to 2 rather than
rejected. 26 expected occurrences and 0 observed is not sampling noise.

### Two more per-sweep mechanisms, gated on the same flag
* `$1470E` walks $14782..$14786 with `eori.w #$ffff,(a0)+` — three words
  toggled, with an early exit on `tst.w d0 / bne`. A small state machine, one
  step per sweep.
* `$1472A` decrements $1477C and reloads it from $1477E (live: 3 and 4), so it
  fires every FOURTH sweep, about every 28 s, and runs $1473E..$14758: an
  8-word RING at **$147F4** rotated by one word.

Neither is implemented and neither has a known visible effect.

---

## Key B — the B.I.G. scroller

### The font-to-buffer renderer — the only unread piece
Font ink lives in planes 0..2 as a glyph-set SELECTOR (byte `b` picks plane
`b div 30`, cell `b mod 30`); screen ink lives in plane 3 as the tint layer.
Something in between transposes one to the other, and it has not been read.

Everything it feeds IS known: eight pre-shifted buffers at $D326 onward
($D3BA $D43A $D4BA $D53A $D5BA $D63A $D6BA $D73A, stride $80 = 64 words = one
word per band line), the 8-phase counter at $D322 dispatching through $D356,
the coarse shift at $D164, and the copy at $D1F0 (160 bytes a line, 64 lines,
`addq.l #$6` so it touches plane 3 and nothing else).

### How 32 px is divided between the coarse shift and the buffers
The rate is settled — **4 px a frame**, measured: $D328 advances ONE byte per
8-phase cycle (+1 over 8 frames, +8 over 64, read twice), and a byte is one
32-px cell. But the coarse 16-px shift at $D164 is reached from SIX of the
eight phases, not one, and 6 x 16 reconciles with nothing anyone has proposed.
The port does not need to know; a future change to the scroll does.

Note the routine READS two bytes and ADVANCES one — $D32A and $D330 are the
current cell and the NEXT, a sliding window across a 32-px boundary.

---

## Key 2 — the 512-colour Psych-O-Screen

**Complete, and it cannot be made byte-exact.** The generator at $18F44 is
seeded from the 200 Hz clock at $4BA and the live beam position at $FF8206, so
two runs of the REAL demo do not produce the same plane. What is reproduced is
the structure, and the harness checks statistics rather than pixels.

For the record, in case anyone re-derives it: the diagonal shift IS a closed
rotation — `movem.l (a1),d2-d7` at **$18B36** saves twelve words of the head
*before* the loop and **$18B98** writes them at the far end after it, eleven
verbatim and the twelfth replaced by the fed value.

---

## Key 3 — the raster field

**Complete.** One thing is a shape argument rather than a reading: the three
scroll scripts at $1B778, $1B7AA and $1B7C8 are real $FFFF-terminated
(count, reload) data at the addresses the other three sections load, but that
they drive a2, R1 and R2 *respectively* has not been confirmed. Flagged in
`big/key3_data.zig`.

---

## Audio

The STE DMA sound chip is implemented (`libs/zig/players/ste_dma.zig`) and
**untested against a tune that actually uses it** — the Digital Department's
five `FLAG~ay` tunes write to it zero times, being STF-style arrangements that
drive digidrums through PSG volume writes. `audioDmaWrites()` / `audioDmaStarts()`
report the traffic, so an idle chip is visible rather than assumed.

Not emulated, and named in the source: the frame-end interrupt (MFP GPIP 7),
the Microwire volume and tone registers, and the real chip's latching of the
pointers at the END of a frame rather than when the go bit is set.

A cookie jar is planted at $5A0 (`_MCH` = STE, `_SND` = YM + DMA). It made no
difference to these five and is kept because a tune that probes and finds
nothing takes a different path silently.

---

## Two things that will bite whoever picks this up

**Anchors are per-screen.** `capture row = display line + N`, and N is NOT the
same across captures — the menu is +31, key 1 is +30. Pin it per capture (the
reliable way is correlating the bitmap's horizontal edges against the still)
before comparing anything.

**A documented gap still ships a wrong screen.** Both bugs Matt found by eye —
key 1 standing still, key 2's field dying to eight colours — were in code
whose comments said "not read, guessed". The comment was not the problem; the
missing thing was a CHECK that the gap changes something observable. Every
structural assertion stayed green through both: a palette of eight colours is
still per-line, a frozen palette is still the right shape.
