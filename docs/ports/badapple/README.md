# BAD APPLE!! (cart 162, R89)

A 1-bit film played from a stream of row-transition edits. The design is `HINTS.md` (the lead's brief, written
before any code); this is what was built and what it costs.

## Licence: what is committed and what is not

- Committed: the player (`apps/zig/scenes/badapple.zig`, `badapple/`), the encoder, the reference decoder and the
  format (`tools/badapple/`), and OUR synthetic test film (`apps/zig/assets/screens/badapple/test_spans.bin`,
  7.7 KB, drawn by `tools/badapple/synth.py`: moving discs, a hard cut, an all-white and an all-black frame, a row
  with exactly 62 transitions and one cut at 62). The shelf disk and the gate use only that.
- NOT committed: the real film (derived from the Bad Apple video, a copyrighted fan animation) and the song (an
  XM of unknown licence). They live in `prototypes/badapple_local/` (git-ignored). A second cart Gemini
  ported from github.com/braheezy/gbadapp (no licence) was dropped; a copy of everything it left is in
  `prototypes/badapple_local/gemini_snapshot/`.
- Local build, as RACER's `-Dracer_music`: `prototypes/cards/build_badapple.sh [rev]` builds with
  `-Dbadapple_music=true` (embeds the git-ignored `apps/zig/assets/screens/badapple/local.xm`) and packs the real
  stream into the disk through `BADAPPLE_SPANS=<file> tools/mkdisks.sh`. Without the option the cart is silent.

## Format ("BASP", `tools/badapple/spans.py` has the byte layout)

Per row, the x positions where the colour flips (a row starts black; at most 62; the encoder cuts a longer row
there and the rest keeps the last colour). A frame is, row by row: skip N unchanged rows; a row with the same
number of transitions as before as nibble dx (-7..+7, two a byte); or the whole row (one or two bytes a
transition). A block is 30 frames (1 s), starts with a keyframe (every row in full), and is ZX0-packed with
`zx0pack`. The file is a 16-byte header, then per block `<packed u32, raw u32, frames u16>` + the packed bytes.
The cart refuses a header that is not 320x200 and any frame that is out of range, short or long.

## The player

- `badapple/blocks.zig`: SPANS.BIN is read a block AHEAD: one disk call for the packed block, then the depack
  `zx0.Stream.step`s 6 KB a frame into the second of two raw buffers, so a block change is a pointer swap, not
  a ~1.5 Mc depack (the real film's largest block is 75,643 bytes raw, 41,472 packed). If the picture catches
  up with the fill it is finished at once. A broken block is shown only when the picture reaches it (red).
- `badapple/decoder.zig`: pure Zig, native tests; repaints each CHANGED row (`@memset` of the row's runs into
  plane 0's 8-bit buffer). A row repaint rewrites the unchanged parts of that row too (a per-edge repaint was
  not worth its overlap cases: see Costs).
- One plane, palette 0 black, 1 white (a fade or tint is a palette write), 2 red = failure.
- Sync: the frame is `elapsed hostMicros x 30 / 1e6 + 1` from the first update. A cart-asked XM has no audio
  position to read (zg.bard.position() is the BARD FM queue's, not the song engine's), so the clock starts when
  the song is requested; a late picture decodes every frame it owes (they are deltas) and shows the last. No
  clock (a host answering 0): 30 fps from the 60 Hz VBLs.
- No float per frame (the only maths is a u64 multiply-divide once a frame).

## The real film (prototypes/badapple_local/spans.bin)

6,573 frames (3 min 39 s), 220 blocks, **2,455,092 bytes** (2.34 MB; 373 bytes a frame packed), 320x200,
thresholded at 128 with no hysteresis. Per frame: 148 of the 200 rows change on average (all 200 at worst),
67 of them as full rows (1,733 frames have 100+ full rows: the noise of the threshold makes edges jitter by more
than a nibble holds); 754 bytes raw a frame on average, 4,228 at most.

## Costs (estimate, not measured on the board)

ZIGGY: a store ~2.3 cycles, so a 320-byte row repaint is ~185 cycles; 148 rows = 27 kcycles (0.03 Mc), 200 rows
37 kcycles; decoding ~754 bytes ~40 kcycles. A frame is 0.05-0.10 Mc against the board's 1.67 Mc a 60 Hz frame; the
read-ahead depack adds ~0.04 Mc a frame for ~19 frames a second (75 KB at 6 KB a frame, ~10 cycles a byte). One
enabled plane (~0.59 Mc compositing, +0.11 a frame) is the dominant cost and cannot go lower. The disk call for
a packed block (up to 41 KB) is one hiccup a second whose size on the board's SD is the unknown.

## Gate

`build.sh`: the synthetic stream is what the encoder writes (`gen_spans.py --synth --check`); `badapple_headless.mjs`:
the cart's plane equals `tools/badapple/ref_decode.py`'s frame (its own ZX0 depacker, none of the cart's code) at 17
pinned frames while the clock runs, after a 1.5 s stall across a block change and the cut, with no clock, a broken
block goes red, silent, Escape; `--break` shifts the plane one pixel and must be caught. Native: the decoder tests in
`scene_tests.zig`; Python: `tools/tests/test_badapple_spans.py`.

## Board to-do

1. `prototypes/cards/build_badapple.sh` (add `SPLIT=1` for the split cart), put `demo-badapple.zmd` (the real film)
   on the shelf as `progs/<disk>/demo-badapple.zmd`, a stale program firmware is CartSilent otherwise.
2. OSD fps and the worst frame (a block's disk read); sync by ear over the whole song, the music is the local XM.
3. If the song drifts: a clock from the audio side (needs a position from the song engine).
4. Encoder hysteresis (keep an edge within 1 px of the last frame's) to cut the 148 changed rows a frame.
