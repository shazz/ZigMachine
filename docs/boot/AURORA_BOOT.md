# Aurora boot (R89)

The KESTREL boot screen, cart 161 `aurora_boot` (`apps/zig/scenes/aurora_boot.zig`): glass plays it at every
power-on before KOS (`fpga/glass/src/app_splash.zig`, below "On the board: the power-on boot"). Matt's concept
(24 Nov): a night sky (a real photo), a curtain of aurora light fades in, moves, fades away, while every star of the
sky flies along a curved path to become a dot on the wireframe of a falcon; the falcon's lines fade in, the name
Kestrel appears in a script, hold, fade to black, with an 8.5 s pad. KESTREL's falcon HOVERS (wingbeats, head
still); PEREGRINE's (later board) will STOOP: a settings switch in the lab, not baked (see "What is not done").

What ships is the variant Matt called **G2** on the board (26 Nov, "our best shot"); the variants it was chosen from
are summarised under "History". The previous boot screen, cart 131 `kestrel_boot` (WINDHOVER), is untouched and
stays on the shelf.

## The spec: Matt's tuned lab

`tools/boot/aurora_lab.html` (our own code; open it in a browser) is the reference and
`tools/boot/aurora_settings.json` holds Matt's values (the lab's defaults equal them). The baker reimplements the
lab, number for number, where it can, with two deviations, both Matt's calls: Edge sharpness **0.15** (his 0.045 cuts
each curtain off in a few pixels and draws the bases as stair steps, in the float render itself, 25 Nov), and the
name as his script font (Christmas Shine) at 0.42 of the falcon's wingspan (26 Nov).

## Architecture: bake everything, play it back

Everything is computed offline by `tools/boot/aurora_bake.py` (numpy + pillow). The cart is a player: frame index
-> add the aurora's changed pixels -> write the star plane's changed bytes -> palette levels + TC_FADE. No float, no
trig, no 3D, no entropy decoder at run time.

| Plane | What | Source |
|---|---|---|
| 0, RGB565 true colour 320x200 | the photo (stars painted out), then the final 565 picture's 16-bit deltas added in place | `sky.zx0`, `aurora.msk` + `aurora.idx` |
| 1, 8-bit, on top | stars and their flight, the falcon's wire, the name: baked per 60 Hz frame | `overlay.bin` (+ `word.bin`, its source) |
| sound | "Northern Lights soft", CC0, signed 8-bit mono 22,050 Hz, `zg.samplePlay` at frame 0 | `boot.raw` |

The TC plane has no colour key, so the stars live on a normal 8-bit plane over it. Entries 1..15 are the star ramp
(opaque, from a dim blue-grey so a faint star is never a black speck over bright aurora); the wire (entry 16) and the
name (entries 128..255, coverage alpha) keep their full colour and fade in by the palette ALPHA (the lab's
`rgba(150,215,255,0.5*a)`): FRESCO blends a partial alpha, and the board's RTL mixer reproduces Chrome's canvas blend
byte for byte (docs/hardware/FPGA_STEPS.md), so a faint line is the aurora under it tinted toward the colour, never
darker (an opaque ramp from the night sky drew the wire BLACK over the aurora first: Matt, 25 Nov). The final fade is
TC_FADE on plane 0 and the machine's own fade rule applied to plane 1's entries, so both reach black together.

### The aurora (plane 0)

`aurora_march.py` is the lab's `FS_SCENE` in numpy float32: curtains as thin sheets along folded curves,
slab-limited ray march (51 steps, 3 curtains, the step's centre instead of the shader's per-pixel jitter), altitude
emission ramp, rays from 1D noise, the shader's own `fract(sin(n) * 43758.5453)` noise. `aurora_post.py` is
`FS_BLUR` + `FS_OUT`: the 1/4 resolution bloom (two 5-tap passes with the GPU's bilinear sampling), ACES, gamma.

**No palette** (`aurora_direct.py`): the final picture (sky + aurora composited in float, as the lab does) is rounded
to RGB565 once per frame; each channel is within half a level of the lab's float picture (dE mean 1.85, p99 4.1,
max 5.6 on the band). That is the floor of any undithered 565 display of the lab; nothing is dithered.

