# `rtl/video/`: the video compositor in Verilog

`zm_video_comp` builds the machine's 800×280 raster a line at a time, as
`machine/video.zig` builds the PFB, and is checked pixel for pixel against the
wasm machine on real carts' frames and on synthetic frames the real
`machine-video` renders. (`zm_vtiming` is documented in its own header.)

## The model: one line, several passes

`video.zig` renders plane-major. `hwClear()` paints all 280 lines of background,
then `hwRenderPlane(p)` composites plane `p` over all of them, with the HBL
handlers running inside each loop. Hardware renders line-major. The compositor
reconciles the two by working in **passes over one line**, each started by a
command:

| `cmd_op` | Pass | `video.zig` equivalent |
|---|---|---|
| 0 `BG` | paint the line from `BACKGROUND`, or in spans from the BEAM table | one line of `clear()` |
| 1 `PLANE` | composite plane `cmd_plane` over what is already in the line buffer | one line of `renderPlane*` |
| 2 `LATCH` | latch plane `cmd_plane`'s frame registers (one clock) | the top of `renderPlane*` |

After the `BG` pass and the `PLANE` passes of enabled planes 0..p, the line
buffer equals row `cmd_line` of the PFB as the machine leaves it after
`hwRenderPlane(p)`. That PFB is what `scene_hash.mjs` and the native host hash.

The HBL handlers run **between passes**. Whatever issues the commands (the
testbench today, an HBL sequencer and the cart CPU on the board) lets the CPU
write registers and palettes through the CPU port before it starts the next
pass. The compositor reads what it needs live, at the start of each pass.

**What is latched and what is live** follows `video.zig` exactly, because the
pictures depend on it:

- **Latched per plane, per frame** (`zm_video_latch.v`, the `LATCH` command):
  `FB_MODE`, `FB_BASE`, `FB_STRIDE`, `FB_HBL_POS`, `HSCROLL` (used by
  fullscreen only), the `FRAME` counter (the overscan noise seed), and the
  overscan state (the last `RES_FLICKER` seen, and whether each band is open).
  On an ST the screen base is latched at VBL in the same way.
- **Live, per pass:** the palettes, `HSCROLL` in scroll mode, `RESOLUTION` in
  medium mode, `RES_FLICKER`, `BACKGROUND` and `BEAM_COUNT` with its table.
- **Written back by the compositor**, as `video.zig` writes them to memory:
  `BACKGROUND` (a BEAM line's last colour, because colour 0 keeps its value into
  the next line on an ST), `BEAM_DROPPED += drops`, `BEAM_COUNT = 0`, and
  `FRAME + 1` after background line 279.

### Plane modes (`zm_video_plane.v`)

| Mode | Lines | Source row | Columns | Into the raster |
|---|---|---|---|---|
| normal | 40..239 | `py - 40` | 320 | doubled, from x 80 |
| scroll | 40..239 | `py - 40`, plus live `HSCROLL` | 320 | doubled, from x 80 |
| fullscreen | 0..279 | `py`, byte `(c + hs) % stride` | 400 | doubled, from x 0 |
| overscan | 0..279 | `py` | 400 | doubled, borders earned (below) |
| medium | 40..239 | `py - 40` | 640 1:1, or 320 doubled | from x 80 |
| medium, stride ≥ 800 | 0..279 | `py` | 800 1:1, or 400 doubled | from x 0 |

Any other `FB_MODE` value is fullscreen when the stride is 400 and normal
otherwise, as in `video.zig`. A medium line is 1:1 when `RESOLUTION` is
`RES_MEDIUM` and doubled otherwise.

**Overscan:** a line *flickered* when `RES_FLICKER` differs from the value the
plane last saw, and it *hit* when the plane's HBL position is within
`OVERSCAN_X_TOL` of `OVERSCAN_MAGIC_X`. A hit in a border band opens that band
for the rest of the frame. A hit on a visible line opens that line's sides. A
flicker that misses paints noise palette indices `(x*37 + y*101 + seed*7) & 255`.

**BEAM** (`zm_video_bg.v`) applies `machine/beam.zig`'s rules one for one: x
snaps down to `BEAM_GRID`; a write is dropped if x ≥ 400 or it lands less than
`BEAM_MIN_GAP` after the last accepted write; only the first `BEAM_MAX` entries
are read; and every rejected or excess entry is counted.

## Ports

