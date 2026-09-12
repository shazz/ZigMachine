# Reusable effects backlog (ZigOS)

Survey of every scene in `apps/zig/scenes/` (2026-09-12, read-only). The CODEF
ports keep re-implementing the same handful of mechanisms, mostly because the
existing `zg.Sprite` / `zg.Scrolltext` assume 320-wide targets, use u16 offsets
(a 400x280 plane is 112000 bytes) and trap on negative y. Line numbers are as of
the survey date.

Status: **#1–#3 shipped (2026-09-12)**: `zg.blit` (`libs/zig/effects/blit.zig`),
`zg.copper` (`libs/zig/effects/copper.zig`) and `LogicalFB.openBorders(.all | .top_bottom)`
plus `hblLinesArePhysical()`. They are documented in `docs/ZIGOS_API.md` §6 and tested in
`blit_test.zig` (12 tests) and `copper_test.zig` (5 tests). Two scenes are migrated, and each
renders byte-identically to before (SHA-256 over the full physical framebuffer):
- `replicants_garfield`: blit `.pattern` ink plus copper; 1200 consecutive frames.
- `ulm_spoon_distorter`: `openBorders(.all)` plus blit; every 10th frame of 6000.

The rest are proposals.

Correction to §2 below: the copper tables are **scene-owned**
(`var t: [n]zg.copper.Table = undefined;`), not library module-scope arrays. The
cart link materialises uninitialised module-scope arrays as zero bytes in the data
segment, `undefined` or not. Library-owned 4 planes × 4 slots × 280 u32 tables added
16.3 KB to every cart that used copper.

## Prioritised proposals

| # | API | Covers | Risk |
|---|-----|--------|------|
| 1 | `libs/zig/effects/blit.zig` — `Dst` view + clipped signed blits, comptime ink modes | noextra, supplex_fs2, replicants_garfield, replicants_dd2, ulm_spoon_distorter, union placement/runner/creditfont | Low |
| 2 | `libs/zig/effects/copper.zig` — per-line palette tables, one HBL, always-physical rows, optional flicker | replicants_garfield, supplex_fs2, dbug, union main, ics, stcs, bladerunners, deltaforce/2, ancool, fallen_angels | Low–Med |
| 3 | `LogicalFB.openBorders(.all / .top_bottom)` + `zg.flickerAllHbl` | noextra, supplex_fs2 (×3), ulm_spoon_distorter, fullscreen, union scroller/runner/placement | ~None |
| 4 | `libs/zig/effects/wave.zig` — `SineSum` (CODEF fxparam) + column/row-shifted blits (`siny`/`sinx`) | noextra, supplex_fs2, union scroller, replicants_garfield, replicants_dd2, fallen_angels, blitter_demo, ulm_spoon_distorter | Med (rounding) |
| 5 | `libs/zig/effects/scrollring.zig` — CODEF `scrolltext_horizontal` letter ring, fractional speed | noextra, supplex_fs2, replicants_garfield, scrolltext2/union | Low–Med |
| 6 | `libs/zig/effects/palette.zig` — scale/fade/cycle a range from a base palette; replaces broken `fade.zig` | noextra, union trsi/wab/placement/main | Low |
| 7 | `Spans` — comptime RLE of sparse overlays | replicants_dd2, replicants_garfield | Low |
| 8 | Small: `utils/tables.zig` (comptime prefix sums / run maps), `zg.applyDefaults(self)`, `apps/lib/headless.mjs` | ulm, dd2, every scene, 3 harnesses | Low |

Rule for every migration: **a scene's tables and numbers are passed in as data,
never changed**, and the scene's headless harness output must be byte-identical
before and after.

## 1. Clipped signed-coordinate indexed blit

Re-implemented in: `noextra.zig` (`blit`, `glyphColumn`), `supplex_fs2.zig`
(`drawGlyph`, `blitGlyphToStrip`), `union/placement.zig` (`blitRect`),
`union/runner.zig` (`blitFrame`, `blitStretch`), `union/creditfont.zig`
(`drawLine`), `replicants_garfield.zig` (`blitGlyph`, source-atop LUT),
`replicants_dd2.zig` (`copyRow`, mirror), `ulm_spoon_distorter.zig` (glyphs into
offscreen). Library-private copies: `tilemap.zig` `blitTile`, `zigos.zig`
`blitGlyphs`.

Proposed shape:
```zig
pub const Dst = struct { buf: []u8, stride: usize, w: i32, h: i32,
    pub fn plane(fb: *LogicalFB) Dst; pub fn buffer(buf: []u8, w: usize, h: usize) Dst; };
pub const Image = struct { data: []const u8, w: u16, h: u16 };
pub const Rect  = struct { x: u16, y: u16, w: u16, h: u16 };
pub const Ink = union(enum) { copy, flat: u8, offset: u8, lut: *const [256]u8,
    row: []const u8, pattern: struct { img: Image, ox: i32, oy: i32 } };
pub fn blit(dst: Dst, src: Image, part: ?Rect, dx: i32, dy: i32, key: ?u8, ink: Ink) void;
```
Clip once to a src/dst rectangle, inner loops with no per-pixel bounds tests,
ink mode dispatched outside the loop. Pure functions, no state.

## 2. Per-line palette rasters ("copper")

