# ZigMachine on an FPGA

*A feasibility note, first written 2026-09-20 and retargeted 2026-10-01 to a real
board. Nothing here is committed to. It exists so the question can be argued
from facts rather than re-imagined each time it comes up.*

## The target

**MicroPhase Z7 board, Xilinx Zynq XC7Z010.** The fantasy console runs in the
programmable logic (PL). The dual Cortex-A9 (PS) does **I/O only**: boot,
SD card, USB keyboard/pad, network and UART. It never runs a cart, never
touches a register on a scanline deadline, and is not on the video or audio
path.

| XC7Z010-1 resource | Amount | What it means here |
|---|---|---|
| LUTs / flip-flops | 17,600 / 35,200 | **The binding constraint.** Small: about a third of a 7020. |
| Block RAM | 60 × 36 Kb ≈ 270 KB | Line buffers, palettes, caches and the ROM. Not framebuffers. |
| DSP48 | 80 | Blitter and audio multiplies, an FPU's mantissa multiplier. |
| PS DDR3 | board-dependent (typically 512 MB) | Holds everything big. The PL reaches it through the four 64-bit AXI HP ports. |
| PS peripherals | USB, SD, Ethernet, UART | The ARM's whole job. |

*The DDR size and the video connector (HDMI or a PMOD) depend on the exact
MicroPhase variant, so check them against its schematic before you rely on them.*

The machine's shared memory is **7 MiB** (`build.zig`, `video_shared_bytes`):
the 2 MiB cart window, VRAM, the physical framebuffer and the 2 MiB ROM window.
All of it lives in DDR. Four planes of 400×280 8-bit pixels are 448 KB, which
is more than all the BRAM on the chip. So the scanout is a DMA master that
streams each line from DDR into a BRAM line buffer ahead of the beam. That costs
roughly 30 MB/s, which is nothing for an HP port.

---

## The question: a RISC-V core, or a wasm softcore?

**RISC-V.** The cart format stays wasm, and wasm is translated to RISC-V
**before** it reaches the board. The fabric never sees a wasm opcode.

### Why not a wasm softcore

1. **Nothing exists to download.** There are research papers and hobby cores,
   but no maintained, verified wasm CPU. You would be building the CPU *and* the
   console, and debugging each against the other.
2. **wasm is a hostile ISA for hardware.** It has LEB128 variable-length
   immediates and a typed operand stack, so you need stack caching or poor IPC.
   Its structured `block`/`loop`/`br` needs a label stack resolved at decode,
   and `call_indirect` type-checks against a table. It was designed to be
   *compiled*, not executed. A wasm core loses to a RISC-V core of the same LUT
   count on every axis.
3. **You cannot subset it.** The carts use the whole numeric spec: `f32`
   appears in 156 files under `apps/zig/scenes` + `libs/zig`, `f64` in 90 and
   `i64` in 124. A wasm core must execute all of that in hardware or trap to
   software, and a core that traps to software is a RISC core plus a decoder.
   A RISC-V toolchain decides per type instead: hardware `f32`, soft `f64`,
   `i64` as register pairs, with no cart changes.
4. **It does not fit.** On a 17.6K-LUT part the CPU budget is a few thousand
   LUTs (see the budget below). A wasm core with `i64`/`f32`/`f64` would eat the
   whole chip before the shifter existed.

The one real argument *for* a wasm core was the original Scenario C: keep wasm
as the single distribution format, and keep the sandbox. Translation keeps the
format, and the fabric enforces the sandbox better than wasm does (next section).
So that argument does not survive.

### How a wasm cart becomes RISC-V

`cart.wasm` goes through **wasm2c** (WABT, mature). The C comes out sandboxed
and deterministic. It is then compiled by clang for `rv32imf` and linked against
the native ROM to give `cart.rv32`.

- **One pipeline for all three languages.** Zig, C and Rust carts all go through
  it unchanged. The polyglot proof survives, because nothing downstream knows
  which language produced the wasm.
