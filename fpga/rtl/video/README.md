# `rtl/video/`: the video compositor in Verilog

`zm_video_comp` builds the machine's 800×280 PFB and the browser's picture of it
in memory, in the machine's own order, as `machine/video.zig` builds the PFB,
and is checked pixel for pixel against the wasm machine on real carts' frames
and on synthetic frames the real `machine-video` renders. `zm_video_out` adds
the double-buffered picture, the scanout fetch, the timing and the scanout, and
`zm_dvi_out` puts it on HDMI. `zm_vtiming`, `zm_tmds_enc` and `zm_video_sync`
are documented in their headers. The architecture is the ADR of 2026-10-02 in
`decisions.md` (Fable #1): **composite each frame into a frame buffer at the
compositor's speed, in the machine's order, and scan out the previous one.**

## The model: the machine's order, a pass at a time

`video.zig` renders plane-major: `hwClear()` paints all 280 lines of background
with the global HBL handler before each, then `cart.frame()` runs, then
`hwRenderPlane(p)` composites plane `p` over all 280 lines with its handler
before each. The compositor does exactly that, a **pass** over one line at a
time, each started by a command (`zm_video_pass.v`):

| `cmd_op` | Pass | `video.zig` equivalent |
|---|---|---|
| 0 `BG` | paint the line from `BACKGROUND` or the BEAM table, store it to the PFB row | one line of `clear()` |
| 1 `PLANE` | load the PFB row, composite plane `cmd_plane`, fold it into the picture, store both | one line of `renderPlane*` |
| 2 `LATCH` | latch plane `cmd_plane`'s frame registers (one clock) | the top of `renderPlane*` |
| 3 `MIX` | load the PFB row and fold it into the picture (no plane is enabled) | the loader showing the cleared PFB |
| 4 `PRESENT` | the picture is complete: show it from the next VBL | the browser's frame |

Between passes over a line every other line has been through, so the line
lives in memory: the **PFB rows go back to the region**, where the machine keeps
its PFB (`OFF_PFB`), and after plane `p`'s passes the region holds exactly the
PFB `scene_hash.mjs` hashes after `hwRenderPlane(p)`. The **picture** (the
browser's stacked canvases, `zm_video_mix.v`) is a second frame buffer of
`{0, B, G, R}` words, one of two (below).

The HBL handlers run **between passes, as plain calls** made by the sequencer,
the cart CPU's firmware (`fpga/cycles/vseq.c`; why firmware, not an FSM: below).
A pass reads every register and palette entry it needs after it is taken, and
`painted` says when it has: the next handler may run from then on, while the
pass mixes and stores. Nothing races the beam: the compositor has no deadline.

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
  `FRAME + 1` after background line 279. The sequencer copies them from the
  compositor's read-back into the region before the next handler runs, so they
  land where the cart reads them.

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

## The sequencer: the cart CPU's firmware

`fpga/cycles/vseq.c`, on the cart CPU (the ROM's side on the board): per frame
`vseq_clear` (gid read once; per line the global handler, then a BG pass, then
the write-back copy), `cart.frame()`, `vseq_plane` per enabled plane (mode,
stride, handler id and position read once; LATCH; per line the plane's handler
with video.zig's line numbering, logical 0..199 or physical 0..279, then a PLANE
pass), `vseq_present`. Firmware rather than a hardware FSM because the order
is decided by registers the cart writes (`GLOBAL_HBL_ID`, `FB_MODE`, `FB_STRIDE`,
`FB_HBL_ID`), the handlers ARE cart code the CPU must call anyway, and the
copy-back of the write-backs is four stores: an FSM would duplicate
`renderPlane`'s mode dispatch in RTL and still have to interrupt the CPU per
line. It costs the CPU the waits (below).

**The drain rule (Fable #5).** A handler's stores reach the compositor when they
leave the CPU's posted-write buffer, not when the handler returns. Before every
command the sequencer waits for `drained` (the snoop's queue and the store
buffer empty). The integration test's mutant `ZM_NO_DRAIN` skips that wait.

## The video region: snooped, not windowed (Fable #6)

The region stays ordinary memory in DDR at `HW_VIDEO_BASE` of the cart's linear
memory, so every load the cart or the ROM makes, unimplemented registers
included, reads what the wasm machine would: it is the machine's memory. The
compositor keeps copies of what it reads (register words, the 4 palettes, the
BEAM table) and learns every change by **snooping** the CPU's stores
(`soc/zm_video_snoop.py`; the D$ is write-through, so every store crosses the
bus). Framebuffers are not snooped: the compositor reads them from memory. The
old bus window is now read-only, the sequencer's read-back of the write-backs.

The snoop's tap is pipelined (`soc/zm_video_snoop.py`): the bus is registered,
then the window offset, then compared, and the queue's output is registered
before the compositor's decode. Under openXC7 (z7 glass SoC, `standard` core,
seed 1, `build/vprobe/`) the unregistered tap was the SoC's critical path at
79.4 MHz. Registering the tap gave 84.1 (the queue's read mux into the
compositor's decode was next); registering the queue's output too, 96.8 (the
`vbase` subtract was next); the offset stage as well, 92.83, with the critical
path in LiteX's bus-timeout counter into the bus `ack`, outside the video
(nextpnr's run-to-run spread is a few MHz). Then (`fpga/TIMING_FABLE.md` P1-4)
the queue's output became a register too, and the snoop decodes the region
itself: three select bits ({BEAM table, palettes, register block}) ride in the
queue word and `zm_video_comp` takes them (`cpu_sel`) instead of comparing
`cpu_waddr`. Four cycles of snoop latency in all, which the drain rule absorbs.

## Ports

| Port | Signals | Contract |
|---|---|---|
| CPU write (snoop) | `cpu_we`, `cpu_waddr[20:0]` (region byte offset / 4), `cpu_sel[2:0]`, `cpu_be`, `cpu_wdata` | `cpu_sel` = {BEAM table, palettes, register block}, decoded by the writer; a write with none set is ignored. |
| Register read | `cpu_rword[4:0]` → `cpu_rdata` (combinational) | The words the compositor stores (the write-backs). |
| Commands | `cmd_valid`, `cmd_ready`, `cmd_op[2:0]`, `cmd_plane`, `cmd_line`, `cmd_mix`, `cmd_first`, `painted`, `pass_done`, `present` | Taken when `cmd_valid && cmd_ready`; a `cmd_mix` command is held back while `d_ok` is low. `cmd_first`: the line's first fold of the frame (over the tube). |
| Addresses | `vbase` (bus address of region offset 0), `dbase` (the picture being built) | Bus byte addresses; rows are 8-byte aligned. |
| **Memory read** | `rd_req_valid/ready/addr/len`, `rd_rsp_valid/data[63:0]` | Bursts of 64-bit beats: below. |
| **Memory write** | `wr_req_valid/ready/addr/len`, `wr_dat_valid/ready/dat[63:0]`, `wr_busy` | A burst request, then `len` beats; a pass is done only when `wr_busy` falls. |
| Status | `overflow` | Sticky: a line needed more than 256 words (a fullscreen stride above 1021). |

**The memory ports** are the only way the compositor reaches memory, shaped as
AXI channels so they sit behind an HP master unchanged (`soc/zm_video_dma.py`
is that master; on the board it splits requests into 16-beat AXI bursts):

- A read **request** is a burst: a byte address (a multiple of 8) and a beat
  count, taken when `rd_req_valid && rd_req_ready`. Its beats come **in order**,
  any number of clocks apart, with no back-pressure. Plane lines are one burst
  covering `[addr & ~7, addr + nbytes)`; rows are 400 beats.
- A write burst is its request, then its beats on `wr_dat_*`; `wr_busy` stays
  up until the memory has taken (B-responded) all of them.

The testbench's memory accepts and answers on random clocks with 1 to 8 clocks
of latency (`tests/tb/video_mem.h`); `--timing` gives it a fixed latency instead.

## Files

| File | What |
|---|---|
| `zm_video_comp.v` | Top level: address decode, command taking, RAMs, the background and plane paths, the memory ports. |
| `zm_video_pass.v` | The phases of a BG / PLANE / MIX pass: load, paint, mix, store. |
| `zm_video_rowio.v` | Row I/O: PFB and picture rows in from memory, out through a skid buffer. |
| `zm_video_regs.v` | Register block (the words the compositor reads), the CPU read-back, and the write-backs. |
| `zm_video_bg.v` | Background pass: `BACKGROUND` fill, or BEAM spans. |
| `zm_video_planepath.v` | Wiring: latch → geometry → fetch → painter. |
| `zm_video_latch.v` | Per-plane frame latches and the overscan state. |
| `zm_video_plane.v` | One plane pass: per-mode geometry, overscan decisions, `hs % stride`. |
| `zm_video_fetch.v` | A plane line's fetch: one read burst into the fetch buffer (64-bit beats). |
| `zm_video_paint.v` | The 3-stage painter: fetch buffer → palette → line buffer. |
| `zm_video_sdpram.v` | Simple dual-port RAM with byte enables. Infers BRAM or LUTRAM. |
| `zm_video_mix.v` | The plane mixer: one sweep a pass, into the accumulator line (the picture's row). |
| `zm_video_scanfetch.v` | The scanout's fetch: the shown picture, a line ahead of the beam, into the display buffers. |
| `zm_video_dcram.v` | A RAM with a clock per port: the display buffers' clock crossing. |
| `zm_video_out.v` | Compositor + double buffer + scanout fetch + `zm_vtiming` + scanout, two clock domains. |
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

**The mixer** sweeps the line buffer once per PLANE (or MIX) pass, 2 pixels a
clock (400 clocks), `D = over(L, D)` with 12 multipliers (DSPs), from the tube
on the line's first fold of the frame (`cmd_first`), else from the picture row
loaded into the accumulator. Canvas `k` re-shows lower planes' pixels it does
not cover, so every pass folds the whole row: a PLANE pass runs on all 280
lines, painting only those the plane covers.

**The pictures** (`zm_video_out`): two frame buffers of 800×280 `{0, B, G, R}`
words (`fb0_base`, `fb1_base`, 875 KiB each). The compositor builds the back one;
PRESENT marks it complete and it becomes the front one at the next VBL. Until
then a pass that would write a picture is not taken (`d_ok`), so the shown
picture is never written: no tearing, one frame of latency, which the browser
has too. The sequencer reaches that wait only at the first PLANE pass, after the
next frame's background and `frame()`, so it overlaps the CPU's own work.

**Scanout** (`zm_video_scanfetch` + `zm_video_scan`): the fetch reads line `y`
of the front picture into display buffer `y[0]` once the scanout has freed it,
one 400-beat burst, and publishes it; at the VBL it samples the new front. The
scanout runs in the 40 MHz pixel clock and shows a line only if its buffer
holds that line, else black and `underrun` (sticky). A line is due a raster
line after its buffer frees: 2,112 pixel clocks, 7,920 sys clocks at 150 MHz,
for 400 beats. The DMA serves the scanout first.

**Throughput.** The compositor has no deadline; its time comes off the frame
budget the CPU also uses, because the CPU waits between passes. Busy clocks per
frame with a 24-clock first beat and a beat a clock (`--timing 24`, which also
counts the testbench's CPU-port writes): `tutorial` (1 plane) 0.73 M,
`dhs_0pxl0reg` (no plane, BEAM) 0.62 M, `union_main` (3 planes) 2.24 M,
synthetic `alpha` 2.75 M, `worst` (4 medium planes over BEAM) 3.52 M. A frame at
150 MHz is 2.5 M. A pass is about 1,000 clocks of row I/O (load 400 beats,
store 400 or 800) around its paint; the real carts' frames in the integration
test are below.

### Integration (Fable #9)

`tools/video_sim_run.py` (`make -C fpga video-sim`; TESTING.md item 6): the
cart CPU running the translated cart and the sequencer, this pipeline, and one
shared main RAM with the board's memory-path model in front of each master
(the CPU on `hp_sb`, the video DMA a 24-clock first beat a burst). 60 frames:

| cart | hashes (frame 60) | cart Mc | seq Mc | CPU max Mc | wall Mc | comp Mc | DMA Mc | CPU MB/frame | comp MB/frame | MB/s at 60 fps |
|---|---|---|---|---|---|---|---|---|---|---|
| tutorial | **= scene_hash, = native** | 0.48 | 0.68 | 1.16 | 2.60 | 0.77 | 0.58 | 0.32 | 3.39 | 276 |
| union_main | **= scene_hash, = native** | 48.16 | 1.76 | 61.72 | 49.96 | 2.45 | 4.02 | 18.11 | 11.09 | 1,806 |
| badflicker | **= scene_hash, = native** | 0.28 | 0.63 | 0.92 | 2.60 | 0.90 | 0.65 | 0.23 | 3.70 | 289 |
| equinox | **= scene_hash, = native** | 4.51 | 2.61 | 7.20 | 7.12 | 3.22 | 2.41 | 3.20 | 14.78 | 1,133 |
| dhs_0pxl0reg | **= scene_hash, = native** | 0.15 | 0.66 | 0.81 | 2.59 | 0.61 | 0.50 | 0.20 | 2.69 | 227 |

Mc = millions of 160 MHz sys cycles a frame, steady frames 6-59 without the
hashed one; *cart* = `frame()` + handlers, *seq* = the sequencer issuing and
waiting for passes (swap wait excluded), *wall* = the frame including the wait
for the swap (2.65 Mc is one 60 Hz VBL at 160 MHz), *comp* = cycles a pass ran,
*DMA* = cycles a burst ran. MB/s counts the CPU's and the compositor's bytes a
frame at 60 fps plus the scanout's 53.8 MB/s; the board's DDR3 x16 peaks at
2,133. Every run: no underrun, no overflow, 59 swaps. `badflicker` and `equinox`
are the two carts a line-major order changes (`tools/video_order_shelf.py`);
plane-major, they match.

**The mutants.** A sequencer in the **line-major order** a beam-racing
compositor would impose (`ZM_LINE_MAJOR`: frame() first, then per line G, BG and
every plane's handler and pass) fails: `badflicker` MISMATCH at frame 2, as
`video_order_shelf.py` predicted; over 60 frames `badflicker` and `equinox` both
MISMATCH and `tutorial` (one plane, no handler interplay) still matches, the control. The **no-drain** sequencer
(`ZM_NO_DRAIN`) does NOT fail, and that is a finding, not a pass: it issued a
command with a store still in flight 739-3,650 times in 4 frames (the
`undrained` count in `ZM VSTAT`), with the handler probes and without, on the
recommended path, a loaded DDR (`sb_drain` 16) and a saturated one (64), on
tutorial, badflicker, equinox and dhs_0pxl0reg, and every hash still matched.
Why: a PLANE pass reads its palette and geometry only after loading its PFB
row (about 450 clocks), and the next BG or PLANE pass waits for the previous
pass's row store, under which the handler's stores drain; only LATCH and a BG
pass's first word are read at once, and no cart's last store before those is
read by them. The rule stays (it is free, and it is what makes the order
exact by construction rather than by slack), but the test that proves it
load-bearing would need a handler longer than a row store that writes
`BACKGROUND` last, which no corpus cart has. The no-copy-back mutant
(`ZM_NO_COPYBACK`) also passes on tutorial and dhs_0pxl0reg: their handlers set
`BEAM_COUNT` rather than add to it, and read neither `BACKGROUND` nor `FRAME`.

### What remains before a bitstream

- **Row I/O overlap.** A pass loads and stores serially around its paint; a
  second line buffer would let the next pass's load run under the current one's
  store and the next handler, and skipping the PFB store of rows nothing changed
  (done) could extend to the picture. 3-4 plane frames need it to fit 60 fps at
  150 MHz (above).
- **The compositor on its own clock: done** (timing pass 2). `zm_video_out`'s
  `clk` is the SoC's `comp` domain (125 MHz on the board, 200 MHz in the video
  sim against sys 160); every boundary crosses in `soc/zm_video_cdc.py`
  (fpga/README.md "Timing under openXC7"). The drain rule's `drained` now
  means the compositor has USED every snooped store, not only received it. The
  video sim's `comp` column counts comp clocks. `zm_video_plane.v` registers
  its inputs and its geometry ahead of `start`, which took comp from ~95 to a
  112 MHz median over the seeds.
- **The AXI master toward HP0** (`soc/zm_video_dma.py` is Wishbone with
  `cti` bursts; `max_burst=16` splits for AXI) and the HP bridge the snoop moves
  into (on the board it taps the CPU's data bus for now); the seal (the other
  ADR half) owns `vbase`/`fb*` once it exists.
- **openXC7's chipdb** for the PS7 and **timing closure**: the compositor's
  `vbase +` adders are new 32-bit cones on the request path.

## Cost (Yosys `synth_xilinx`, xc7, before place and route; `make -C fpga util`)

| Block | LUT | % of 7010 | FF | CARRY4 | BRAM | LUTRAM | DSP |
|---|---|---|---|---|---|---|---|
| `zm_video_comp` (with the mixer and row I/O) | 1,691 | 9.6 % | 1,221 | 186 | 5 | 36 | 13 |
| `zm_video_out` (+ double buffer, scanout fetch, timing) | 1,960 | 11.1 % | 1,463 | 221 | 8 | 36 | 13 |
| `zm_tmds_enc` (one channel) | 52 | 0.3 % | 28 | 7 | 0 | 0 | 0 |
| whole z7 SoC with video + DVI + glass (`tools/soc_util.py`, 2026-10-02 tree) | 5,433 | 30.9 % | 5,259 | 451 | 37 | 50 | 17 |

Against the line-racing design (1,378 / 1,492 LUTs): the row I/O, pass phases
and the scanout fetch add 313 LUTs to the compositor and 468 to the pipeline;
the two display buffers left the mixer for the scanout, so BRAM stays 8. The
SoC figure also carries the 64-bit DMA master, its width converter onto the
32-bit bus, the snoop, and whatever else the tree held that day (it was 4,069
before; the seal work was in progress in the same tree).