| Port | Signals | Contract |
|---|---|---|
| CPU write | `cpu_we`, `cpu_waddr[20:0]` (region byte offset / 4), `cpu_be`, `cpu_wdata` | Decodes the register block (`0x00..0x7F`), the four palettes (`OFF_PAL`) and the BEAM table (`OFF_BEAM_TABLE`). Other addresses are ignored. |
| Register read | `cpu_rword[4:0]` → `cpu_rdata` (combinational) | Only the words the compositor stores. The rest read 0. |
| Commands | `cmd_valid`, `cmd_ready`, `cmd_op`, `cmd_plane`, `cmd_line`, `pass_done` | A command is taken when `cmd_valid && cmd_ready`. `pass_done` pulses at the end of a `BG` or `PLANE` pass. |
| **Memory read** | `mem_req_valid/ready/addr`, `mem_rsp_valid/data` | See below. |
| Line buffer read | `lb_raddr[8:0]` → `lb_rdata[63:0]` (next clock) | Pair `x`: raster pixel `2x` in the low half and `2x+1` in the high half. This is the scanout's port. |
| Status | `overflow` | Sticky. A line needed more than 256 words, which only a fullscreen stride above 1021 does. |

**The memory read port** (`zm_video_fetch.v`) is the only way the compositor
reaches memory, and is shaped so it can sit behind an AXI HP master to DDR
unchanged:

- A **request** is taken when `mem_req_valid && mem_req_ready`; its address is a
  word-aligned byte offset from `HW_VIDEO_BASE`.
- Each request gets one **response** (`mem_rsp_valid`, 32-bit little-endian
  `mem_rsp_data`), **in request order**, any number of clocks later, with no
  back-pressure (the fetch buffer has room for every word asked). Several may be
  outstanding: AR = request, R = response with one ID, RREADY tied high.

Lines start at any byte (`FB_BASE`, `row * stride` and `HSCROLL` are byte
granular): the fetcher reads the covering words, the painter selects bytes. The
testbench answers after 1 to 8 random clocks and refuses a random quarter.

## Files

| File | What |
|---|---|
| `zm_video_comp.v` | Top level: address decode, command sequencing, RAMs, the background and plane paths. |
| `zm_video_regs.v` | Register block (the words the compositor reads), the CPU read-back, and the write-backs. |
| `zm_video_bg.v` | Background pass: `BACKGROUND` fill, or BEAM spans. |
| `zm_video_planepath.v` | Wiring: latch → geometry → fetch → painter. |
| `zm_video_latch.v` | Per-plane frame latches and the overscan state. |
| `zm_video_plane.v` | One plane pass: per-mode geometry, overscan decisions, `hs % stride`. |
| `zm_video_fetch.v` | The memory read port and the fetch buffer writer. |
| `zm_video_paint.v` | The 3-stage painter: fetch buffer → palette → line buffer. |
| `zm_video_sdpram.v` | Simple dual-port RAM with byte enables. Infers BRAM or LUTRAM. |
| `zm_video_memmap.vh` | Includes `gen/memmap.vh` once per module. The generated include guard would otherwise give the constants to the first module only. |

## How it is tested

```sh
uv run pytest -q tests/test_rtl_video.py                   # the replays and oracle checks, ~1 min
ZM_RTL_BREAK=1 uv run pytest -q tests/test_rtl_video.py    # + the 25 break tests, ~5 min more
uv run python tools/video_dump.py tutorial 300             # record frames of a cart
uv run python tools/video_dump.py --synth beam             # record a synthetic scenario
uv run python tools/video_rtl.py build/vdump/tutorial/frames 300   # replay (video_cover.py: coverage)
```

1. **Record.** `tools/video_dump/vdump` is the native host (`fpga/host/`'s
   machine, ROM and cart objects) plus a recorder. Every `hblDispatch` and every
   pass is bracketed by a delta record of the registers, palettes and BEAM table;
   it saves the memory the fetcher reads and the PFB after `hwClear` and after
   each enabled plane. `vsynth` is the same recorder around `machine-video`
   alone, programmed by C scenarios (`vsynth_scen.c`), which reaches what no cart
   does. The machine still renders those frames.
2. **Replay.** `tests/tb/video_comp_tb.cpp` (CXXRTL) runs each line as BG +
   PLANE passes. Before a pass it writes, through the CPU port, each word that
   differs from what the machine held for that pass and line. After it, it
   compares all 800 pixels with the PFB row. The words the compositor writes
   itself are checked against the machine's next record, never overwritten unseen.
3. **The oracle is untouched:** every cart frame's dumped PFBs hash to what
   `fpga/host` reports for that frame.
4. **Each frame states what it exercises** (`video_cover.py`, from the records:
   modes, and the effects a handler actually changed), and fails if it stops.
5. **Break tests:** 25 one-rule mutations of the RTL (`tests/tb/video_mutants.json`),
   each with the dump that must catch it; a hung pass is reported, not waited
   on. Opt-in (`ZM_RTL_BREAK=1`, 25 testbench builds). All 25 caught on 2026-10-02.

### Coverage: proven or not yet

"Proven" means at least one replayed frame matches the machine pixel for pixel
in every pass, and a break test of that rule is caught.