- **The `.zmd` disk becomes a fat disk.** The wasm cart (canonical, what the
  browser runs) and its `rv32` translation sit side by side, produced by
  `tools/mkdisks.sh`. The `rv32` blob is ZX0-packed like everything else on the
  shelf.
- **Option: translate on the ARM at load time.** That puts a compiler on the
  board, but the ARM is otherwise idle and loading a cart off SD *is* I/O. Do
  this only once build-time translation works.
- **Later, for a hot cart:** compile its Zig directly for `riscv32-freestanding`
  and skip wasm2c's bounds checks. That is a per-cart optimisation, not the
  architecture.

### The seal, enforced by the bus instead of by wasm

wasm's isolation is what makes the machine *sealed*. On the FPGA the seal moves
into the interconnect, and it gets stronger:

- The cart CPU's AXI master is **wired** to see only the 2 MiB cart window, the
  VRAM, the register block and the ROM (execute-only). Anything else returns a
  bus error, which raises the error trap. Machine state that is not a register
  has no address at all, so a buggy cart physically cannot reach it.
- RISC-V PMP (NEORV32 has it, VexRiscv optionally) adds the ROM's
  execute-only rule and catches wild jumps.
- Once the bus enforces the seal, wasm2c's own bounds checks are belt and
  braces. Keep them until the bus window is proven.

---

## The machine in fabric

| Block | Source | Notes |
|---|---|---|
| Cart CPU | VexRiscv or NEORV32, `rv32imf`, I/D caches in BRAM | ~150 MHz on a -1 Artix-7 fabric is realistic for VexRiscv. Interrupt on every line start = HBL handlers, natively. |
| Video | new RTL from `docs/HARDWARE_SPEC.md` | Plane fetch, compositor, 256-colour palettes, `zg.copper` / `zg.linepal` as hardware lists, earned overscan (`flickerBorder()` becomes real res-flicker timing). |
| Blitter | new RTL from `docs/BLITTER_HW_SPEC.md` | Already written as a register spec with a cost model. |
| YM2149 + PCM | MikeJ's YM2149 (VHDL) or jotego's `jt49` (Verilog): a few hundred LUTs, the cheapest block on the chip. Plus the 4-channel PCM engine (`machine/audio/engine.zig`), with its channels time-shared through one DSP48 MAC. | Audio out over HDMI (data islands cost LUTs), I²S to a PMOD DAC, or PWM on a pin as a first step. |
| ROM | `rom.wasm` translated to `rv32`, in BRAM/flash | Phase 2's "ROM chip" literally becomes one. Carts call it through a fixed jump table, as TOS did. |
| Display | DVI/HDMI TMDS (OSERDES) | **800×600 @ 60 Hz, 40 MHz pixel clock.** 400×280 scaled ×2 is 800×560, so the bars are 20 lines. Integer scaling, no filter, and one logical line is exactly two output lines. |
| ARM side | Linux (Buildroot/PetaLinux), AXI GP for control, shared DDR | USB HID is the reason for Linux. It writes keyboard and pad state into machine registers, and loads `.zmd` files off SD into DDR. |

**Scenario D's timing problem disappears.** With the CPU and the shifter both
in fabric, a per-scanline palette write has no bus between them. At 150 MHz and
~19 kHz logical lines, an HBL handler gets roughly **7,900 cycles a line**.

### The SNDH player: the one subsystem that does not map cleanly

SNDH music is a 68000 emulator (Musashi, in `demo-audio.wasm`) running each
tune's original replay code. On the board there are three options:

1. **Musashi on a second, small RV32IM core** (no FPU, ~1.5K LUTs). A plain
   50 Hz replay uses maybe 10–20 % of an 8 MHz 68000. At ~50 host instructions
   per 68000 instruction that is 5–10 M instructions a second, comfortable at
   150 MHz. Timer digidrums at several kHz are the stress case, so measure them.
