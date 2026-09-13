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