**Change masks, no ZX0** (`aurora_mask.py`, `masked.zig`). Only 18 % of the band's pixels change a frame and only 97
distinct 16-bit deltas exist (98.6 % within 2 levels a channel), so each frame is two containers (the even and the
odd 60 Hz frame, split where both carry about as many changed pixels): a change MASK (a bit a pixel, zero bytes
run-length coded) plus one NIBBLE a changed pixel (the 15 most frequent deltas, 93 %; 15 = escape + a byte). The
cart walks each non-zero mask byte one set bit at a time (a 256-entry highest-bit table, no clz on rv32im), byte loads
only (embedded data is unaligned; a misaligned load traps on the board), the stream's end checked once per mask byte
(the baker pads 12 zero bytes), the delta table padded to 256 so no index check, and adds the delta to the pixel (a
16-bit wrapping add). The last frame is the sky again (the baker refuses a film that does not end on it), and the
baker decodes all 151 frames back with the cart's loop in Python and refuses a mismatch. Spans (skip/len) cost more
(9.5 KB a frame of run headers alone); ZX0 over the deltas was 2.5 Mc a frame on the board (its bit reader alone 0.85).

### The star plane (plane 1)

`aurora_falcon.py` is the lab's wireframe (`V`/`E`), `pose`, `project` and `assignTargets` (dots spread evenly
along the edges by length, one per star, matched to stars by angle around the centre, delay by radius).
`aurora_stars.py` evaluates every 30 fps frame: each star's pixel and level (quadratic Bezier flight with the swirl,
the delays, the falcon's moving target, the twinkle), the falcon's 42 projected vertices (Q4 pixels) and three
scalars (wire level, name level, fade). `aurora_overlay.py` then draws every 60 Hz frame with integer drawing (seek
the record, the midpoint on the odd frame, a DDA line per edge, one pixel a star, the name image) and stores only the
bytes that change (u16 count, then offset u16 + entry u8): mean 140 writes a frame, 966 at the name's frame, 71,465
over the film, 213 KB. The cart writes them (`overlay.zig`): no clear, no lines, no seek (Matt: "precalculate the
bird"). The levels come from the baked `SCALARS` table.

The name (`aurora_word.py`, `word.bin`): "Kestrel" drawn 4x and box-filtered to real coverage, 89 x 35 px at
(116, 154), entries 128..255 = the ink at alpha coverage x name level, so FRESCO blends it anti-aliased. The font
(Christmas Shine by Fandi, free for commercial use; `prototypes/boot_screen/font_christmas_shine/SOURCE.txt`) stays
local: only the image ships.

Star detector: stars are found only between `bandTop` and `bandBot` percent of the height (the lab's sliders, 0 and
70: the green airglow near the treeline produced false stars), and a star is painted out by a horizontal + vertical
linear interpolation of its ring (`aurora_photo.inpaint`), so a star in a gradient leaves no rectangle. 214 stars.

### Sound

The machine's PCM is Paula's, 8-bit, and `zg.samplePlay` hands the whole sample to the audio side (BARD on the board,
the audio thread in the browser): nothing per frame. Mono mix, FFT resample 48 -> 22.05 kHz, trimmed to the
picture's 8.467 s with a 50 ms closing ramp, peak lifted to -1 dBFS, TPDF dither from a seeded generator, int8:
186,690 bytes, raw (ZX0 does not shrink PCM). Source: `apps/zig/assets/screens/aurora_boot/SOURCE_sound.txt`
(neolein, Freesound 721140, CC0 1.0; the author asks for feedback if it is used in artworks).

### Timeline

Frame-counted at 60 Hz (dt ignored): fade in from black 0.8 s (`fadeInSky`), stars alone until 1.0 s, aurora
1.0-6.0 s, flight 1.7-5.15 s, name 5.85 s, end fade 7.85-8.45 s; black and asks to leave (`pollCartRequest -1`) at
frame 508 (8.467 s). At 60 fps it ends with the sound.

## Data and cost

| | bytes |
|---|---|
| sky (565, ZX0) | 28,786 |
| aurora (302 containers + offsets) | 1,758,059 |
| star plane (`overlay.bin`) | 213,421 |
| sound (s8 mono 22,050 Hz) | 186,690 |
| cart wasm | 2.23 MB; disk `demo-aurora_boot.zmd` 2.24 MB, the wasm UNPACKED (`tools/mkdisks.sh`: the packed copy outgrows the ROM's free RAM where the loader unpacks it); the board's fat disk 3.96 MB |

Cart RAM window (`check_fits`): 2,556 KB of 3,072 KB used, 516 KB free; no run-time buffers (the masks are read in
place, the sky is unpacked straight into the plane, again on a replay).

Board (`glass ctl stats`; `cart_c` = the cart's cycles a frame, the frame is late past ~1.05 Mc): **59.8-60.9 fps,
0 missed** in the aurora, `cart_c` 0.23-0.25 Mc; 514-515 frames in 8.5 s over 3 whole runs (26 Nov, as G2; the
ZX0 version of the same picture ran 17.7-23.2 fps at 3.8-5.1 Mc). The estimator (`apps/harness/frame_cost.mjs`)
says cart 0.29 Mc, total 1.58 Mc (p95 1.62) in the aurora and 1.7 (p95 1.93) in the flight + name window; it still
bills FRESCO 1.3 Mc for the two planes and so sits at the edge of its band: the board is the evidence.

## On the board: the power-on boot

glass's boot splash (`fpga/glass/src/app_splash.zig`, docs/hardware/FPGA_GLASS.md "Boot splash") plays
`demo-aurora_boot.zmd` (anywhere on the shelf; the card has it at `CARTS/tests/`, `fpga/tools/glass_shelf.py` SHELF
lists it) on the first glass since power-on, then powers KOS on. It ends when the cart asks to leave at 8.47 s (a
request before `MIN_MS` 8 s is held), on a key or pad button (swallowed), a trap, or `CAP_MS` 12 s. The sample is
the cart's own `samplePlay`, which the board's firmware hands to BARD.

On the card (26 Nov): `KESTREL/glass` is this glass (md5 9ae1738a, built at b61a9538), the previous one kept as
`KESTREL/glass.pre-aurora` (md5 07b28ee6, WINDHOVER's splash); `CARTS/tests/demo-aurora_boot.zmd` is this cart's fat
disk (md5 dd3ac0b9, a lean cart for the card's `system.rv32`). Loaded with `glass ctl load` it ran 60.1-60.8 fps, 0
missed, `cart_c` 0.24-0.29 Mc, loaded in 2,349 ms, and asked to leave. **Not yet verified: a real power-on** (the
board did not come back on the network after `glass ctl reboot`, 26 Nov; it needs a power cycle), and the sound by
ear.

Ways back: `splash=0` in `KESTREL/glass.cfg` (no boot screen at all), or, on a PC, copy `KESTREL/glass.pre-aurora`
over `KESTREL/glass`.

## History: the variants (24-26 Nov)

Cart 161 first shipped variant **A** (a shared 256-entry palette of the aurora's difference, ZX0'd 8-bit index deltas
with a 2-level temporal hold, every other row, bitmap capitals). Matt saw "JPEG-like stains of colour around the
aurora", so carts 162-168 tried the causes one at a time on the board: **B** smooth light quantised on the float
value, **C** no temporal hold (the hold was the main culprit: neighbours froze at different moments), **D** every row,
**E** the faint halo's hue locked, **F** a palette per row, **G** no palette (the final 565 picture as 16-bit deltas),
the soft curtain base and the script name. Measured against the lab's float picture (dE mean / p99): E 2.75 / 8.5,
F 2.38 / 6.5, G 1.85 / 4.1. Matt picked G ("visually the best, no comparison"); it ran ~20 fps on the board under
ZX0, and became G2 (60 fps) with the change masks and the baked star plane, one-pixel stars and the smaller name.
On 26 Nov G2 became cart 161 and the boot; carts 162-165, 167 and 168 are retired (build.zig keeps their slots
empty, 166 is BAD APPLE). Their code, data, harness lines and the baker's palette, hold, halo and per-row paths are
gone (in git history up to the merge of `feat/aurora-boot`). The cart's look is unchanged by the move: the harness's
composite hashes of 161 equal G2's (`scene_hash.mjs`, 520 frames). The variants' board shots and crops stay local
(`prototypes/boot_screen/aurora_compare/`, `board_shots/`, `prototypes/aurora_f_re/`).

## Fidelity to the lab, and deviations

Close: same shader constants, camera, noise, march, ramp, bloom, ACES, gamma, same falcon, dots, flights and timeline.
Deviations:

- **Edge sharpness 0.15** and the **script name at 0.42** (above).
- **Photo resampling.** The lab uses the browser's canvas resize; PIL bicubic finds 237 stars over the whole height
  where the lab's JSON reports 254 (lanczos 282, bilinear 121, box 455). Same algorithm otherwise.
- **float32 sin** of numpy (not the GPU's) in the noise hash: rays differ in the fine grain, not in character.
- The lab's RGBA16F buffers are float32 here; the march uses each step's centre, not the per-pixel jitter.
- **Stars** are one pixel on an opaque ramp, not alpha-blended discs; **lines** are integer DDA, not antialiased
  strokes.
- **Sound** is a 22 kHz 8-bit mono reduction of the 48 kHz stereo master.

## Keys and flow

Space or R replays (the sky restored, the star plane emptied, the sound stopped and restarted); Esc leaves. K / P
(KESTREL / PEREGRINE) are a hook: only KESTREL is baked. During the power-on splash glass takes any key as "skip"
(it never reaches the cart).

## Re-baking

```
zig build                      # installs zig-out/bin/zx0pack
uv run --with numpy --with pillow python tools/boot/aurora_bake.py --cache prototypes/boot_screen/aurora_f/light_edge015.npz
./build.sh --only aurora_boot  # the harness reads the new aurora_ref.json: nothing is pinned by hand
```
Rendering the light takes ~3 min (the cache skips it: seconds). The wordmark font is local (`aurora_bake.FONT`; a
worktree passes the main checkout's with `--font`); a missing font is an error before anything renders, never a
blank name. `--frames N` renders N aurora frames plus the closing dark one (the tests use 2). Python tests:
`tools/tests/test_aurora_bake.py` (its end-to-end bake runs only where the font is), `test_aurora_direct.py`,
`test_aurora_g.py` (the masks and the baked star plane, the cart's loops mirrored in Python).

## Harness

`apps/harness/aurora_boot_check.mjs`: the cart's TC plane at 5 probed aurora frames equals the baker's reference
picture byte for byte, the sky at frame 10 and after the aurora, plane 1 at 4 probed frames is the baked one, every
baked star lit at the probed records, the wire only once the falcon forms, the baked name only from its beat, the
fade-in from black, TC_FADE 0 then 31, black + asks to leave at frame 508 and never before, ONE 8-bit sample at
frame 0 (the baker's bytes, its rate, never stopped, as long as the picture), and the replay key. `--break` runs 8
mutants (no fade-in, no sound, half speed, frozen, never leaves, a flipped bit in the aurora, no stars, no wire),
each caught. `scene_hash.mjs ... 520 30 --composite` runs the whole film with no `zg.mem` refusal.

## What is not done

PEREGRINE's stoop (the lab's `pose` has it; the baker would bake a second set and a key would switch them); the K / P
key; the sample's level and hiss judged by ear on the board.