2. **A real 68000 core (fx68k: **3,357 LUTs measured**, 19 % of a 7010) as the audio coprocessor.** This is
   Scenario B's best idea without its worst one: the replay drivers *run*,
   cycle-exact, and the SDK stays Zig. It probably does not fit a 7010
   alongside everything else, but it is the obvious upgrade on a 7020.
3. Musashi on the main cart core: no. It would steal frame time
   unpredictably.

**Start with option 1.**

---

## LUT budget

*Rows marked **measured** come from `make -C fpga util` (Yosys `synth_xilinx`,
pre-place-and-route, within ~10–20 % of Vivado). The rest are still estimates.*

| Block | LUTs |
|---|---|
| Cart CPU, VexRiscv `standard` (`rv32im` + caches) | **2,019 measured** (9 BRAM, 4 DSP) |
| ...its FPU | **0: not needed** (step 0b, `fpga/CYCLES.md`) |
| Audio CPU, VexRiscv `lite` (`rv32im`) | **1,718 measured** |
| Video: compositor (planes, palettes, border, BEAM, all modes) | **1,169 measured** (4 BRAM, 1 DSP; `fpga/rtl/video`) |
| Video: scanout buffer, plane mixer, copper/linepal, AXI bursts | 1,000 – 2,000 |
| Blitter | 2,000 – 4,000 |
| YM2149 (`jt49`: **286 measured**) + the 4-channel 44.1 kHz PCM engine, one time-shared DSP48 MAC | 500 – 1,000 |
| TMDS encoder | ~500 |
| AXI interconnect, HP masters, PS glue | 2,000 – 3,000 |
| **Total** | **~11,000 – 16,000** of 17,600 |

**The reading after step 0b (2026-10-02): the 7010 fits, with no FPU.**

The cart CPU's real load was measured on VexRiscv in Verilator, with hashes
identical to the wasm machine (`fpga/CYCLES.md`):

- **Clock: 150 MHz.** It covers the realistic sample carts with ~25 % margin,
  where 100 MHz misses three of them.
- **No FPU.** The carts that fit barely use floats. The two float-heavy ones
  (polkadots, replicants_emlyn) are CODEF ports that kept JavaScript's `f64`, so
  an `f32` FPU would not touch them. Fixing them is a scene change.
- **Cheaper wins than an FPU,** both measured: aligned word loads with the rare
  misaligned access trapped and emulated (−4…40 %), and dropping wasm2c's bounds
  checks now that the bus window is the seal (−36 %).
- **The open risk is memory, not compute.** The simulation's RAM answers in one
  cycle. With DDR behind the PS, cache refills and the write-through store
  stream could cost up to ~2.5× on store-heavy carts. That makes the D-cache
  policy and the HP-port write path the next design question.

A **7020** stays the upgrade path for the 68000 SNDH coprocessor (fx68k, 3,357
LUTs).

---

## The plan, smallest provable step first

0. **Measure, without hardware.** *0a is done* (`make -C fpga carts`): all 90
   carts translate with wasm2c and compile for `rv32imf` unchanged. *0b is done*:
   the whole machine runs as native C, byte-identical (`make -C fpga host-check`),
   and on VexRiscv in Verilator with cycles per frame measured
   (`fpga/CYCLES.md`): 150 MHz, no FPU.
1. **Scanout.** The ARM fills a framebuffer in DDR, and the PL streams it over
   HP to 800×600 HDMI. This proves the DDR → line buffer → TMDS path.
2. **YM2149 in fabric, register-driven from the ARM.** You hear real hardware
   early. This is Scenario D's weekend project, done on-chip.
3. **The cart CPU plus one C cart** (`apps/c` hello world) through the
   memory-mapped ABI, with the bus-window seal from day one.
4. **HBL interrupts, copper, linepal and earned overscan.** This is where the
   authenticity lives.
