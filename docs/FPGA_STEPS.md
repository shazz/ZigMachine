# ZigMachine on an FPGA: progress log

What has been done toward [`ZIGMACHINE_IN_FPGA.md`](ZIGMACHINE_IN_FPGA.md),
what each step measured, and what is next. The working tree is [`fpga/`](../fpga/README.md).
Newest status first. Every number here was measured, not estimated, unless it
says otherwise.

## Status at a glance

| Plan step | What | State | Result |
|---|---|---|---|
| — | Architecture decision (RISC-V, not a wasm softcore) | **done** | ADR 2026-10-01 in `decisions.md` |
| — | `fpga/` tooling: cores, uv env, memmap export, cost tool | **done** | `make -C fpga setup && make -C fpga check` |
| 0a | Every cart through wasm2c, then compiled for `rv32imf` | **done** | **90 / 90** compile, no cart changes |
| 0b-i | Native C host: machine + ROM + cart, all wasm2c'd | **done** | **98 / 98 fingerprints identical** to `scene_hash.mjs` |
| 0b-iii | Memory path: DDR via HP, store buffer, caches | **done** | 8-entry store buffer + 16 KiB 2-way I$: **150 MHz holds on DDR** (`784cb2c`) |
| 0b-ii | Cycles per frame on a real VexRiscv (Verilator) | **done** | hashes identical on 9 carts; **150 MHz, no FPU** (`fpga/CYCLES.md`) |
| — | Board files (XDC, schematic, PS7 bring-up) | **done** | `fpga/tools/fetch_board.sh`, gitignored; HDMI pins re-derived from the schematic |
| — | Whole SoC elaborated against the real board | **done** | 2,408 LUTs (13.7 %) synthesised |
| — | Video to the wire: mixer, scanout, TMDS/DVI, in the SoC | **done** | mixer = Chrome byte for byte; 40/40 frames; 90/90 carts replay identically |
| — | openXC7 toolchain (Docker, pinned) + first bitstream | **done** | `make -C fpga blink`; the full SoC routes |
| — | Timing closure under openXC7 (pass 2) | **done at 100 MHz** | glass SoC **meets sys 100 / comp 125 MHz** (seed 8, pinned); compositor on its own clock; skystrike needs 119 |
| — | The glass: ARM loader + OSD menu + USB keyboard/mouse/pads ([`FPGA_GLASS.md`](FPGA_GLASS.md)) | **built, host-tested** | GP0 regs + OSD in RTL (19/19 break tests), Zig `glass` (37 tests), input break tests 18/18, 9 board images land byte for byte; the SoC with PS7 does not route yet |
| 1–7 | Board work | **started: blink runs on the board** | `openFPGALoader -c digilent_hs2 fpga/build/blink/blink_top.bit` |
| RTL | Video timing (`zm_vtiming`) | **done** | 64 LUTs, CXXRTL-tested over 2 frames |
| RTL | Video compositor: planes, palettes, border, BEAM, all modes | **done** | **32/32 frames pixel-identical** to the machine; 25/25 mutants caught; 1,169 LUTs |
| — | DDR framebuffer video: sequencer, snoop, double buffer, scanout DMA | **done** | the cart CPU + the RTL video in Verilator: **5/5 carts hash = scene_hash** (tutorial, union_main, badflicker, equinox, dhs_0pxl0reg); 49/49 RTL mutants caught |

---

## 2026-10-03: the board is alive

- **First light.** `openFPGALoader -c digilent_hs2 --detect` sees the JTAG chain:
  the ARM Cortex-A9 DAP (`0x4ba00477`) and the **xc7z010** (`0x3722093`).
- `fpga/build/blink/blink_top.bit` (openXC7, 8 LUTs) loaded into the PL SRAM.
  **PL LED1 and LED2 alternate**, as designed. The open toolchain
  (Yosys → nextpnr-himbaechel → prjxray → openFPGALoader) is proven end to end
  on real silicon.
