# ZX0 container & depack effects

Carts can embed assets packed with ZX0 (Einar Saukas's optimal LZ77 format,
v2, BSD-3; written from the format description) and unpack them at run time,
with an effect on screen while they do. Code: `libs/zig/depackers/zx0.zig`
(depacker, container), `zx0_pack.zig` (packer), `depack_fx.zig` (effects),
`tools/zx0pack/main.zig` (CLI). Tests: `zx0_test.zig`, `depack_fx.zig`, both in
`build.sh`.

### Container, version 1

| offset | size | field |
|---|---|---|
| 0 | 4 | magic `ZX0!` |
| 4 | 1 | version, `1` |
| 5 | 1 | fx: `0` none, `1` rasters, `2` bar, `3` text, `4` fade, `5` noise, `6` automation, `7` tex_loader |
| 6 | 4 | depacked length, u32 little-endian |
| 10 | 1 | text length n, 1..40 (**only** when fx = text) |
| 11 | n | message, printable ASCII (**only** when fx = text) |
| 10 | 1 | bar height, AtariDecrunch's MaxBarHeight 0..255 (**only** when fx = automation) |
| 10 | 1 | panel columns c, 1..30 (**only** when fx = tex_loader) |
| 11 | 1 | panel rows r, 1..24 (**only** when fx = tex_loader) |
| 12 | c×r | the panel row by row, chars `' '`..`'['` (the loader font; no lowercase) (**only** when fx = tex_loader) |
| … | … | ZX0 v2 stream (absent when the length is 0) |

Contract: the packer rejects an unknown effect, a missing, over-long or
non-printable message, and a message with any effect but `text`. It also rejects
`automation` without a bar height, and a bar height with any other effect, and
likewise `tex_loader` without a panel, a panel with any other effect, a panel of
0 or more than 30 columns or 24 rows, ragged rows, or a char outside the font. The depacker
answers **null** on an unknown version or fx, a malformed message, a missing bar height or a
missing, misshapen, truncated or out-of-font panel, never
falling back to "no effect". Plain `zx0.depack(image, dst)` ignores fx and just
returns the data.

### CLI

```sh
zx0pack [--fx none|rasters|bar|text|fade|noise|automation|tex_loader] [--text "MESSAGE"] [--bars N] [--panel FILE] <in> <out>  # packs, verifies, writes
zx0pack [--fx F] [--text MSG] [--bars N] [--panel FILE] [--stats] [--force] --pairs <in> <out> [<in> <out>...]
zx0pack [--stats] [--force] --manifest <file>    # lines: in TAB out [TAB fx [TAB text|bars|panel file]], '#' comments
zx0pack -m <file>...                                                           # measure: raw packed path
```

Batch modes skip any output newer than its input (`--force` repacks; the check
is by file time, so after changing a manifest line's fx or text use `--force`).
They keep going past a failure, print `zx0pack: <file>: <error>`, and exit 1 at
the end if anything failed. `--stats` prints one aligned line per file (name,
raw, packed, ratio, pack ms, or "up to date") and a TOTAL line.

### Runtime

`zx0.Stream` is resumable: `step(max_bytes)` returns `.more / .done / .failed`,
and any budget gives exactly the one-shot bytes. `depack_fx.Runner(zg, tvnoise)`
reads fx and drives it: pass `@import("zigos")`, plus `@import("tvnoise")` or
`null`. Without tvnoise, a `noise` image is refused at `start`, before anything
is touched. Call `start(zigos, image, dst, bytes_per_line)` once, then
`frame(zigos)` every frame until it stops answering `.more`. It restores the
background colour, the global HBL handler, plane enable flags and plane 0's
palette entries 0..15.

| fx | what it does |
|---|---|
| rasters | global HBL depacks `bytes_per_line` bytes per physical line and loads colour 0 from the data, so the stripes are the depack |
| bar | 240×8 bar on plane 0 fills with written / total |
| text | the container's message, 8×8 system font, centred |
| fade | background steps $777 → $000 in 8 ST levels, black exactly at the last byte |
| noise | `libs/zig/tvnoise` snow on plane 0 (ramp at entries 8..15), redrawn every frame for as long as the depack runs; tvnoise takes no progress input, so the snow does not change with progress |
| automation | the Automation Packer v2.3r depack screen from CODEF's `AtariDecrunch`: random bars in its 12 colours over the whole plane, the Automation logo and the busy bee on top, redrawn every frame until the data is ready |
| tex_loader | the Union Demo's TEX loader: the header's text panel assembles letter by letter in the loader font, the last letter landing with the last byte (`libs/zig/depackers/tex_loader.zig`) |

**tex_loader**, what is authentic and what is adapted. Source: shazz's melonJS
remake `Union-Demo-HTML5-Remake-0.9.8`, `loader.js` (the `TEXLoader` base
class), panels in `menuloader.js` and `screens/*/loader.js`. Kept: the black
screen; the `loader.png` font (60 16×16 tiles from `' '`, one colour `#C0A000`),
halved to 8×8 with no pixel lost because every glyph is pixel-doubled (12 on an
odd phase, each sampled at its own; `tex_loader/loader.raw`, 480 bytes of rows in
the cart); the cells of `resetScroller` halved (top-left x = 80 + 8·col, bottom
row at y 184, rows stacked upward); the letter order (column by column, bottom
row first in each column); each letter's linear 50 ms flight from y 500 (246
halved, below the window), letter k starting at 30·k ms. Adapted: the JS clock
was `Tween.tick(140)` per frame, so the 23×20 main menu panel took 13,820 ms =
99 frames; here the clock is `written / total` of that timeline, so the panel is
the progress display and ends on the frame the data is ready (at 7 bytes per
physical line a 196 KB asset takes 101 frames, the remake's pace). The panel is a
header payload (`--panel FILE`: one `"quoted"` row per line, all the same width,
so trailing spaces survive editors); widths differ per screen (18..25 columns,
always 23 rows). Tiles `# * + ; < = > ? @ [` are blank in `loader.png` and draw
nothing. The loader's music, `zik_loader` (`data/music/zik_loader.ogg`, a 44.1 kHz
Vorbis stream the remake plays on the demo screens' loaders; `menuloader.js` has
it commented out), is not part of the effect. Plane-0 entry 1 is the ink, restored
afterwards. On a 400×280 plane the panel sits in the 320×200 window at (40,40).
`apps/tex_loader_fx_headless.mjs` packs a real asset with the main menu's panel
(`apps/zig/assets/screens/union_demo/loader_main_menu.txt`), runs it on the sealed
machine, shoots start/middle/end and checks the depacked bytes. The first screen
to ship behind it is the Union Demo's TCB3 MULTIFAKE (`union_multifake`): its
pictures (156,511 bytes) are packed with `screens/multifake/loader.js`'s panel in
`build.zig` and depack at 6 bytes a line, 94 frames
(`apps/union_multifake_headless.mjs`). DELTA FORCE (`union_deltaforce`) followed:
186,774 bytes behind `screens/deltaforce/loader.js`'s 19-column panel, 7 bytes a line,
96 frames (`apps/union_deltaforce_headless.mjs`). TCB2's WOW!-SCROLLER (`union_superscroller`)
does the same with `screens/superscroller/loader.js`'s panel: 140,601 bytes at 5 a
line, 101 frames (`apps/union_superscroller_headless.mjs`).

