# Aurora boot (R89, spike)

The new KESTREL boot screen, cart 161 `aurora_boot` (`apps/zig/scenes/aurora_boot.zig`). Matt's concept (24 Nov):
a night sky (a real photo), a curtain of aurora light fades in, moves, fades away, while every star of the sky
flies along a curved path to become a dot on the wireframe of a falcon; the falcon's lines fade in, the name
KESTREL appears, hold, fade to black. KESTREL's falcon HOVERS (wingbeats, head still); PEREGRINE's (later
board) will STOOP. This spike does KESTREL; the stoop is a settings switch in the lab and is not baked (see
"What is not done"). The current boot screen (cart 131 `kestrel_boot`, WINDHOVER) is untouched.

## The spec: Matt's tuned lab

`tools/boot/aurora_lab.html` (our own code; open it in a browser) is the reference and
`tools/boot/aurora_settings.json` holds Matt's values (the lab's defaults equal them). The baker reimplements the
lab, number for number, where it can.

## Architecture: bake everything, play it back

Everything is computed offline by `tools/boot/aurora_bake.py` (numpy + pillow, `uv run --with numpy --with
pillow python tools/boot/aurora_bake.py`; it needs `zig-out/bin/zx0pack`, which `zig build` installs). The cart
is a player: frame index -> unpack -> add spans -> plot points -> draw lines -> TC_FADE. No float, no trig, no 3D
at run time.

| Plane | What | Source |
|---|---|---|
| 0, RGB565 true colour 320x200 | the photo (stars painted out) + the aurora, added in place | `sky.zx0`, `aurora.zx0` + `aurora.idx` |
| 1, 8-bit, on top | stars and their flight, the falcon's wire, the name | `stars.zx0` (one record per 30 fps frame) |
| sound | "Northern Lights soft", CC0, signed 8-bit mono 22,050 Hz, `zg.samplePlay` at frame 0 | `boot.raw` |

The TC plane has no colour key, so the stars live on a normal 8-bit plane over it. Plane 1's alpha is binary: a
star at the lab's alpha a is an opaque palette ramp entry (`look.zig`); the wire and the name are one entry each,
recoloured by their level. The final fade is TC_FADE on plane 0 and the machine's own fade rule applied to
plane 1's entries, so both reach black together.

### The aurora (plane 0)

