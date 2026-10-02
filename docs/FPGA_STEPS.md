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
| 1–7 | Board work (scanout, YM, CPU, HBL, blitter, ROM, SNDH) | waiting | needs the MicroPhase board package (`fpga/boards/…/README.md`) |
| RTL | Video timing (`zm_vtiming`) | **done** | 64 LUTs, CXXRTL-tested over 2 frames |
| RTL | Video compositor, planes and palettes | *running* | — |

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
