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

The TC plane has no colour key, so the stars live on a normal 8-bit plane over it. A star at the lab's alpha a is
an opaque palette ramp entry (`look.zig`); the wire and the name are one entry each at their full colour, faded in
by the entry's ALPHA (the mixer blends a partial palette alpha: the board's RTL mixer reproduces Chrome's canvas
blend byte for byte, docs/hardware/FPGA_STEPS.md); F / G's baked name is 128 entries of coverage alpha. The final fade is TC_FADE on plane 0 and the machine's own fade rule applied to
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
| aurora (151 delta containers + offsets) | 351,026 |
| star plane records (ZX0) | 37,714 |
| sound (s8 mono 22,050 Hz) | 186,690 |
| **baked total** | **~604,000** |
| cart wasm | 654 KB; disk `demo-aurora_boot.zmd` ~539 KB |

Cart RAM window: 1,011 KB of 3,072 KB used (2,061 KB free), `check_fits` ok. Run time memory: sky copy 128 KB, star records 407 KB, aurora frame delta 26.5 KB, state 26.5 KB; VRAM: the
TC plane (128 KB) and the star plane (64 KB).

Cost on ZIGGY (cart 161; the variants write more or fewer pixels per frame, the plane cost is the same) (`tools/perf_audit.sh aurora_boot`, estimate, `apps/harness/perf/cost_model.mjs`): about 0.6 Mc a
frame of cart work and 1.3 Mc of FRESCO for the two planes (2 enabled planes are the big lever: 0.59 Mc each),
~2.0 Mc total (p95 2.3), ~50 fps estimated; the board's band is 1.75-2.1 Mc, so the board decides. The cart half
is the ZX0 unpack (byte copies, ~0.16 Mc), the plane 1 clear and ~240 star pixels.

## Variants to compare on the board (24 Nov night)

Matt saw the first bake's aurora as dithered / stained ("JPEG-like stains of colour around the aurora"). Cart 161
is that first bake, kept as shipped (variant **A**); `aurora_boot_b` .. `_e` (carts 162-165, the same scene on
other baked data, `apps/zig/assets/screens/aurora_art_<v>.zig`) are the fixes, each measured on the board's
shots (`prototypes/boot_screen/aurora_compare/`, side by side at 4x, A to E left to right, a stretched row under each).

| | what | aurora data | total baked (+ sky 29 KB, stars 35 KB, shared sound 187 KB) |
|---|---|---|---|
| A (161) | the first bake: jittered march, integer-difference palette, 2-level hold, every other row | 351 KB | 604 KB (old sky and 237 stars) |
| B | no ray-march jitter, the palette chosen on the FLOAT light, 2-level hold, every other row | 302 KB | 553 KB |
| C | B without the hold | 689 KB | 940 KB |
| D | C with every row | 1,346 KB | 1,597 KB |
| E | D with the faint halo's hue locked (`aurora_halo.py`) | 1,310 KB | 1,561 KB |