`aurora_march.py` is the lab's `FS_SCENE` in numpy float32: curtains as thin sheets along folded curves,
slab-limited ray march (51 steps, 3 curtains), altitude emission ramp, rays from 1D noise, the shader's own
`fract(sin(n) * 43758.5453)` noise and per-pixel jitter. `aurora_post.py` is `FS_BLUR` + `FS_OUT`: the 1/4
resolution bloom (two 5-tap passes with the GPU's bilinear sampling), ACES, gamma, RGB565 rounding.

The lab tone-maps photo and aurora TOGETHER, so a tone-mapped aurora added to a tone-mapped photo would be too
bright. The baker therefore renders the picture twice (with and without the aurora) and stores the
**difference in RGB565 levels**; `sky.zx0` is the picture without aurora. ACES is monotone, so the difference
is never negative, and the baker also proves per pixel that `sky + entry` never overflows a channel on either
row an entry covers (`fit_headroom`, 0 fixes needed on the committed bake): the cart's add is a plain 16-bit add,
two pixels in a 32-bit add would equal the saturating one.

**Palette, no dither.** Only 2,636 distinct difference colours exist over all 151 frames. One shared 256-entry
palette (entry 0 = exactly no aurora) is chosen by weighted median cut + 12 Lloyd steps (`aurora_palette.py`,
deterministic, sorted by brightness so index distance follows colour distance), every pixel takes its nearest entry,
nothing is dithered. Error vs the exact difference: mean 0.04 / 0.25 / 0.03 levels (R5 / G6 / B5), worst 2 / 4 / 2.
A 565 level is the display's own step, so the soft fade shows no extra banding beyond 565 itself; `weight_pow`
(0.5) already favours the dark end. If banding ever shows, the options are weight_pow 0.3 (more entries at the dark
end, 0.4 mean error on G), two palettes (one per colour band), or intensity + altitude stored as two indices.

**Packing.** Measured on the grain-faithful frames (sizes are ZX0, per frame):

| Option | Packed (151 frames) |
|---|---|
| 1a intra, every row | ~3.1 MB |
| 1b delta vs previous (index difference mod 256), every row | 1.6 MB |
| 1c XOR vs previous | 1.7 MB |
| 3 delta, every other row | 0.8 MB |
| 3 + hysteresis 1 level | 0.48 MB |
| **3 + hysteresis 2 levels (chosen)** | **0.31 MB** |
| same, 15 fps, every other row | 0.23 MB |
| same, every row | 0.62 MB |
| 2 changed-run lists (x, len, bytes) | 920 runs / frame, 0.6 MB before ZX0: no better than 1b+hysteresis |
| 5 tile dictionary (8x4 .. 4x2) | the bank is as big as the frames: 40 % of all tiles are distinct (46,000 of 120,000 at 8x4), 755 KB - 1.4 MB: no |

The aurora is NOT static (18 % of pixels change index every frame; the curtains and rays move), so a dictionary
finds no repeats. What works is the delta plus a temporal hold: a pixel keeps its previous palette entry while the
new one is within **2 levels** of it (the error is bounded to 2 levels per channel and never accumulates, the last
frame is exact). Only about 5 % of pixels then change per frame. The lower edge, shown at the baker's
resolution, is a little blockier with every other row (the stored row is shown on two screen rows); full rows
cost twice the data (`aurora_pack.ROW_STEP = 1`, 0.62 MB). Matt can pick. Chosen on size/cost: the cart writes only
changed pixels, so a smaller stream is also less work.

Per frame the cart unpacks the delta (`zx0.Stream`, 83 rows x 320 B, half on each 60 Hz frame), reads it as 32-bit
words (a word of four zero deltas costs one load) and for each non-zero delta updates the pixel on both rows it
covers. `blend.zig`.

### The star plane (plane 1)

`aurora_falcon.py` is the lab's wireframe (`V`/`E`), `pose`, `project` and `assignTargets` (dots spread evenly
along the edges by length, one per star, matched to stars by angle around the centre, delay by radius).
`aurora_stars.py` evaluates every 30 fps frame: each star's pixel and level (quadratic Bezier flight with the
swirl, the delays, the falcon's moving target, the twinkle), the falcon's 42 projected vertices (Q4 pixels) and
three scalars (wire level, name level, fade). A record is 798 i16; the stream stores each record as the
difference from the previous one: **37.7 KB** ZX0 for 255 records (raw 407 KB, expanded at init; column-major
delta would be 28 KB, not worth the transpose). The cart adds the next delta to a running record and draws points
and DDA lines (`plot.zig`); an odd 60 Hz frame shows the midpoint.

### Sound

The machine's PCM is Paula's, 8-bit, and `zg.samplePlay` hands the whole sample to the audio side (the sound CPU on
the board, the audio thread in the browser): nothing per frame, the same on both, the cheapest path. Mono
mix, FFT resample 48 -> 22.05 kHz, trimmed to the picture's 8.467 s with a 50 ms closing ramp, peak lifted to
-1 dBFS (the master's peak is -9 dB, 8 bits must not waste range), TPDF dither from a seeded generator (audio
dither is what keeps a quiet pad free of quantisation distortion; the image gets none), rounded to int8. 186,690
bytes; ZX0 does not shrink PCM, so it ships raw. Stereo (`zg.audioStreamStartStereo`) would double that and add a
per-frame feed; mono is fine for a pad. Not wired to the board's audio yet: board to-do.
Source: `apps/zig/assets/screens/aurora_boot/SOURCE_sound.txt` (neolein, Freesound 721140, CC0 1.0; the author
asks for feedback if it is used in artworks).

## Data and cost