| Mode or effect | Status | Evidence |
|---|---|---|
| normal mode, static palette | **proven** | `tutorial` 300, `union_intro` 100 |
| 2–4 planes layered over the background | **proven** | `union_main` (3 planes), `tcb_colorshock`, `union_l16`, synthetic `layers` (4 modes stacked) |
| fullscreen (`FB_MODE_FULLSCREEN`), fine scroll latched, odd stride, `hs > stride` | **proven, synthetic only** | synthetic `fullscreen`. ZigOS no longer sets mode 1, so no cart reaches it. |
| legacy fullscreen (mode 0, stride 400) | **proven, synthetic only** | synthetic `fullscreen`, plane 2 |
| overscan, borders opened on time | **proven** | `union_main`, `replicants_emlyn`, `gen4_3615`, `maxi`, `fullscreen` (cart) |
| overscan, mistimed flicker (noise) | **proven** | `badflicker`, synthetic `overscan` (late HBL, tolerance edge) |
| overscan with a wider buffer (stride 512) | **proven** | `tcb_colorshock`, synthetic `overscan` |
| scroll mode (pan by `FB_BASE`) | **proven** | `scroll` 300 |
| scroll mode, `HSCROLL` per line | **proven, synthetic only** | synthetic `scroll`, `layers`. `scroll_demo`'s distort needs a key press. |
| medium, `RESOLUTION` per line | **proven** | `res_switch`, synthetic `medium` (including `RES_TRUECOLOR`, which renders as low) |
| medium overscan (stride ≥ 800) | **proven** | `medium_overscan`, synthetic `medium` |
| palettes changed per line by HBL (copper, linepal) | **proven** | `replicants_emlyn`, `gen4_3615`, `tutorial`, every synthetic scenario |
| `BACKGROUND` changed per line | **proven** | synthetic `beam`, `layers`; `dhs_0pxl0reg` 900 |
| BEAM lines: snapping, gap and x drops, more than 64 entries, carry into `BACKGROUND` | **proven** | `dhs_0pxl0reg` 300 and 900 (a static picture), synthetic `beam` |
| unaligned `FB_BASE`, `FB_BASE`/`HSCROLL` rewritten mid-frame (must be ignored) | **proven, synthetic only** | every synthetic scenario |
| a fetch stalled by the memory port | **proven** | random `ready` and latency on every replay (`ignore_ready` break test) |
| HBL handlers that write VRAM mid-render | **not yet** | The replay serves the pre-render image. `vram_changed` is 0 on every corpus frame. |
| fullscreen stride > 1021 | **not supported** | flagged (`overflow`) and not drawn. The machine has no such limit. |

### What remains before the compositor drives a screen

- **Scanout:** a second line buffer (ping-pong, +2 RAMB18) read by `zm_vtiming`.
- **The final picture.** The browser stacks one canvas per enabled plane (the
  PFB after that plane) with alpha. The RTL reproduces each of those PFBs, but
  not the alpha stacking. A display mixer is needed: binary alpha is cheap,
  blending is not.
- **The sequencer.** Something must issue BG/LATCH/PLANE per line and raise the
  HBL interrupt before each pass. Line-major hardware differs from the machine's
  plane-major order when a plane-p handler reads what a plane-q handler writes
  on a later line, or what `frame()` writes between `hwClear` and the renders.
  The replay applies the machine's per-pass state, so it cannot see this: it is
  a question about the machine's semantics, not this RTL.
- **Throughput.** A raster line is 2 × 1056 = 2112 clocks at 40 MHz. Measured
  compose clocks for the worst line (stalling test memory): 858 for one low-res
  plane (`tutorial`), 2,081 for three (`union_main`, just fits), 2,632 to 2,818
  for four planes or three medium ones (synthetic `overscan`, `layers`,
  `medium`, does not fit). Passes run fetch-then-paint in sequence. A 2×
  compositor clock, or fetching the next plane during this one's paint, closes it.
- **AXI.** The port is AXI-shaped but not yet wrapped. There are no bursts: one
  word per request.
- **Timing closure.** Not attempted. There has been no place and route.

## Cost (Yosys `synth_xilinx`, xc7, before place and route; `make -C fpga util`)

| Block | LUT | % of 7010 | FF | CARRY4 | BRAM | LUTRAM | DSP |
|---|---|---|---|---|---|---|---|
| `zm_video_comp` | 1,169 | 6.6 % | 1,057 | 106 | 4 (3 RAMB18 + 1 RAMB36) | 25 | 1 |

The BRAMs are the palettes (4 × 256 × 32, one RAMB36), the line buffer (2 ×
512 × 32, two RAMB18) and the fetch buffer (256 × 32, one RAMB18). The BEAM
table and the latch slots are LUTRAM. The DSP computes `row * stride`.