- Setup: the USB-C **JTAG** port (J6; it also powers the board), the **UART**
  port (J3, CH340 → `/dev/ttyUSB0`), and jumper **J1 on the JTAG pins**.

## 2026-10-03

### Timing pass 2: the compositor on its own clock, the predictor on trial, a pinned seed

Details: [`fpga/README.md`](../fpga/README.md) "Timing under openXC7" and
[`fpga/CYCLES.md`](../fpga/CYCLES.md) "Branch prediction and the clock".
Logs and the ledger: `fpga/build/timing2/` (`results.txt`).

- **The board build meets timing:** `uv run python -m soc.zigmachine_soc
  --target z7 --build` gives **sys 100.63 MHz, comp 125.19 MHz** (both pass),
  reproduced by a fresh end-to-end build (same netlist byte for byte, same
  result). The seed is pinned in `soc/openxc7.py`: over seeds 1-12 the same
  netlist gives sys 76-102 MHz, and seed 8 is the only one that meets both
  clocks. Any netlist change needs a re-sweep.
- **The compositor runs in `comp`** (`soc/zm_z7.py`'s PLL, 125 MHz), crossing to
  `sys` through `soc/zm_video_cdc.py`: snooped stores through a gray queue
  (`drained` = the compositor has used them), command/ready/painted as echoed
  toggles, read-back and the three DMA ports as toggle requests with queues.
  5 Migen-sim tests at unrelated clocks; the video sim (comp 200 against sys
  160) still hash-matches on tutorial and dhs_0pxl0reg; `make -C fpga check`
  green (122 passed).
- **comp's own path** was the plane pass's geometry (latch LUTRAM -> compare
  -> carry chains, 10-11 ns). `zm_video_plane.v` now registers its inputs and
  its geometry before `start`: comp 89-99 -> 92-139 MHz (median 112) over the
  seeds. RTL video tests 46/46.
- **No branch prediction loses.** It removes the static predictor's cone (pass
  1's 82 -> 99.5 MHz, one seed each), but on this netlist that is worth ~10 %
  sys at the median seed (90.7 -> 99.9 MHz) against **+16.5-24.5 % cycles**
  (union_beatdis 52 -> 62 MHz needed, ulm_dsots 98 -> 114, skystrike 119 -> 141,
  tutorial 26 -> 32). The board keeps static prediction; the no-prediction core
  is built alongside (`make -C fpga vexgen-board`, `vexgen/gen.sh ...:nopred`).
  The dynamic-target predictor needs 9-14 % FEWER cycles but does not route
  (overuse climbs, three attempts).
- **Is ~100 MHz enough?** For union_beatdis (52), tutorial (26) and ulm_dsots
  (98, 3 % margin) yes; **skystrike (119) no**, about 50 fps on its sustained
  load. Plus the sequencer's own wait for the passes, which comp's faster clock
  shortens.
- **Not done:** a frozen placement. openXC7's `-o preplaced=` aborts on this
  build (`dict::at()` while packing, even with one pinned cell), so the seed is
  the only pin.

**Pass 3 should look at:** routing the dynamic-target core (it would take
skystrike to 107 MHz needed); the `-o preplaced=` crash (a frozen placement
would stop every netlist change from redrawing the seed lottery); VexRiscv's
execute-stage and I$-tag->regfile paths, now `sys`'s limit; and Vivado for one
honest timing report.

---

## 2026-10-02 (night)

### The video composites into a DDR framebuffer (ADR 2026-10-02; Fable #1, 4-9)

The line-racing compositor is gone. Every frame is built in the machine's own
order, at the compositor's speed, into a picture in memory, and the scanout shows
the previous picture. Details: [`fpga/rtl/video/README.md`](../fpga/rtl/video/README.md).

- **The sequencer is the cart CPU's firmware** (`fpga/cycles/vseq.c`): hwClear's
  global handlers and BG passes, `frame()`, then per enabled plane LATCH and a
  PLANE pass a line with the handler called before it, exactly where and with
  the line numbers `machine/video.zig` uses. Handlers are calls, not interrupts.
  It waits for `painted` (the pass has read the CPU's state) and `drained` (the
  handler's stores have reached the compositor) before each pass.
- **Plane-major, so rows live in memory.** A BG pass stores its PFB row; a PLANE
  pass loads it, paints, folds it into the picture and stores both. The PFB rows
  land where the machine keeps its PFB, so `scene_hash` hashes the board's frame.
- **Double-buffered picture, swap at VBL.** PRESENT marks the back picture
  complete; a pass that would write a picture waits for the swap. No tearing, one
  frame of latency. The scanout fetch reads the front picture a line ahead in
  400-beat bursts; underrun is detected and sticky.
- **Memory:** 64-bit burst read/write ports; `soc/zm_video_dma.py` serves them
  (scanout first) over one Wishbone burst master, AXI-shaped (`max_burst` = 16
  on the board).
- **The region is snooped** (`soc/zm_video_snoop.py`): it stays DDR, so every
  cart load reads what wasm would; the CPU's stores to registers, palettes and
  the BEAM table reach the compositor at the store buffer's drain rate. The
  sequencer copies the compositor's 4 write-backs into the region.

**The integration test** (Fable #9; `make -C fpga video-sim`,
`tools/video_sim_run.py`): VexRiscv running the translated cart with the
sequencer, the RTL pipeline, the scanout in a 40 MHz pixel clock against a
160 MHz sys clock, and ONE shared main RAM with the board's memory-path model in
front of the CPU (`hp_sb`) and of the video DMA (24-clock first beat). 60 frames,
the PFB hash at frame 60 against `scene_hash.mjs` and the native host:

| cart | hashes (frame 60) | cart Mc | seq Mc | CPU max Mc | wall Mc | comp Mc | DMA Mc | CPU MB/frame | comp MB/frame | MB/s at 60 fps |
|---|---|---|---|---|---|---|---|---|---|---|
| tutorial | **= scene_hash, = native** | 0.48 | 0.68 | 1.16 | 2.60 | 0.77 | 0.58 | 0.32 | 3.39 | 276 |
| union_main | **= scene_hash, = native** | 48.16 | 1.76 | 61.72 | 49.96 | 2.45 | 4.02 | 18.11 | 11.09 | 1,806 |
| badflicker | **= scene_hash, = native** | 0.28 | 0.63 | 0.92 | 2.60 | 0.90 | 0.65 | 0.23 | 3.70 | 289 |
| equinox | **= scene_hash, = native** | 4.51 | 2.61 | 7.20 | 7.12 | 3.22 | 2.41 | 3.20 | 14.78 | 1,133 |
| dhs_0pxl0reg | **= scene_hash, = native** | 0.15 | 0.66 | 0.81 | 2.59 | 0.61 | 0.50 | 0.20 | 2.69 | 227 |

Cycles in millions of 160 MHz sys cycles (2.65 M = one 60 Hz frame); full notes in the README.

**Mutants.** The line-major sequencer fails on badflicker and equinox over 60 frames (tutorial, the control, still matches). The
no-drain sequencer does **not** fail: it issued thousands of commands with a
store in flight, on three memory configurations up to a saturated DDR, and
every hash matched, because a pass reads palettes only after its ~450-clock row
load and the next pass waits for the previous row store. The drain rule is kept
(free, and exact by construction), but no corpus cart makes it load-bearing.

**Timing (the seal agent's finding).** The snoop's dBus tap was the SoC's
critical path under openXC7 (79.4 MHz). Pipelined (tap, offset, compare, and a
registered output with the region decoded into select bits the compositor takes
as inputs, `TIMING_FABLE.md` P1-4) it is off it: 92.8-96.8 MHz, then limited by
LiteX's bus-timeout counter (removing the timeout gained nothing, 92.3: P1-5
dropped). A separate compositor clock (Fable's `comp150_sys100`: 117.6 MHz) is
the next cut, not done.

**Costs:** `zm_video_comp` 1,691 LUTs (+313), `zm_video_out` 1,960 (+468), BRAM
unchanged at 8; the z7 glass SoC 5,433 LUTs (30.9 %).

**Next:** overlap row I/O with the next handler (a second line buffer): 3-4 plane
frames need it to fit 60 fps (equinox: compositor 3.2 Mc a frame); the AXI HP
master and HP bridge; the cart CPU is the limit for union_main (48 Mc a frame of
`frame()`, as CYCLES.md found for its float code).

## 2026-10-02 (evening)

### The glass: the console's front panel ([`FPGA_GLASS.md`](FPGA_GLASS.md))

- **ARM stack:** Linux (Buildroot) running one static Zig program, `glass`,
  over `/dev/mem` (ADR 2026-10-02). zeST's `BOOT.BIN` and, as a stopgap, its
  kernel boot it.
- **PL:**
  - `zm_glass_regs` is an AXI3 GP0 slave with the cart CPU's reset, a key FIFO,
    the joypad and the cart's reports: 223 LUT.
  - `zm_glass_osd` is 32×16 characters of the ST system font over the finished
    picture: 45 LUT, 2 BRAM.
  - Whole SoC: 4,424 LUT (25.1 %).
- **Proven without the board:**
  - the RTL under CXXRTL, including 3 whole frames checked pixel by pixel, with
    13/13 break tests caught;
  - the loader, menu, keymap and pad against a simulated block;
  - the board images `fpga/cycles` links for 9 carts, which go through fat
    disks and `glass sim-load` and land byte for byte;
  - `boot.scr` byte-identical to `mkimage`'s.
- **The mouse** (added later the same day): a `POINTER` register, with presses
  latched until the firmware acks them and a `SEQ` the firmware polls, so the
  cart gets `pointer(x, y, buttons)` with the browser's rules (0..639 × 0..199,
  any button = bit 0, a double-click pulse = bit 1). `zm_glass_regs` is now
  254 LUT. Pads gained `xpad` and the Sony, PlayStation, Nintendo and Microsoft
  HID drivers.
- **Open:** routing the SoC with the PS7 under openXC7 diverges (overuse 730 to
  1,830 over 51 iterations). Also open: the HP-port master and the board firmware
  that reports `CART_STATE`.

## 2026-10-02 (afternoon)

### The memory path, measured (`784cb2c`)

`soc/zm_memtiming.py` puts a DDR latency model in front of the simulation's
RAM. Its numbers are derived from UG585, UG1145 and the JBLopen benchmarks, not
measured on the board yet:

- an HP read: +24 cycles unloaded, +62 with DDR saturated, at 150 MHz;
- a blocking write: the same as a read;
- the options: a posted-write buffer, write combining, and ACP through the
  ARM's L2.

All 59 runs hash identically to the wasm machine.

| cart (aligned build) | 1-cycle RAM | HP, blocking stores | HP + 8-entry store buffer | ACP |
|---|---|---|---|---|
| union_beatdis | 55 MHz | 194 | 61 | 58 |
| ulm_dsots | 98 | 248 | 112 | 106 |
| skystrike | 115 | 325 | 129 | 124 |

- **Blocking stores were the whole penalty.** A posted-write buffer of about
  50 LUTs matches "free stores" cycle for cycle, so a write-back D$ is not needed.
- **A 16 KiB 2-way I$** costs +47 LUT and +3.5 BRAM, and brings skystrike to
  119 MHz. polkadots' I$ refills drop from 792k to 57k a frame.
- **Recommendation:**
  - VexRiscv `standard` + I$ 16K 2-way, D$ 4K write-through;
  - an 8-entry store buffer on HP0;
  - the aligned build (no bounds checks);
  - 150 MHz.

  Margin is 26 % unloaded, about 140 MHz under saturated DDR.
- **At board bring-up:** time one refill and one posted write, then put the real
  numbers in `tools/mempath_cfg.py`.

### A full frame on the wire (`f5b84e5`)

- **Mixer.** The browser stacks one canvas per plane. Chrome's software
  compositor was measured over all 65,536 colour × alpha pairs, and the RTL
  mixer reproduces it byte for byte (`zm_video_mix`). The C oracle equals
  Chrome's own screenshots.
- **Scanout.** The compositor runs in its own clock, with two dual-clock
  display line buffers feeding VESA 800×600 at 40 MHz. Whole frames are checked
  against VESA 800×600 timing, with the picture doubled vertically. An underrun
  is sticky.
- **HDMI.** Our own DVI TMDS encoder takes 52 LUTs per channel; 2 million
  symbols equal a spec encoder. Output goes through OSERDESE2 10:1 and OBUFDS.
- **The shelf.** All 90 hostable carts replay pixel-identically through the RTL.
  Line-by-line order (the hardware's) changes only `badflicker` (its noise seed
  is counted at `hwClear`) and `equinox` (planes share `RES_FLICKER`).
- **Throughput.** The worst line takes 5,060 compositor clocks: 4 % margin at
  100 MHz, 36 % at 150 MHz.
- **Open:** `frame()` running while the beam scans, the pass/HBL sequencer, and
  AXI HP bursts.

### The first bitstreams (`f685ee5`)

- **openXC7 in Docker**, pinned to toolchain-nix 092acc1. The xc7z010 chipdb is
  reproducible, and its sha256 is checked on every rebuild.
- **`make -C fpga blink`** builds `blink_top.bit`: 8 LUTs, 266 MHz against 50.
- **The full SoC** (VexRiscv, JTAG UART, PLL, video pipeline, HDMI serialisers)
  places and routes: 4,159 LUT, 46 BRAM, 17 DSP. Pixel clock: 126 MHz achieved.
  **sys: 92 MHz achieved against 100**, on VexRiscv's fetch path, where 9.17 ns
  of the 10.87 ns is routing. The fix is a lower sys clock or pipelining.
- **Fixed:** the generated XDC had no `create_clock`, so every clock was being
  checked against nextpnr's 12 MHz default, a false pass.

## 2026-10-02

### Step 0b-ii: the cart CPU's real load, and the verdict (`623f27c`)

The native host runs bare-metal on the SoC's own VexRiscv `standard` (rv32im) in
Verilator, built with GCC 13 and picolibc and a three-header shim for the stock
wasm2c runtime. **All 9 sample carts hash identically** to `scene_hash.mjs` and
to the native host, in every build. A cycle counter splits the time three ways:
**cart** (`frame()` plus the HBL handlers), **machine render**, and
**blitter**. The last two become RTL.

| cart | Mc/frame (p95) | MHz needed, soft-float | float share |
|---|---|---|---|
| blitter | 0.14 | 9 | 78 % |
| tsl_hybridglenz | 0.16 | 10 | 28 % |
| tutorial | 0.60 | 36 | 0 % |
| union_beatdis | 1.54 (2.04 worst frame) | 93 (122) | 0 % |
| ulm_dsots | 1.69 | 101 | 1 % |
| skystrike | 2.01 | 120 | 0 % |
| replicants_emlyn | 9.17 | 550 (209 even with an f64 FPU) | 65 % |
| polkadots | 37.7 | 2262 (449 with an f64 FPU) | 83 % |

- **Verdict: 150 MHz, no FPU.** The two outliers use `f64` kept from their
  JavaScript originals. That is a scene fix, not a hardware one.
- **Measured cheaper wins:** aligned loads cut cart cost by 4–40 %
  (union_beatdis 1.54 to 0.92 Mc). Dropping the bounds checks saves 36 %.
- **Caveat:** the simulated RAM answers in one cycle. With realistic DDR
  refill and store costs, union_beatdis would need 238 MHz, ulm_dsots 210 and
  skystrike 261. **The DDR/write path is the next design question**, more than
  the clock.
- **Still running:** the rest of the shelf (81 carts) is being measured in the
  background. `uv run python tools/cycles_report.py` refreshes the table.

### The video compositor in RTL, proven against the machine (`060a9af`)

`fpga/rtl/video/zm_video_comp.v` (+ 9 modules) builds each 800-pixel raster
line in passes: first the background or BEAM spans, then one pass per enabled
plane. It latches and reads registers exactly as `machine/video.zig` does.

- **How it was proven:** `tools/video_dump` records real carts through the
  native host: every register, palette and BEAM change around each HBL and pass,
  the memory read, and the PFB after each plane. The recorder's hashes equal
  `fpga/host`'s. A CXXRTL testbench replays the recordings with random memory
  stalls and compares all 800 pixels after every pass.
- **32/32 frames are pixel-identical.**
  - Real carts: tutorial, union_intro, union_main (3 planes), union_l16,
    tcb_colorshock, replicants_emlyn, gen4_3615, maxi, badflicker,
    dhs_0pxl0reg (BEAM), scroll, res_switch, medium_overscan.
  - Synthetic frames for what no cart reaches: fullscreen mode, per-line
    HSCROLL, BEAM edge cases.
- **25/25 one-rule mutants are caught**: `ZM_RTL_BREAK=1 make -C fpga test`.
- **Cost:** 1,169 LUT (6.6 %), 1,057 FF, 4 BRAM (palettes, line buffer,
  fetch), 1 DSP.
- **Throughput at 40 MHz (2,112 clocks a line):** 1 plane takes 858 clocks,
  3 planes 2,081. 4 planes need fetch/paint overlap or a 2× compositor clock.
- **Left:**
  - a scanout double buffer
  - the plane mixer (the browser stacks one canvas per plane)
  - an HBL sequencer: hardware runs line by line, the machine plane by plane
  - AXI bursts
  - place and route

### The board files: found, verified, and kept out of git

`fpga/tools/fetch_board.sh` (pinned commits, checksummed) fetches the following:

- **MicroPhase's own `Z7_LITE.xdc`.** It is in three public repos with an
  identical pin map (103 ports). Its header forbids publication, so it stays
  gitignored.
- **The schematic and the reference manual**, from MicroPhase's `fpga-docs`
  on GitHub.
- **Xilinx's xc7z010clg400 package file**, which maps each pin function to a
  ball.
- **zeST** (zerkman, GPL-3, an Atari ST on this very board): its Z7-Lite XDC,
  its Vivado PS7 configuration, and its **prebuilt 7010 `boot.bin`**.

What was verified:

- **HDMI pins:** every one was re-derived independently from the schematic and
  the package file, and all match: CLK U18/U19, D0 V20/W20, D1 T20/U20,
  D2 N20/P20, HPD P19, SCL R19, SDA T19. zeST agrees.
- **Clock:** the PL clock is 50 MHz on N18.
- **DDR3:** a single 16-bit MT41J256M16 (512 MB). One community `preset.xml`
  says 32 bits, and it is wrong.
- **UART:** it is on PS MIO, so the VexRiscv console on the board is `jtag_uart`.
- **`ps7_init` for the 7010** is not public. zeST's `boot.bin` brings up DDR,
  clocks and MIO without Vivado, and U-Boot then loads our bitstream. Our own
  FSBL needs Vivado or `xsct` run once on zeST's PS7 block.

### The whole SoC against the real board

`--target z7` now elaborates against `board.xdc`. Yosys `synth_xilinx` of the
whole design gives **2,408 LUTs (13.7 %), 1,874 FF, 4 DSP, and 19 + 8 BRAM**. The
design is VexRiscv `standard`, 32 KB ROM, 64 KB RAM, 8 KB SRAM, CSRs, JTAG UART,
PLL and `zm_vtiming`. Most of the BRAM is the on-chip test RAM, which moves to
DDR. The bitstream step stops only at openXC7's missing chipdb.

---

## 2026-10-01

### Toolchain: open source and installed

| Need | Installed | How |
|---|---|---|
| Synthesis | Yosys 0.69 (YoWASP, runs as wasm) | `uv` in `fpga/` |
| SystemVerilog to Verilog | sv2v v0.0.13 | `fpga/tools/setup.sh`, checksummed |
| wasm to C | wabt 1.0.42 (`wasm2c`) | `fpga/tools/setup.sh`, checksummed |
| SoC | LiteX 2024.12, migen (git), VexRiscv netlists, picolibc | `uv` |
| Simulation | Yosys CXXRTL (RTL tests), Verilator 5.020 (SoC), Icarus, GTKWave | CXXRTL via `uv`, the rest via apt |
| RISC-V software | riscv64-unknown-elf-gcc 13.2, picolibc; clang and zig cc as alternatives | apt |
| Bitstreams | not yet. openXC7 (Docker) first, Vivado ML Standard as the fallback | when there is a board |

Reused cores are pinned shallow submodules in `fpga/third_party/` (licences in
its README): `jt49`, `VexRiscv`, `neorv32`, `hdmi`, `fx68k`, and
`AtariST_MiSTer` as reference only.

### Measured block costs (Yosys `synth_xilinx`, xc7, before place and route)

| Block | LUT | % of 7010 | FF | BRAM | DSP |
|---|---|---|---|---|---|
| VexRiscv `min` (rv32i) | 1,041 | 5.9 % | 856 | 2 | 0 |
| VexRiscv `lite` (rv32im) | 1,718 | 9.8 % | 1,090 | 4 | 0 |
| VexRiscv `standard` (rv32im + caches) | 2,019 | 11.5 % | 1,363 | 9 | 4 |
| VexRiscv `full` | 2,399 | 13.6 % | 1,569 | 9 | 4 |
| `jt49` (YM2149) | 286 | 1.6 % | 291 | 0 | 0 |
| `fx68k` (68000) | 3,357 | 19.1 % | 1,441 | 2 | 0 |
| `zm_vtiming` (ours) | 64 | 0.4 % | 50 | 0 | 0 |

`hdl-util/hdmi` could not be measured: Yosys rejects its `real` parameters.
Reproduce with `make -C fpga util`.

### Step 0a: carts translate to RISC-V unchanged

`make -C fpga carts`: all 90 `docs/demo-*.wasm` go through wasm2c and compile
for `rv32imf` (zig cc, musl headers). The largest code sizes include each
cart's embedded data: `audio` 2.1 MB (the SNDH player's 68000 tables),
`mpp_truecolor` 1.2 MB, `joust` 0.9 MB. STNICCC is 83 KB.

### Step 0b-i: the whole machine runs as native C, byte-identical

`make -C fpga host-check`: `machine-video.wasm`, `rom.wasm` and each cart are
translated with wasm2c and linked against one shared 7 MiB bounds-checked
memory. The host replays exactly the call sequence of `apps/scene_hash.mjs`.

- **98 PASS, 0 FAIL:** all 89 carts at 1200 frames (sampled every 10) plus 9
  `--call` runs. The JSON matches byte for byte.
- `demo-audio` is refused by node too (memory max 48 pages), so there is
  nothing to compare.
- **Weak spots, shared with `scene_hash.mjs`:** 10 runs show one distinct frame
  for the whole run. stniccc and stream get no disk data (`diskReadBlock`
  returns 0), and gem, st_replay, fullscreen, north_south, dhs_0pxl0reg,
  ulm_dsots and the 3 step-1 `--call` runs probably wait for input. Real tests
  of those need disk serving or scripted input.
- `-ffp-contract=off` is mandatory: an F-extension `fmadd` would round
  differently from wasm.

Commits: `c007033` (doc), `da85e28` (`fpga/`), `a4d086d` (host).

---

## Open decisions for Matt

- **FPU and 7010 vs 7020:** decided by step 0b-ii's table (below, when it lands).
- **GPL in the bitstream:** `jt49` and `fx68k` are GPL-3, so a bitstream that
  contains them is a combined work. That is fine on your bench, but it needs
  deciding before you distribute one.
- **The board package:** `board.xdc` and `ps7_init` go into
  `fpga/boards/microphase_z7_7010/`. Nothing past simulation can start without
  them.
