# `rtl/video/`: the video compositor in Verilog

`zm_video_comp` builds the machine's 800×280 raster a line at a time, as
`machine/video.zig` builds the PFB, and is checked pixel for pixel against the
wasm machine on real carts' frames and on synthetic frames the real
`machine-video` renders. `zm_video_mix` folds each pass into the picture the
browser shows, `zm_video_out` adds the display buffers, timing and scanout, and
`zm_dvi_out` puts it on HDMI (below, "The picture"). `zm_vtiming`, `zm_tmds_enc`
and `zm_video_sync` are documented in their headers.

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
| Commands | `cmd_valid`, `cmd_ready`, `cmd_op`, `cmd_plane`, `cmd_line`, `cmd_mix`, `cmd_last`, `pass_done` | A command is taken when `cmd_valid && cmd_ready`. `pass_done` pulses at the end of a `BG` or `PLANE` pass. `cmd_mix`: fold the pass into the picture; `cmd_last`: the line's last pass. |
| **Memory read** | `mem_req_valid/ready/addr`, `mem_rsp_valid/data` | See below. |
| Line buffer read | `lb_raddr[8:0]` → `lb_rdata[63:0]` (next clock) | Pair `x`: raster pixel `2x` (low half), `2x+1` (high). The PFB row, for tests; the mixer owns the port while `mix_busy`. |
| Display | `dp_clk`, `dp_raddr` = {buffer, pair} → `dp_rdata[47:0]`, `dp_free[1:0]`, `line_ready`, `ready_line` | The picture, 2 × RGB a read, in the scanout's clock. A line's last sweep waits for `dp_free[line[0]]`. |
| Status | `overflow`, `mix_hazard` | Sticky. A line needed more than 256 words (a fullscreen stride above 1021); the line buffer was rewritten before the sweep read it. |

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
| `zm_video_mix.v` | The plane mixer: sweeps, the accumulator line, the two display buffers. |
| `zm_video_dcram.v` | A RAM with a clock per port: the display buffers' clock crossing. |
| `zm_video_out.v` | Compositor + `zm_vtiming` + scanout, two clock domains, buffer hand-over. |
| `zm_video_scan.v`, `zm_video_sync.v` | The scanout; a toggle pulse synchroniser. |
| `zm_tmds_enc.v`, `zm_dvi_out.v` | One TMDS channel; DVI out (3 encoders, OSERDESE2 10:1, OBUFDS). Board only. |
| `zm_video_memmap.vh` | Includes `gen/memmap.vh` once per module. The generated include guard would otherwise give the constants to the first module only. |

## How it is tested

Recorded frames replayed through the RTL, pass by pass, line by line and on the
wire, with break tests: see [`TESTING.md`](TESTING.md), with the coverage table.

## The picture: mixer, scanout, DVI

**What the browser shows** (`docs/sealed-loader.js`, `docs/css/crt.css`): canvas
`i` holds the PFB after `hwRenderPlane(i)` for each enabled plane (the cleared
PFB on canvas 0 when none is), stacked in DOM order on the tube's `#121010`.
Chrome's software compositor gives, per canvas: `P = round(c·a/255)` (the
premultiply in `putImageData`), then `D = P + (D·(256−a) >> 8)`. That is exact on
all 65,536 colour × alpha pairs and on random 4-canvas stacks, checked against
headless Chrome screenshots (`tools/mix_chrome.mjs`; the cosmetic CRT veil is
left out). A GPU compositor rounds partial alpha differently, by up to 4.

**The mixer** sweeps the line buffer after every `cmd_mix` pass, 2 pixels a
clock (400 clocks), `D = over(L, D)` with 12 multipliers (DSPs), from the tube on
the first sweep of a line. Canvas `k` re-shows lower planes' pixels it does not
cover, so each sweep covers the whole line. The sweep starts the clock after its
pass and runs while the next pass fetches and paints; both go from low pairs up
at ≤ 1 pair a clock, so it is never overtaken (`mix_hazard` checks).

**Scanout** (`zm_video_out`): the compositor runs in its own clock (the SoC's
`sys`), the timing and scanout in the 40 MHz pixel clock. Line `y` goes to
display buffer `y[0]`; the scanout frees it at the next HBL and shows a line only
if its buffer holds that line, else black and `underrun`. The compositor stalls
by itself when both buffers are full.

**Throughput**, worst line, busy clocks with sweeps overlapped (`--timing`):
corpus carts at most 2,099 (`union_main`); synthetic `medium` 3,197, `alpha`
3,124; `worst` (4 medium planes of 800 columns 1:1 over 64 BEAM writes) 5,060. A
raster line is 2,112 pixel clocks: 4,224 compositor clocks at 80 MHz (`worst`
underruns, by test), 5,280 at 100 MHz (4 % margin), 7,920 at 150 MHz (36 %).

### What remains before a bitstream

- **The sequencer.** Something must issue the passes and run the HBL handlers.
  `tools/video_order_shelf.py` (2026-10-02, frame 300 of 90 carts, every one
  pixel-identical through the RTL in the machine's order): under line-major
  order only two change. `badflicker`: the overscan noise seed is `FRAME`, which
  the machine bumps at the end of `hwClear`, before planes latch (fix: count the
  frame at VBL). `equinox`: four overscan planes share `RES_FLICKER`, so one
  plane sees another's flicker (160 pixels).
- **frame() runs while the beam scans** on hardware; the machine runs it before
  any plane pass. Its writes to live state (palettes, `BACKGROUND`) land mid-frame.
- **AXI** (`soc/zm_video_pipe.py` fetches over Wishbone, one word at a time) and
  DDR; **openXC7's chipdb**; **timing closure** (no place and route yet).

## Cost (Yosys `synth_xilinx`, xc7, before place and route; `make -C fpga util`)

| Block | LUT | % of 7010 | FF | CARRY4 | BRAM | LUTRAM | DSP |
|---|---|---|---|---|---|---|---|
| `zm_video_comp` (with the mixer) | 1,378 | 7.8 % | 1,158 | 152 | 8 | 25 | 13 |
| `zm_video_out` (+ scanout, timing) | 1,492 | 8.5 % | 1,325 | 162 | 8 | 25 | 13 |
| `zm_tmds_enc` (one channel) | 52 | 0.3 % | 28 | 7 | 0 | 0 | 0 |
| whole z7 SoC with video + DVI (`tools/soc_util.py`) | 4,069 | 23.1 % | 3,345 | 332 | 35 | 33 | 17 |

The mixer adds 209 LUTs, 4 BRAM (accumulator line, 2 display buffers) and 12 DSPs.