What each cause contributed (crops at the shot's frames, upper halo, curtain base, ground glow):

1. **The temporal hold is the main culprit.** A and B (both hold) show the large violet / blue patches in the halo
   and rectangular steps at the curtain base: neighbours freeze at different moments, so the dim top of the ramp
   becomes blotches. C (no hold) already turns them into soft vertical rays. Cost: the stream doubles (302 to 689 KB).
2. **Jitter is not the grain.** B differs from A only by smooth light and float quantisation: the halo is no less
   blotchy (the hold is still there), so the ray-march jitter was not what Matt saw; it is gone anyway.
3. **Palette quantisation on rounded channels** made a coloured fringe at the halo's first level (R steps alone):
   quantising on the float light (B..E) removes the salt and pepper between neighbouring palette cells; E's hue lock
   removes the remaining dark red / green fringe of the first levels (D shows a faint red rim, E does not).
4. **Every other row** shows as 2-pixel steps along the curtain base and the horizon; D / E (every row) are the
   smoothest, at twice C's data. The cart's 3 MB window holds D (cart 1.5 MB) with room.

My pick for Matt: **E** if 1.3 MB is acceptable, else **C** (0.69 MB) with a visible but small edge step.
The A-vs-the-rest data are from my crops; the final judgement is Matt's, on the board.

## Variants F and G (25 Nov): past the shared palette

Matt on the board (E, ~5 s in, `prototypes/boot_screen/board_shots/SHOT0111.PNG`): lavender patches in the green
curtain, stair-step blocks along the curtain base, faint banding. Measured against the lab's FLOAT picture
(`prototypes/aurora_f_re/measure.py`, every 5th frame, the band's rows; dE = CIE76 on the displayed sRGB):

1. **The stair steps and the lavender base are in the baker's float render itself** (not compared against
   `aurora_lab.html` directly), not in any quantiser: the lab's
   Edge sharpness (0.045) cuts each of the three curtains off in a few pixels, at a different screen height per
   curtain, and the emission ramp is violet at the base. Neither supersampling the march (4 / 8 / 16 offsets)
   nor 2x2 / 4x4 pixel supersampling changes it. F and G therefore bake **Edge sharpness 0.15** (a soft base, no
   cliff; `VARIANTS` in `aurora_bake.py`): the steps and the violet base line go. **This is a look change to Matt's
   tuned setting**, so the E vs F / G table below mixes storage with edge. The lab slider is the knob if Matt wants
   the violet back (0.1 keeps a little, with softer steps); G at 0.045 is a one-minute re-bake from the cache.
2. **The shared 256-entry palette adds speckle**: on the SAME light (edge 0.045, against the rounded sky) E sits at
   dE mean 1.63 / p99 7.4 where per-row palettes reach 1.29 / 4.3 and plain 565 rounding 1.23 (p99 ~4). One
   palette for ~2,300 colours of the whole film scatters lavender speckle up into the teal (the patches Matt saw);
   plain rounding keeps the violet only at the base, cleanly (`prototypes/aurora_f_re/cmp_j120_100_50_200_150.png`:
   float | rounded | E | ramp).
3. **A per-row hue RAMP is worse than E** (tried first: per row, the principal colour direction of the light,
   8-bit intensity along it, conditional mean colour per step; dE mean 2.2, worst 5 levels on G, and it loses
   the lavender): a row mixes curtains at different heights and the bloom halo, one hue line is too few
   dimensions. Time blocks (4 per-row ramps over the film) did not help either, so drift was not the cause.

| | what | aurora data | dE mean / p99 / max | RGB8 err mean / max | cart RAM free (static) |
|---|---|---|---|---|---|
| E (165) | one shared palette, halo lock, edge 0.045 | 1,310 KB | 2.75 / 8.46 / 19.3 | 2.56 / 21 | 1,154 KB |
| **F (167)** | a 256-entry palette PER ROW (`palette.bin`, 154 rows x 512 B), 8-bit index deltas, edge 0.15 | 1,703 KB | 2.38 / 6.54 / 11.2 | 2.25 / 15 | 754 KB |
| **G (168)** | no palette: the final picture (sky + aurora, the lab's float compositing) rounded to 565 once, 16-bit wrapping deltas, edge 0.15 | 1,992 KB | 1.85 / 4.13 / 5.56 | 1.73 / 4.1 | 465 KB |

G is the floor of any undithered 565 display of the lab (each channel within half a level). F is between.
Crops of frame 120 (E's shot time), 4x, lab float 0.045 | E | lab float 0.15 | F | G:
`prototypes/boot_screen/aurora_compare/efg_{curtain_base,halo_top,right_curtain}_j120.png`.

**F** (`tools/boot/aurora_fg.py` `build_rowpal`): each band row's own median cut + Lloyd palette on its float
light (`aurora_palette.py`, as E's but per row, sorted by brightness so index deltas still pack), the per-row
headroom proof (0 fixes: the add stays a plain 16-bit add, equal to a saturating one), the cart reads
`table[row * 256 + index]` (`blend.Layer.pal_stride`), the table copied to aligned RAM at init (an embedded file
is byte-aligned; a misaligned u16 load traps on the board). No halo lock: per-row palettes already follow the
halo's hue, the lock only moved it.

**G** (`build_direct`, `blend.Direct`): two ZX0 containers a frame (the band's top half on the even 60 Hz
frame, the bottom on the odd), so the delta buffer is half a frame (53 KB), and no sky copy (the sky is unpacked
straight into the plane, again on a replay): its RAM window is the tight one, ~40 KB spare after its 372 KB of
star records and the buffer. 16-bit deltas cost twice E's unpack bytes.

Cost through the aurora window (`apps/harness/frame_cost.mjs --warmup 150 --frames 120`, estimate, cart + FRESCO):
E 3.40 Mc (p95 4.08, ~29.5 fps), F 3.87 Mc (p95 4.81, ~25.8 fps), G 4.22 Mc (p95 5.08, ~23.7 fps); G's top
region is the ZX0 unpack (0.85 Mc). All three are over the board's 60 fps band (1.75-2.1 Mc) while the aurora
plays, as E already was; the OSD decides. The timeline counts frames, so below 60 fps the picture outlasts the
8.5 s sample (E already does). Disks: E 1.50 MB, F 1.83 MB, G 2.19 MB. If a cart's `load()` is refused RAM, it
shows black, restarts the sample every frame and never asks to leave (the harness catches it: G's first build did
this before its sky copy went).

Both F and G draw the **name as a baked image**: "Kestrel" in Matt's script font (Christmas Shine by Fandi, free
for commercial use; `prototypes/boot_screen/font_christmas_shine/SOURCE.txt`; the .otf stays local, only the
image ships), drawn 4x and box-filtered to real coverage (`tools/boot/aurora_word.py`, `word.bin`), 0.65 of the
falcon's wingspan (136 x 52 px: the script's loops make it tall, a full wingspan would leave the screen), centred
under it. On the star plane its pixels are entries 128..255 = the ink at alpha
coverage x name level, so FRESCO blends it over the true-colour sky anti-aliased, no dithering, no 1-bit edge;
it fades in on the name's beat and follows the end fade. A..E keep the bitmap capitals (`WORDMARK` in the meta).

**The wire fades in by alpha (all variants, A included).** The falcon's lines (and the bitmap name) were opaque
ramps from the night sky's colour, so over the bright aurora they appeared BLACK first and then turned white.
FRESCO blends a partial palette alpha, so `look.wire` / `look.ink` now keep their full colour and ramp the alpha
(the lab's `rgba(150,215,255,0.5*a)`): a faint line is the aurora under it tinted toward the colour, never
darker. Crop (E, cart frames 312 / 318, before | before | after | after):
`prototypes/boot_screen/aurora_compare/wire_fadein_before_after.png`. Cart 161 on main has the same code and
gets the fix when this branch lands.

Star detector (all variants): stars are found only between `bandTop` and `bandBot` percent of the height (the lab's
two sliders, defaults 0 and 70), because the green airglow near the treeline produced false stars; and a star is
painted out by a horizontal + vertical linear interpolation of the ring (`aurora_photo.inpaint`) instead of a flat
3x3 fill, so a star in a gradient leaves no rectangle. 214 stars remain (237 before the band).

Fade in: `fadeInSky` (default 0.8 s) ramps TC_FADE from 31 (black) to 0 at the start, the star plane's palette in
step (the same baked coefficient). The beats are unchanged: the stars alone second still starts at 0 and the aurora
at 1.0 s, so the 0.8 s fade-in ends before the aurora and nothing overlaps; the end fade is 0.6 s. Cart 161 (A)
has no fade-in (its star records predate it).

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
# F / G render with edge 0.15, so they share their own light cache (~3 min to render, F's palettes ~2 min):
uv run --with numpy --with pillow python tools/boot/aurora_bake.py --variant g --cache prototypes/boot_screen/aurora_f/light_edge015.npz
uv run --with numpy --with pillow python tools/boot/aurora_bake.py --variant f --cache prototypes/boot_screen/aurora_f/light_edge015.npz
```
F / G need the wordmark font locally (`aurora_bake.FONT`); a missing font is an error, never a silent blank.
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
