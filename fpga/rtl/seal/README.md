# `rtl/seal/`: the cart CPU's bus windows

The seal answers REVIEW_FABLE.md finding 2 and the ADR "the seal is a hardware
bus window" (`decisions.md`, 2026-10-02). The cart, the ROM and the firmware all
run on one VexRiscv, and the board build drops wasm2c's bounds checks
(`CYCLES.md`, `aligned`). Without the seal, a wild wasm offset reaches the video
`cmd`/`mem_base` CSRs, the UART, the firmware's state, or any DDR the HP port
maps.

## The mechanism: U-mode, plus windows checked in the core's translation slot

| Piece | Where |
|---|---|
| The decision: may this address be read, written or executed, by U or by M | `zm_seal.v`, map in `zm_seal_map.vh` |
| The core: `CsrPlugin` with `userGen`, `catchIllegalAccess` and `mscratch`, and `ZmSealPlugin` in place of `StaticMemoryTranslatorPlugin` | `vexgen/src/main/scala/zm/ZmSealPlugin.scala`, `vexgen/gen.sh <spec>:seal` |
| Tests | `tests/test_rtl_seal.py` (CXXRTL), `tests/test_seal_core.py` + `tests/seal/` (Verilator, the whole core) |

The firmware runs in M. It enters the cart (`frame()`, an HBL handler, an
export) with `mret` to U, and the cart comes back through a trap. A trap is the
only way into M, and the cart cannot fake one.

**Why this choice and not the others:**

- **A privilege bit the firmware sets in a CSR outside the core.** Something
  has to clear the bit again on the way back in, and only the core knows when it
  takes a trap. A bit sampled outside the core also disagrees with the core's
  privilege for the stores still in flight at the switch: the D$ write path has
  two pipe registers before the bus. A cart could then write `sw; ecall` and the
  store would be judged as M's. The core's own privilege register has neither
  problem. A trap or an `mret` flushes the pipeline, so every access is judged
  with the privilege of the instruction that made it. `tests/seal/` checks a
  store placed right before an `ecall`.
- **VexRiscv's PMP (`PmpPlugin`/`PmpPluginNapot`).** It does the same job with
  CSR-programmable regions, so it costs comparators per region and adds a
  locking story. Our windows are fixed at elaboration. Read-only (by reading
  the pinned source, not tested): the PMP plugins report `isPaging = False`, and
  VexRiscv's DataCache ignores translation permissions on its uncached (IO) path
  unless the translation is paging. So a U access to the CSR bus that PMP
  denies would still go out. `ZmSealPlugin` says paging on the data side for
  that reason (below).
- **A window decoder on the Wishbone bus after the core.** A Wishbone `err`
  is not seen on a write-through store, and the decoder does not know the
  privilege. The translation slot sees both, and a "no" there suppresses the
  access in the core, so it never reaches the bus.
- **Keeping the bounds checks** costs about 36 % of the cart's cycles
  (`CYCLES.md`).

## The windows (`zm_seal_map.vh`)

| Window | Cart CPU address | Size | U | M |
|---|---|---|---|---|
| firmware | `0x4000_0000` | 8 MiB | none | rwx |
| code: cart + ROM text, and the libgcc/memcpy they call | `0x4080_0000` | 8 MiB | **x only** | rwx |
| rodata: their constants and jump tables | `0x4100_0000` | 4 MiB | r | rwx |
| data: their instance structs and globals, the U stack | `0x4140_0000` | 4 MiB | rw | rw, no x |
| linear: the machine's 7 MiB wasm memory | `0x4180_0000` | 8 MiB | rw | rw, no x |
| video: the compositor's register window | `0x9000_0000` | 8 MiB | rw | rw, no x |
| everything else: boot ROM, SRAM, CSR bus, other DDR | | | none | rwx |

- Nothing is both writable and executable for U.
- M never executes from a window U can write, so a firmware jump through a
  pointer the cart made cannot run cart data.
- A window is a power of two, aligned to its size, so a hit is one compare of
  the top address bits.

## Traps the firmware sees

| mcause | Meaning |
|---|---|
| 1 | U fetched outside the code window. This is also **the call gate**: the cart calls a firmware function (a wasm import) with a plain `jal`, the fetch faults, and the handler checks that `mtval` is a registered entry point, runs it in M, and `mret`s to `ra`. Nothing in the cart's code changes. |
| 13 / 15 | U loaded or stored outside its windows (the data port reports paging, see `ZmSealPlugin.scala`). The access did not reach the bus. |
| 5 / 7 | A real bus error. |
| 2 | U touched an M CSR, or ran `mret`. |
| 8 | `ecall` from U. |

## What the firmware must do (the seal only works if it does)

- **Link into the windows.** Cart, ROM, libgcc and memcpy text go into code.
  Their `.rodata` goes into rodata. Their `.data`, `.bss` and the U stack go
  into data. The wasm memory goes into linear, not `calloc`'d from the
  firmware heap. Firmware code, data and the M stack go into firmware.
  `tests/seal/link.ld` is the shape.
- **Never trust U's registers on a trap.** Swap `sp` with `mscratch` first.
- **Act for the cart only inside its windows.** The misaligned-access emulator
  (`cycles/trap.c`) and any import that takes a linear-memory pointer
  (`hwBlit`) run in M. They must check the address against the same map before
  touching it, or they are a confused deputy. `gen`-style export of
  `zm_seal_map.vh` to a C header is the way to share it (not done yet).
- **Bound the HP path too.** The seal stops U. M can still reach any DDR the HP
  port maps, so the HP bridge should add a fixed base and mask to 32 MiB.

## Costs (measured)

- **LUTs (Yosys `synth_xilinx`):**
  - `standard` 4K/4K: 2,038 → 2,051 LUT, 1,367 → 1,406 FF.
  - Board core 16K 2-way I$ + 4K D$: 2,066 → 2,150 LUT, 1,369 → 1,408 FF.
  - The FFs are mostly `mscratch`.
  - BRAM, DSP and CARRY4 are unchanged.
- **Cycles per access:** none. The check sits in the existing translation slot
  and adds no pipeline stage.
- **Cycles per gate**, in Verilator with a one-wait-state memory, including a
  3-instruction loop:
  - An `ecall` round trip (save 2 registers, `mepc += 4`, `mret`) is 45.8
    cycles.
  - A call through the fetch-fault gate is 50.5 cycles.
  - A real gate saves more registers, so add about 2 cycles per register.
  - At about 1,400 HBL handler calls a frame (280 lines × 5), the worst case is
    about 70k cycles, 2.8 % of a 2.5 Mc frame at 150 MHz. Typical carts make a
    few gates a frame.
- **fmax:** no loss. Under openXC7 the glass SoC reaches 81.2 MHz with the sealed I16w2D4 core and 79.4 MHz with LiteX's `standard` (`fpga/README.md`, *Timing under openXC7*).
