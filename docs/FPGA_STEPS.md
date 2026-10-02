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
| 0b-ii | Cycles per frame on a real VexRiscv (Verilator) | *running* | — |
| — | Board files (XDC, schematic, PS7 bring-up) | **done** | `fpga/tools/fetch_board.sh`, gitignored; HDMI pins re-derived from the schematic |
| — | Whole SoC elaborated against the real board | **done** | 2,408 LUTs (13.7 %) synthesised |
| 1–7 | Board work (scanout, YM, CPU, HBL, blitter, ROM, SNDH) | ready to start | needs the board on the bench and openXC7's chipdb |
| RTL | Video timing (`zm_vtiming`) | **done** | 64 LUTs, CXXRTL-tested over 2 frames |
| RTL | Video compositor: planes, palettes, border, BEAM, all modes | **done** | **32/32 frames pixel-identical** to the machine; 25/25 mutants caught; 1,169 LUTs |

---

## 2026-10-02

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