5. **Blitter**, from its spec.
6. **The native ROM, the `.zmd` loader on the ARM, and the menu.** The shelf
   boots.
7. **SNDH** on the audio core.

**The test oracle already exists.** `apps/scene_hash.mjs` fingerprints scenes
byte for byte against the wasm machine. Run the RTL plus the translated cart in
Verilator on the desktop, dump the same frames, and compare. Every scene that
matches its wasm fingerprint is proven before it ever touches the board, and
the browser build stays the reference implementation.

---

## Toolchain: open source, with Vivado as the fallback

The XC7Z010 is one of the best-covered Xilinx parts in the open flow, because
Project X-Ray documented its bitstream early.

| Stage | Tool |
|---|---|
| Synthesis | **Yosys** (`synth_xilinx`). VHDL via the GHDL plugin (MikeJ's YM2149), SystemVerilog via sv2v. |
| Place & route + bitstream | **nextpnr-xilinx** + Project X-Ray, packaged together as **openXC7** |
| SoC | **LiteX**: VexRiscv/NEORV32, buses, video, a Zynq-7000 PS wrapper. It targets openXC7 *and* Vivado. |
| Simulation | **Verilator** (the scene-fingerprint oracle), GHDL, cocotb |
| Software | clang/Zig for `rv32imf`, wasm2c, and Linux + U-Boot on the ARM |

**The weak spots, to check against the current state of openXC7:**
- **PS configuration.** `ps7_init` (DDR timings, clocks, MIO) is normally
  generated by Vivado, so take it once from the board vendor's package.
- **Timing closure.** It is weaker than Vivado's, which matters near 150 MHz
  with an FPU.
- **Primitive coverage.** Check OSERDES (TMDS) and the PS7 HP ports.

**Vivado ML Standard** (free, not open, supports the 7010) is the fallback for
any of these. Because LiteX builds with either flow, switching costs one option.

---

## The earlier scenarios, for the record

The first version of this note argued four architectures without a board.
Given the 7010 and "ARM for I/O only", this is where each one lands:

- **A, soft RISC-V with native carts:** **chosen.** Its two cons were "wasm
  stops being the distribution format" and "no sandbox". The first is answered
  by translating at build time into a fat `.zmd`, the second by the bus-window
  seal.
- **B, a real 68000 core running the carts:** still rejected for carts. Zig and
  Rust do not target m68k, so the SDK would be thrown away. It survives in a
  smaller role as the optional SNDH coprocessor.
- **C, wasm in fabric:** rejected, for the four reasons above. Translation gets
  its benefits without its costs.
- **D, chips in fabric with a host CPU over USB:** rejected as an architecture,
  since the CPU is on the board now. It survives as plan step 2.

## Prior art

The **MiSTer** project implements a full Atari ST in FPGA: shifter, MMU,
blitter, YM2149, MFP and floppy, and it runs real software. Every chip
ZigMachine models has a known-good open implementation to read. What ZigMachine
adds (a 256-colour palette, four planes, a 400×280 raster) *simplifies* what an
ST core already solved. MiSTer targets a Cyclone V with ~110K LEs, though, so
borrow its designs, not its budget.

## See also

- **`fpga/`**: the working tree for all of this (setup, the memmap export, RTL
  and tests, the LiteX SoC, the cost tool, cart translation). See its README.
- `docs/FPGA_GLASS.md`: the ARM side, MiSTer-style: SD card, cart loading,
  USB input and the OSD menu

- `docs/HARDWARE_SPEC.md`, `docs/HW_API.md`: the register model, the RTL's spec
- `docs/BLITTER_HW_SPEC.md`: already written as a hardware spec
- `docs/PHASE2_ROM_CHIP.md`: the ROM that becomes a real ROM
- `machine/sdk/memmap.zig`: the single source of truth for the bus map
- `TODOS.md`, "A native desktop host": the same portability argument, one step
  short of hardware. wasm2c is a good way to build it, and it doubles as plan
  step 0.