**automation**, what is authentic and what is adapted. It is the fake depack
screen that opened the Replicants' Kick Off 2 remake (CODEF screen 168,
`prototypes/codef/168/lib/codef_decrunch.js`, `AtariDecrunch(0, 100, 0, 200)`).
It used to be the first 200 frames of `replicants_kickoff2.zig`, and now runs
here, over a real depack. Elite Snooker (CODEF 422) calls the same function as
`AtariDecrunch(0, 30, 0, 100)`. The one argument that changes the look is
MaxBarHeight (168: 100, 422: 30), so it is **parameterised** as the header's bar
height (`--bars N`, required with this effect). DecrunchMaxVBL (200 / 100) is
replaced by the depack's own length. DType is 0 (Automation) and
StartDecrunchAt is 0 in both calls, and doDecrunch never reads StartDecrunchAt,
so neither is stored. Kept as in the JS: each frame draws
`tallest = 10 + round(rnd*MaxBarHeight)`, then bars `round(rnd*tallest)` canvas rows tall
in `palette[round(rnd*12)]`. When that index is 12, one past the palette, the
canvas keeps its last `fillStyle`, so the bar repeats the previous colour. It
also keeps the 12 `#a0....` colours, and the logo at canvas `(320 - w/2, 7)` and
the bee at `(320, 50)`, halved and inked black. The two masks are the scene's
old assets (`libs/zig/depackers/automation/*.raw`, cut from the JS's base64
PNGs), packed to bits at compile time: 214 bytes. Adapted: the remake ran a
fixed 200 frames on a 320×240 canvas. Here the effect lasts exactly as long as
the depack and fills the plane (320×200, or 400×280 with the logo placed from
the 320×200 window at (40,40)). One plane row is drawn per two canvas rows of a
canvas twice the plane's height. `Math.random` is xorshift64*, seeded as the
scene was, so the bars do not change with progress. Palette entries 1 (ink) and
3..14 (bars) of plane 0 are used, and restored afterwards.

The rasters follow Jampack 4.0's `DEPICE.S:55` (`MOVE.W D7,$FFFF8240` with the
packed byte on each bit-buffer reload). Unverified: D7's upper byte (red) is
taken as 0. Colour 0 is sampled once per scanline, where a real ST also shows
mid-line writes.

### Numbers (2026-09-12, all 219 files under `apps/zig/assets/`)

| | bytes | of raw |
|---|---|---|
| raw | 5,819,500 | 100% |
| **zx0** | **2,229,412** | **38.3%** |
| gzip -9 | 2,142,589 | 36.8% |
| xz -9e | 1,909,012 | 32.8% |

It packs everything in 14.6 s and depacks natively at ~880 MB/s (0.21 ms for
the 196 KB TRSI animation, which packs to 7,397 bytes). Already-compressed
audio (`smp/music1`, `.mod` samples) does not shrink; leave those unpacked.

### Pilot: `union_intro` (TRSI turn animation, fx = rasters)

`build.zig` builds `zx0pack` for the host and packs
`screens/union_intro/trsi_turn.raw` with `--fx rasters` into a generated
`packed_assets` module. `union_intro.zig` depacks it at 8 bytes per physical
line (about 1.5 s of stripes) before the TRSI part starts. If there is no room,
the image is unreadable or the depack fails, it logs and skips the part.

| | before | after |
|---|---|---|
| `docs/demo-union_intro.wasm` | 1,168,019 | 983,624 (−15.8%) |
| `docs/demo-union_intro.zmd` | 1,169,920 | 985,600 |
| RAM window used (check_fits) | 1483 KB | 1299 KB |

The depack target is taken from **free cart RAM** (`hwRamBase + hwRamUsed`,
gated on `hwRamFree`), not a static buffer. With imported memory, the linker
writes `.bss` out as an explicit zero data segment. A static 196 KB buffer made
the first attempt *bigger* (+11 KB). At run time the depack borrows 196 KB of
the 749 KB free; `check_fits` does not see that.