| | bytes |
|---|---|
| sky (565, ZX0) | 28,590 |
| aurora (151 delta containers + offsets) | 351,000 (see aurora_ref.json `sizes`) |
| star plane records (ZX0) | 37,714 |
| sound (s8 mono 22,050 Hz) | 186,690 |
| **baked total** | **~604,000** |
| cart wasm | 654 KB; disk `demo-aurora_boot.zmd` ~539 KB |

Run time memory: sky copy 128 KB, star records 407 KB, aurora frame delta 26.5 KB, state 26.5 KB; VRAM: the
TC plane (128 KB) and the star plane (64 KB).

Cost on ZIGGY (`tools/perf_audit.sh aurora_boot`, estimate, `apps/harness/perf/cost_model.mjs`): about 0.6 Mc a
frame of cart work and 1.3 Mc of FRESCO for the two planes (2 enabled planes are the big lever: 0.59 Mc each),
~1.9 Mc total (p95 2.3), ~52 fps estimated; the board's band is 1.75-2.1 Mc, so the board decides. The cart half
is the ZX0 unpack (byte copies, ~0.16 Mc), the plane 1 clear and ~240 star pixels.

## Fidelity to the lab, and deviations

Close: same shader constants, camera, noise, march, ramp, bloom, ACES, gamma and 565 quantisation, same falcon,
dots, flights and timeline. Deviations:

- **Photo resampling.** The lab uses the browser's canvas resize; PIL bicubic finds 237 stars where the lab's JSON
  reports 254 (lanczos 282, bilinear 121, box 455). Same algorithm otherwise.
- **float32 sin** of numpy (not the GPU's) in the noise hash: rays differ in the fine grain, not in character.
- The lab's RGBA16F buffers are float32 here.
- **Stars and the wire** are opaque palette ramps, not alpha blends; the ramp starts at a dim blue-grey so a faint
  star is not a black speck over bright aurora.
- **Lines** are integer DDA, not antialiased strokes.
- **Aurora** every other row with a 2-level temporal hold (above).
- **Sound** is a 22 kHz 8-bit mono reduction of the 48 kHz stereo master.
- Timeline: the cart plays the lab's 8.45 s (stars alone 1.0 s, aurora 5.0 s, flight 1.7-5.15 s, name 5.85 s,
  fade 7.85-8.45 s) with no extra fade in: it starts on the sky.

## Keys and flow

Space or R replays (the sky restored, the sound stopped and restarted); Esc leaves. K / P (KESTREL / PEREGRINE) are
a hook: only KESTREL is baked. The cart asks to leave (`pollCartRequest -1`) at the last record, black, as
`kestrel_boot` does, so a replay works until then. Wiring it into glass's boot (`fpga/glass/src/app_splash.zig`) is
not part of the spike.

## Re-baking

```
zig build                      # installs zig-out/bin/zx0pack
uv run --with numpy --with pillow python tools/boot/aurora_bake.py     # ~8 min, rewrites apps/zig/assets/screens/aurora_boot/
./build.sh --only aurora_boot  # the harness reads the new aurora_ref.json: nothing is pinned by hand
```
`--frames N` renders only N aurora frames (the tests use 2). Python tests: `tools/tests/test_aurora_bake.py`.

## Harness

`apps/harness/aurora_boot_check.mjs`: the cart's TC plane after 5 aurora frames equals the Python reference (numpy's
`base + palette[index]`) byte for byte, so the ZX0 + delta + add loop is the model's; plus the beats, the fade, the
end, the sound (one op at frame 0, the baker's bytes, its rate, never stopped, as long as the picture) and the
replay. `--break` runs 8 mutants. The audio itself is not rendered by the harness (that runs on the audio side);
the exact bytes and timing handed to it are checked.

## Board to-do

fps (OSD) through the aurora window and the flight; the look vs the lab on the real screen (the 565 + palette-less
aurora, the half-row edge); the 654 KB cart's load time from the card; the sample on the board (level, the 8-bit
hiss under a quiet pad, start in step with the picture); the wiring into glass's boot; the PEREGRINE stoop.

## What is not done

PEREGRINE's stoop (the lab's `pose` has it; the baker would bake it as a second set of records and a key would
switch them); the K / P key; glass integration; a chime hook is replaced by the sample.