Re-implemented in 14 scenes: `replicants_garfield` (entries 0 and 7),
`supplex_fs2` (160 entries rewritten per frame, no HBL), `dbug` (7, physical,
shares flicker handler), `union/main` (0, `SKY[line]`), `ics`, `stcs` (three
handlers, one calling `setPalette` of 256 entries per scanline), `bladerunners`,
`deltaforce`, `deltaforce2`, `ancool`, `fallen_angels`, `replicants` (REPS OLD),
`music_debug`. They differ in entry(ies), line window and out-of-window rule
(wrap/clamp/hold/blank), scrolling, global vs per-plane handler, and whether the
handler also flickers the border.

Proposed shape: `install(fb, .{ .entries, .flicker })`, `table(fb, slot)` →
`*[280]u32` indexed by **physical** row, `fillGradient(...)`, a global-handler
variant. State lives in module-scope library tables (zero-filled, no data
segment); the handler maps `line` to a physical row from the plane's mode, which
removes the logical/physical trap by construction.

## 3. Overscan setup boilerplate

Identical `fn handler(fb…) { fb.flickerBorder(); }` +
`setOverscanBuffer()` + `setFrameBufferHBLHandler(OVERSCAN_MAGIC_X, …)` in
noextra, supplex_fs2 (three times), ulm_spoon_distorter, fullscreen,
union/scroller, union/runner, union/placement. Variants combined with rasters
(dbug, union/main, music_debug) move to `copper.install(.{ .flicker = true })`;
top/bottom-only in maxi.

## 4–8

- **wave.zig**: column displacement in noextra (1 term, trunc), supplex_fs2
  (2 terms), union/scroller (1 term, 3-px columns, round); row displacement in
  noextra (2 terms, 16.16 zoom), replicants_garfield (f64, floor), replicants_dd2,
  fallen_angels (8-row bands), blitter_demo, ulm_spoon_distorter (tiled). Float
  type, rounding, column grouping and phase origin must be parameters.
- **scrollring.zig**: noextra (15 letters, 4.5 px), supplex_fs2 (22, 2 px),
  replicants_garfield (integer quarter-pixels). `scrolltext2` can't express
  fractional speed and starts slots on screen (union pads 13 spaces).
- **palette.zig**: noextra, union trsi/wab/placement/credits/main. `fade.zig`
  does not compile if used (`RenderTarget` has no palette methods).
- **Spans**: replicants_dd2 (flat span list), replicants_garfield (per-row index).
- **Small**: prefix sums (ulm, dd2 check; not equinox's `road_sum`, which is not
  a true prefix sum), ping-pong bounce (reversal rules differ per scene, so low
  value), `applyDefaults`, shared headless harness module.
- **Already covered, no API needed:** D-BUG's text reveal (`charpanel.zig`),
  tile/parallax (`tilemap`, `parallax`), bob curves (too little shared code).

## Incidental bugs found (not fixed)

1. **Dangling stack pointers**: `init()` stores `&render_buffer` of a local /
   slices a local buffer in `dbug.zig`, `ics.zig`, `stcs.zig`,
   `fallen_angels.zig`, `deltaforce2.zig` (`bladerunners.zig` already fixed it).
2. **HBL numbering**: `fallen_angels.zig` and `ancool.zig` test physical ranges
   (40..240) in normal-plane handlers — raster shifted 40 rows, stale bottom.
   Same in REPS OLD (`replicants.zig`), kept as-is for comparison.
3. **Out-of-bounds read**: `fallen_angels.zig` buffer 640×7 but RenderBuffer
   claims `height = HEIGHT`.
4. **Size mismatch**: `deltaforce2.zig` buffer 20480 bytes, claims 320×66.
5. **Negative-y Sprite**: `ics.zig` grid sprite y in [-32, -1].
6. **`zg.Fade` does not compile** if used.
7. **`self.* = .{}` on large structs**: `union_intro.zig` (whole Demo),
   `union/doors.zig`, smaller in trsi/wab/dragonball.
8. **`std.debug.assert` as a runtime guard**: `charpanel.zig`.
9. **Performance**: `stcs.zig` `setPalette` per scanline; `supplex_fs2.zig`
   3 overscan planes + per-pixel strip blit; equinox and tex use 4 planes.
10. **Duplicate write**: `stcs.zig` same pixel written twice.
11. **Bitwise index masking** (`fb & mask` on palette indices): `tex.zig`,
    `replicants.zig`.

## ZX0 container & depack effects

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
| 5 | 1 | fx: `0` none, `1` rasters, `2` bar, `3` text, `4` fade, `5` noise |
| 6 | 4 | depacked length, u32 little-endian |
| 10 | 1 | text length n, 1..40 (**only** when fx = text) |
| 11 | n | message, printable ASCII (**only** when fx = text) |
| … | … | ZX0 v2 stream (absent when the length is 0) |

Contract: the packer rejects an unknown effect, a missing, over-long or
non-printable message, and a message with any effect but `text`. The depacker
answers **null** on an unknown version or fx, or a malformed message, never
falling back to "no effect". Plain `zx0.depack(image, dst)` ignores fx and just
returns the data.

### CLI

```sh
zx0pack [--fx none|rasters|bar|text|fade|noise] [--text "MESSAGE"] <in> <out>  # packs, verifies, writes
zx0pack [--fx F] [--text MSG] [--stats] [--force] --pairs <in> <out> [<in> <out>...]
zx0pack [--stats] [--force] --manifest <file>    # lines: in TAB out [TAB fx [TAB text]], '#' comments
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
