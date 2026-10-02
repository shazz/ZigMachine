# FPGA design review (Fable, 2026-10-02)

Adversarial read of `docs/ZIGMACHINE_IN_FPGA.md`, `docs/FPGA_STEPS.md`, `fpga/CYCLES.md`,
`fpga/rtl/video/*`, `fpga/soc/*.py`, the board README, `machine/video.zig`, `machine/sdk/memmap.zig`
and the ADR, at `b99da65`. Read-only; nothing was built. **Verified** = read in the code or a
measured number in the docs. **Hypothesis** = reasoning from them, to be tested.

Severity: **B** blocker (the board design cannot work as described) · **H** high · **M** medium · **L** low.

## Top 10

| # | Sev | Finding | Fix / experiment |
|---|---|---|---|
| 1 | **B** | **`frame()` concurrent with the beam breaks the machine's contract and the oracle.** The machine runs `hwClear` (280 global HBLs) → `frame()` → planes, atomically (`fpga/host/main.c:66-81`, `docs/sealed-loader.js:607-680`). The hardware plan has the compositor race the beam while `frame(N+1)` draws into the same VRAM and HBL interrupts preempt it. Nearly every cart draws in place (only 2 files in `apps/zig/scenes`+`libs/zig` touch `REG_FB_BASE`), so single-buffered carts tear and `scene_hash` stops being an oracle for the board. "90/90 identical" (`FPGA_STEPS.md`) was measured with `frame()` complete before rendering. | Decouple the compositor from the beam: composite into a DDR frame buffer at compositor speed **in the machine's order** (BG+global HBLs, then `frame()`, then planes), scan out the previous frame. ~80 MB/s, one frame of latency, no preemption, no tearing, and the DDR buffer is hashable **on the board**. Details in §A1. Decide this before plan step 3. |
| 2 | **B** | **The seal is not enforceable as written.** The ADR says "the cart master sees only its windows", but the cart, the ROM and the host firmware run on **one** VexRiscv in one address space (`fpga/host/boot.c:9-27`: one `env.memory` for all modules), and the recommended board build drops wasm2c's bounds checks (`CYCLES.md` "Builds: aligned"). A wild `sw` reaches the video `cmd`/`mem_base` CSRs, the UART and Linux's DDR; a 32-bit wasm offset wraps anywhere. Today nothing stands between the cart and the machine. | Either (a) hardware: mask the core's data addresses to an 8 MiB window (7 MiB RAM + the video peripheral overlaid) and bus-error the rest, and move the sequencer + `mem_base` out of software (§A2); or (b) PMP/user-mode on VexRiscv with the ROM in M-mode; or (c) keep the bounds checks (+36 %). Say which one in the ADR. |
| 3 | **H** | **150 MHz has no closure evidence; the whole CYCLES.md margin chain hangs on it.** Measured: sys **92 MHz against 100** with VexRiscv `standard` (`FPGA_STEPS.md`), 9.17 ns of a 10.87 ns path being routing (nextpnr-xilinx, not timing-driven the way Vivado is). The recommended core adds a 2-way 16 KiB I$ (wider way mux). The compositor also has single-cycle `base + row*stride + hs` (`zm_video_plane.v:57`, a DSP + 32-bit add) and `py*101 + seed*7` (`:79`) on the `start` path. | Run the z7 SoC through **Vivado ML** once now (free, no board needed) with the I16w2 core at 100/125/150 MHz. If 150 does not close, the CYCLES.md verdict changes (skystrike 119 MHz nominal, ~140 loaded). Pipeline the two start-path arithmetic cones regardless. |
| 4 | **H** | **The line fetch is one Wishbone word in flight (`zm_video_pipe.py:128-143`).** Against the modelled HP read latency (+24 unloaded, +62 loaded, `CYCLES.md`) a 400-byte line is 100 × ~30 = ~3,000 clocks per plane per line; 4 planes ≈ 12,000 > the 7,920-clock line at 150 MHz. The compositor budget (5,060 worst) assumed the testbench's 1-8 clock memory. The fetcher itself is burst-ready (in-order responses, no back-pressure, `zm_video_fetch.v:4-17`). | An AXI master issuing 32-byte (or 64-bit × 8) INCR bursts for the covering span, several outstanding; or, with #1's design, the deadline disappears and single-word fetches merely cost DDR efficiency. Add the fetcher's traffic to `zm_memtiming` so the CPU and DMA contend in the sim. |
| 5 | **H** | **Live palette writes race the pass.** The painter reads the palette RAM live during a pass (`zm_video_paint.v:61`, `zm_video_comp.v:105`); the machine's handler runs atomically between passes. On the board the handler for line y+1 (interrupt) writes palettes while line y paints → mid-line palette changes the machine never shows. Also, a handler's stores sit in the write-through D$ + the recommended 8-entry **posted store buffer**: "handler returned" ≠ "writes landed", so a pass can start before its palette/HSCROLL write arrives. | With #1 (sequential), only the drain rule remains: the sequencer waits for store-buffer-empty + bus idle before each pass (a `fence`-like CSR). Without #1: shadow palettes committed at pass start (one more RAMB36). |
| 6 | **H** | **The video window is write-mostly and the memory model is undefined.** `cpu_rword = adr[:5]` (`zm_video_pipe.py:111`): a load from a palette or the BEAM table returns a register word; words the compositor does not store read 0 (`zm_video_regs.v:3`), including `REG_FB_HBL_ID`, `REG_GLOBAL_HBL_ID`, `CART_HIGH`, the arena — which the ROM and dispatcher read (`machine/video.zig:81-92,113-183,216`). Nothing says how the cart's linear-memory stores at `HW_VIDEO_BASE+…` reach the window at `0x90000000` (`zigmachine_soc.py:35`). | Keep the whole region as ordinary DDR memory (so every read works as in wasm) and add a **write snoop**: the D$ is write-through, so a bridge forwards stores in `[0, 0x1100)` and the BEAM table to the compositor as well. Mirror the compositor's four write-backs (BACKGROUND, BEAM_COUNT, BEAM_DROPPED, FRAME) back to DDR or redirect those reads. |
| 7 | **M** | **HBL as an interrupt costs more than the measurement included, and the strobe is the wrong trigger.** CYCLES.md's "cart" column measures handlers as direct calls. On the board: trap entry, 16-32 register saves, 2-3 CSR reads over the CSR bus, I$ pollution, up to 5 dispatches a line (global + 4 planes, `video.zig:220,273,339,367,397,425`) ≈ 500-1,000 cycles/line ≈ 7-13 % of a 7,920-cycle line. And `zm_vtiming`'s HBL fires in the blank *before* the line is shown (256 clocks, not the 264 in its header), i.e. after the compositor must already have that line (two buffers = one line of slack, `zm_video_scan.v:42-44`, so the README's "any number of lines ahead" is wrong). | With #1 the compositor drives the sequence and the handler is a call again (no interrupt). Otherwise the HBL interrupt must come from the compositor's own line pipeline one line early, and the handler budget must be re-measured with interrupts. Fix the README/header numbers. |
| 8 | **M** | **The per-line deadline versus two display buffers.** `dp_free` lets a line start only after the line two before it has been shown; a long line cannot borrow slack from short ones. `worst` is 5,060 clocks against 4,224 at 80 MHz (underruns, by test) and 5,280 at 100 MHz — 4 % margin at the clock the SoC actually reaches today (92). | Four line buffers (2 more RAMB36) average slack across lines; or #1 removes the deadline. |
| 9 | **M** | **Verification gap: nothing has run the RTL compositor, VexRiscv and a translated cart together.** The RTL is driven by a replay testbench; the Verilator SoC runs the *C* machine. The concurrency, drain, window and interrupt issues above only appear in the combined system, and it needs no board. | Highest-value next test: the cycles firmware + `ZMVideo` in Verilator, a software sequencer issuing passes and calling handlers, hash the display/frame buffer, compare to `scene_hash`. Start with `tutorial`, `union_main`, `badflicker`, `equinox`. |
| 10 | **M** | **Plan order.** Step 1 (ARM fills DDR, PL scans it out) needs the PS7 (`ps7_init` not public for the 7010; zeST's `boot.bin` is the route) *and* HP0 *and* the DVI path all at once. The DVI/OSERDES/pin/monitor path is testable alone first, from BRAM, with the PL's own 50 MHz. OSERDESE2 cascade + OBUFDS through prjxray is a known-incomplete corner (hypothesis). | Order: blink → **test pattern from `zm_vtiming` + `zm_dvi_out`, no PS** → zeST boot + HP0 scanout of a DDR picture (plan step 1, and with #1 it is the permanent scanout, not a throwaway) → time one HP refill and one posted write (`tools/mempath_cfg.py`) → VexRiscv + cart. Vivado fmax (#3) and the integration sim (#9) are desk work to do while waiting. |

---

## A. Architecture

### A1. The machine is plane-major and atomic; the beam is neither (B, #1)

**Verified.** `machine/video.zig:215-232` runs the global HBL for all 280 lines inside `hwClear`, *before*
`frame()`; the per-plane HBLs run inside `hwRenderPlane`, after `frame()`, with LOGICAL lines (0..199)
for normal/scroll/medium planes and physical lines for fullscreen/overscan (`:273,339,367,397,425`).
`tools/video_order_shelf.py` showed line-major HBL order changes 2 of 90 carts (`badflicker`,
`equinox`) — but it kept `frame()` complete before any pass. `fpga/rtl/video/README.md:536-538` lists
"frame() runs while the beam scans" as open; it is not an open detail, it is the design.

**Hypothesis (strong).** On a line-racing design: (i) carts that draw in place tear (almost all; see #1);
(ii) HBL handlers preempt `frame()` mid-statement — wasm never allowed that, so shared tables
(a sine table `frame()` rewrites and the handler reads) are read half-updated; (iii) global handlers see
`frame(N+1)`'s partial state. None of it is reproducible by any oracle, so the "proven before it touches
the board" story ends at step 3.

**Options, with costs.**
- **(a) Accept it** (ST-like). Lose `scene_hash` for the board; keep it for the RTL in isolation.
- **(b) Frame latency + VBL snapshot** of the planes' windows into the unused PFB area (896 KB worst,
  ~1 ms with the CPU stalled). Fixes tearing, not (ii)/(iii).
- **(c) Decouple the compositor from the beam (recommended).** Per frame, sequentially on the one core:
  BG passes with global handlers → `frame()` → plane passes with per-plane handlers, line-major as the
  RTL already works, the mixer writing the picture to a DDR frame buffer (800×280×3 = 672 KB, double
  buffered); the scanout DMAs the previous frame through the existing `zm_video_dcram` line buffers.
  DDR: ~40 MB/s write + 40 MB/s read + plane fetches. Compositor time comes off the cart's budget:
  corpus worst 2,099 clocks × 280 = 0.59 Mc (3.9 ms at 150 MHz, 23 % of the frame), typical 1 plane
  858 × 280 = 0.24 Mc; skystrike 1.92 + 0.24 = 2.16 Mc still fits 2.5 Mc. Gains: exact machine
  semantics, no interrupts, no palette race (#5), no per-line deadline (#4, #8), compositor clock
  independent of the CPU's, `badflicker`/`equinox` fixed by the one-line machine changes already
  identified, and **the DDR frame buffer is `scene_hash`'s PFB on the board** (hash it from the ARM;
  a debug mode can also dump the per-plane intermediate). The cost is one frame of latency, which the
  browser already has, and the "palette write with no bus between CPU and shifter" narrative in
  `ZIGMACHINE_IN_FPGA.md`, which the machine never had either (HBLs are callbacks, `FB_HBL_POS` is a
  declared register, not a measured beam position — `video.zig:284-287`).
- Note the doc's "`flickerBorder()` becomes real res-flicker timing": if the hardware ever *measures*
  the flicker's timing, overscan carts stop matching the oracle. Pick declared (oracle-exact) or real.

### A2. The seal (B, #2)

**Verified.** `decisions.md:25-26`: "The seal is enforced by the AXI interconnect (the cart master sees
only its windows)". `boot.c:9-27`: machine, ROM and cart share one memory and one core; `CYCLES.md`
recommends `aligned` (no bounds checks, −36 %). `zm_video_pipe.py:89`: `mem_base` is a CSR the DMA
adds to every fetch address. `zigmachine_soc.py:118-120`: the video window and DMA are on the same
Wishbone as the CPU.

**Consequences.** There is no "cart master": the master is the core, which also runs the ROM and the
sequencer. A cart store to `mem_base` points the video DMA at Linux's memory; a store to `cmd` wedges
the compositor; a wrapped offset hits the UART. The video region is both "machine state" and
"cart-writable" (palettes, registers), so it must be inside the seal anyway.

**Fix.** (1) Make the sequencer hardware or ROM-only and remove `mem_base` (fix it at elaboration);
(2) a data-address mask + decoder: the core may touch `[0, 7 MiB)` DDR and the video peripheral
overlay (#6) only, everything else `err` → trap; (3) ROM code X-only via PMP if "execute-only ROM" is
still wanted; (4) keep the bounds checks until (2) exists, as `ZIGMACHINE_IN_FPGA.md:90` says.
The ADR should name the mechanism.

### A3. Smaller architectural points

- **ROM in BRAM does not fit** (L). `rom.o` text is 229 KB rv32 (`fpga/build/cycles/stock/common/`);
  the 7010 has ~270 KB BRAM, 46 of 60 RAMB36 already used. `CYCLES.md` already assumes ROM in DDR;
  `ZIGMACHINE_IN_FPGA.md`'s table should say so.
- **ARM as I/O only** (M). Fine for input latency. The unmodelled risk is DDR arbitration: Linux, the
  HP0 CPU path, the video DMA and later the blitter and audio share one x16 DDR3-1066 (~2.1 GB/s
  peak). Set the DDRC QoS/`HP` priorities in `ps7_init`, and measure under Linux load, not idle.
- **Blitter** (M). `hwBlit` is synchronous and byte-per-pixel with up to 3 sources
  (`BLITTER_HW_SPEC.md §6`, `blitter.zig:393-413`); tsl_hybridglenz spends 27 Mc/frame in it. In DDR
  that is three read streams + one write of single bytes unless it works on 32/64-bit words with
  masks. Spec the burst/word model before RTL; with A1(c) it also runs sequentially with `frame()`.
- **Audio ring** (L). 32 KB in BRAM would be 8 RAMB36; stream it from DDR.
- **GPL** (L). Already noted in the ADR; unresolved.

## B. RTL correctness

Read: `zm_video_out/scan/sync/dcram/mix/tmds_enc/dvi_out/vtiming/comp/regs/fetch/paint/plane/latch/bg`.

- **TMDS encoder** (`zm_tmds_enc.v:38-60`): checked case by case against DVI 1.0 §3.3.3 — balanced,
  invert and non-invert branches, `adj`, control tokens, bit order (D1 first = `q[0]`). **Correct.**
  Clock lane comment says "5 ones then 5 zeros"; the pattern sends 5 zeros first. Harmless (L).
- **Mixer arithmetic** (`zm_video_mix.v:82-90`): `(x+128 + ((x+128)>>8))>>8` is exact `round(x/255)`
  for x ≤ 65535; `d*(256−a)` ≤ 65280 fits 16 bits; the sum never exceeds 255 (checked the a=0, 255,
  128, 1 corners). **Correct.** Note the oracle is Chrome's *software* compositor; a GPU compositor
  differs by up to 4 LSB (`README.md:505`), so the HDMI picture of an alpha cart will not equal what
  Matt's browser shows. Consider declaring the machine's own integer blend canonical (L).
- **CDC** (`zm_video_sync.v`, `zm_video_dcram.v`, `zm_video_out.v:61-85`): toggle synchronisers with
  `ASYNC_REG`, data (`pub_line`, buffer contents) stable before the toggle flips and unchanged until
  the buffer is freed. Sound as a protocol. **Gaps:** no `set_false_path`/`set_max_delay` anywhere
  (`grep` of `fpga/soc`, `fpga/tools`, the XDC: only the attribute). nextpnr-xilinx's inter-clock
  handling must be checked — a 92 MHz "failure" or pass on a sys↔pix path is meaningless until the
  crossings are declared (H, hypothesis). The toggle rule "pulses ≥ 3 destination clocks apart" holds
  for every user (one per line).
- **Reset**: `zm_video_sync` has no reset (init values only, fine on 7-series); `dp_free` resets in
  `clk`, `full` in `pix_clk`. Asymmetric resets self-heal because `freed` pulses every HBL whether or
  not the buffer was published (`zm_video_scan.v:42-44`). After an underrun the compositor stays one
  line behind for the rest of the frame unless the sequencer resyncs at VBL — the sequencer does not
  exist yet (M).
- **Scanout**: `ok` compares buffer line to `zm_line`; underrun sticky; outputs 2 clocks behind the
  timing, all aligned. **Correct.** `zm_vtiming` HBL leads the line by 256 clocks (40+128+88), not
  264 (`zm_vtiming.v:10`).
- **OSERDESE2** (`zm_dvi_out.v:41-61`): DDR 10:1 master/slave cascade per UG471, CLK = 5× pixel from
  the same PLL (`zigmachine_soc.py:80-82`), 400 Mb/s per lane, well inside a -1 HR bank; `rst` in the
  CLKDIV domain. Hold the reset a few CLKDIV cycles after PLL lock (LiteX's CRG does if `pix` reset is
  derived from `pll.locked`; verify). Whether prjxray's bitstream encodes the cascade correctly is the
  board test (#10).
- **Timing paths to watch at ≥100 MHz**: `zm_video_plane.v:57,79` (multiply + add + mux in one cycle),
  `zm_video_bg.v:39` (two 16-bit compares feeding a 3-way state decision), `zm_video_regs.v:64`
  (32:1 × 32 mux, combinational to the Wishbone `dat_r` register — fine), the mixer's
  `pm`→`p`→`o` (two adders after a registered product — fine).
- **Command CSR race** (`zm_video_pipe.py:116-126`): `cmd` fields drive the compositor directly; a
  second write before `take` silently replaces the first. Software must poll `status.ready`; a FIFO
  would remove the rule (L).
- **`mix_hazard`** logic (`zm_video_comp.v:156`): after the sweep's `run` ends `m` = 400, no writer
  address reaches it, so no false hazard. Fine.

## C. Latency and throughput

- Memory path: the store buffer result (`hp_sb` = `hp_free`, `CYCLES.md`) is convincing. Unmodelled:
  the fetcher's reads contending with the CPU on HP0 and the DDRC (CYCLES.md says so). With A1(c) the
  video traffic is ~80-200 MB/s steady; with the line-racing design it is bursty at line rate.
- Fetch bursts: #4. Even with A1(c), 32-bit single-beat reads waste ~8× DDR efficiency on a 64-bit
  port; do the burst master once, it is the same AXI shape the fetcher already assumes.
- HBL latency: #7. If interrupts stay, measure them in the cycles sim (the `trap.S` path exists); the
  table's "cart" cycles exclude them.
- Compositor per line: 858 (1 plane) / 2,081 (3) / 5,060 (worst synthetic) clocks are from
  `--timing` replays with a 1-8 clock memory; re-measure with the HP latency model before quoting a margin.

## D. Optimisations (LUT/BRAM/DSP on the 7010)

- **Mixer DSPs 12 → 6** (`zm_video_mix.v:83-84`): share `a` by packing `{c,16'b0} + d` into one DSP48E1
  (25×18): `(c·2^16 + d)·a` gives both products with no carry overlap since `d·a` < 2^16. Or compute
  `d·(256−a)` as `(d<<8) − d·a`. Zero LUT cost.
- **Display buffers** (`zm_video_dcram` 1024×48): 2 RAMB36 for two lines. With A1(c) they become the
  scanout's DMA line buffers and stay; without it, 4 lines (#8) cost 2 more.
- **Palette RAM** is already one RAMB36 for 4 planes; the fetch buffer (256×32) could be LUTRAM
  (it is 8 Kb) to save a RAMB18 — only if BRAM gets tight (it will: SNDH core + blitter + audio).
- **Cheaper cart cycles, not yet exploited**: `aligned` + no bounds is in; the ROM in DDR shares the
  I$ with the cart (16 KiB 2-way measured enough). A 2 MiB-aligned layout lets the address mask (A2)
  be a few LUTs.
- **The compositor's own clock**: with A1(c) it need not run at the CPU's clock; 100 MHz with the
  known 4 % worst-synthetic margin becomes irrelevant (no deadline), and the CPU can chase 150 alone.

## E. Verification gaps and the next test

What the current strategy cannot catch: anything that needs the CPU and the RTL in one system (#1,
#2, #5, #6, #7), DDR-realistic fetch latency on the compositor (the replay stalls 1-8 clocks), DDR
contention between masters, CDC with real phase drift (CXXRTL ratios are integer; 15:4 is the board's
150/40, 23:10 the 92/40 case — run both), reset mid-frame, and the OSERDES/pins/monitor path.

**Next test (M, #9):** Verilator SoC = VexRiscv + `ZMVideo` + the cycles firmware acting as the
sequencer (write passes to `cmd`, call `hblDispatch` between them, drain stores), with
`zm_memtiming` on both the CPU and the DMA. Hash the display buffers per line (or the DDR frame buffer
under A1(c)) and compare to `apps/scene_hash.mjs`. Carts: `tutorial`, `union_main`, `badflicker`,
`equinox`, `dhs_0pxl0reg`. Then a mutant: make the sequencer *not* drain the store buffer, and show
the hash moves — that is the proof the drain rule is load-bearing.

Also worth adding: a TMDS cross-check against `third_party/hdmi`'s encoder (independent author), a
Vivado timing report for the z7 SoC at 100/125/150 MHz committed as a number, and a test that the
video window's reads return what the machine would (today they cannot, #6).

## F. Plan order

See #10. Two desk tasks should precede any board work because they can change the design: the
Vivado fmax of the real core (#3) and the integrated sim (#9). The A1 decision gates step 3 (the cart
CPU), because it decides whether the video DMA needs a write path and whether the HBL is an interrupt.
Step 2 (YM from the ARM) is independent and can go anywhere; `jt49` at 286 LUTs is cheap and gives a
second, easy board win after the test pattern.

## G. Smaller doc corrections

- `zm_vtiming.v:10` "264 clocks" → 256. `zm_video_out.v:7` "any number of lines ahead" → one line.
- `ZIGMACHINE_IN_FPGA.md` ROM row: DDR, not BRAM; "Interrupt on every line start = HBL handlers,
  natively" needs the A1 caveat; the 7,900-cycles-a-line figure is before interrupt entry and the
  compositor's own passes.
- `fpga/rtl/video/README.md` throughput paragraph: state the memory model the clocks were measured with.
