# ZigMachine on an FPGA

*A feasibility note, 2026-09-20. Nothing here is committed to — it exists so the
question can be argued from facts rather than re-imagined each time it comes up.*

## The shape of the problem

ZigMachine is two halves with a hard line between them, and the two halves have
completely different FPGA stories.

| Half | What it is today | FPGA difficulty |
|---|---|---|
| **The machine** — planes, shifter, per-scanline palette, blitter, YM2149, HBL timing | `machine/*.zig` compiled to wasm | **Solved elsewhere.** This is what FPGAs are for. |
| **The carts** — the programs that run on it | wasm modules | **The whole problem.** An FPGA cannot run wasm. |

The line between them is the sealed memory-mapped ABI, and it is the most
FPGA-friendly decision in the project. Carts talk to registers in shared memory
and cannot reach inside the hardware. That is not an emulation convention — it
is *how real hardware is organised*. `docs/BLITTER_HW_SPEC.md` already reads
like an RTL specification: a register block at fixed offsets, an operation
selector, a BUSY flag, and a cost model.

So the hardware half is mostly a transcription job. Everything below is about
the cart half.

## Prior art, so the hardware half is not argued from first principles

The **MiSTer** project implements a full Atari ST in FPGA — shifter, MMU,
blitter, YM2149, MFP, floppy — and it runs real software. Every chip ZigMachine
models has a known-good open implementation. The ST core is not a research
project; it is a download.

This matters because it converts "can the video and audio be done?" from an open
question into a porting estimate. What ZigMachine adds beyond a stock ST is a
256-colour palette, four planes and a 400x280 raster — all *simplifications* of
the problem an ST core already solved, not new hardware.

---

## Scenario A — soft CPU, carts compiled native

Put a **RISC-V** soft core in the fabric. Drop wasm entirely. Compile carts to
RISC-V with the same Zig/C/Rust toolchains, keep the memory-mapped ABI byte for
byte, and let the hardware be real logic.

**Pros**
- The ABI is unchanged, so every existing scene is a recompile, not a rewrite.
- The polyglot proof already holds: Zig, C and Rust all target RISC-V.
- Soft RISC-V cores are mature, small, and free (VexRiscv, PicoRV32, NEORV32).
- Toolchain risk is near zero — this is the best-supported cross-compile target
  in existence.

**Cons**
- **wasm stops being the distribution format**, so the browser build and the
  FPGA build diverge into two artefacts from one source. The `.zmd` disk format
  would need a native-code cart variant, or a fat format.
- No sandbox. wasm's memory isolation is what makes the machine *sealed*; on a
  soft CPU a buggy cart can scribble anywhere. The seal becomes a convention
  again, enforced by an MPU at best.
- Performance is a real question. A ~100 MHz soft RISC-V is not obviously faster
  than wasm in a browser on a modern laptop; the win is authenticity, not speed.

**Effort:** the largest *piece* but the least *risk*. Bring up a core, write a
linker script, port the ABI headers, boot one cart.

**Problems to solve first:** how `.zmd` carries native code; whether `rom.wasm`
becomes ROM in fabric or a native library; what replaces `--import-memory`'s
shared-memory contract.

---

## Scenario B — a real 68000 core

Put a **68000** (TG68, fx68k) in the fabric instead. Carts become 68000 code.

**Pros**
- The most authentic possible answer. The machine stops *modelling* an ST and
  becomes one.
- **The SNDH player collapses into nothing.** Today it emulates a 68000 (Musashi)
  to run each tune's original replay driver, trapping its PSG writes. On a real
  68000 that driver simply *runs*. An entire subsystem — and its three documented
  silent-failure traps — disappears.
- Real ST binaries could run directly. The `/convert_st` ports stop being ports.
- fx68k is cycle-accurate, so the cycle-counting this project already does
  (`move.w` = 12 cycles = 12 pixels) becomes literally true rather than a model.

**Cons**
- **Zig does not target 68000.** Neither does Rust. Only C has a maintained
  m68k backend (gcc). So the SDK — the thing that makes writing screens pleasant
  — would have to be rewritten, or scenes written in C and assembly.
- That contradicts the project's name and its central proof (a rich Zig SDK with
  C and Rust as equals).
- A 68000 at 8 MHz really is slow. Effects written against a wasm budget would
  need rewriting to fit, which is authentic but is a rewrite of every scene.

**Effort:** moderate in fabric, **enormous** in software. It is not a port; it is
a different project that shares a name.

**Problems to solve first:** the SDK question, and whether the answer is "this is
a second machine" rather than "this is ZigMachine on FPGA".

---

## Scenario C — wasm in fabric

Execute wasm directly: a hardware wasm interpreter, or AOT-compile each cart to a
soft core's instruction set at load time.

**Pros**
- Keeps wasm as the one distribution format. One `.zmd` shelf, every host.
- Preserves the sandbox, and therefore the seal.

**Cons**
- Largely unexplored. There are research papers and a few hobby cores; there is
  no production-grade wasm CPU to download.
- A wasm interpreter in fabric will be slower than the same silicon running
  RISC-V natively, because you pay decode costs forever.
- AOT-at-load-time means shipping a compiler onto the board, which is a large
  software problem wearing a hardware hat.

**Effort:** research-scale. Unbounded.

**Verdict:** interesting, and not the way to get something on a screen.

---

## Scenario D — hybrid: FPGA video/audio, host CPU

Keep the carts running on a real computer (browser or the native host in
`TODOS.md`), and put only the **chips** in fabric — the shifter, blitter and YM —
connected over USB/PCIe, driven by the same register writes.

**Pros**
- The smallest step that produces something genuinely real: the rasters and the
  blits are *actually hardware*.
- No cart changes at all. The ABI already writes to registers; those writes just
  travel further.
- Naturally incremental — do the YM first, hear it, then the blitter.

**Cons**
- The bus latency is the whole design problem. A per-scanline palette write has
  a deadline measured in microseconds; USB does not.
- Probably needs the frame's register writes batched and shipped ahead, which
  changes the timing model from "write when you like" to "submit a display list".
  That is a real ABI change, even if the register names survive.

**Effort:** smallest to start, and the one most likely to produce a demo video.

**Problems to solve first:** latency budget, and whether a display-list model can
be introduced without breaking the "write a register from an HBL" contract that
every scene is built on.

---

## What is actually hard, across all four

1. **wasm is not a CPU.** Every scenario resolves this differently and each
   resolution has a cost: a second artefact (A), a rewritten SDK (B), a research
   project (C), or keeping the CPU off the board entirely (D).
2. **The seal.** wasm's isolation is load-bearing — it is what lets the machine
   be "sealed" rather than merely well-behaved. Only C and D preserve it.
3. **Timing.** ZigMachine's authenticity lives in per-scanline effects. Any
   architecture that adds latency between the cart and the palette register
   breaks the thing worth building.
4. **Assets.** `.zmd` disks, ZX0 packing and the ROM are all wasm-shaped today.
   They would need a native equivalent in A and B.

## If it were to be tried

**D first, then A.** D gets a YM2149 singing from real fabric in a weekend-ish
project and proves the register model survives the trip. A is the one that could
become a whole machine on a board, and its risk is mostly clerical.

B is the romantic answer and is worth being honest about: it would be a superb
*Atari* project and a poor *ZigMachine* one, because it throws away the Zig SDK
that is the reason this project exists.

## See also

- `docs/BLITTER_HW_SPEC.md` — already written as a hardware spec
- `docs/HARDWARE_SPEC.md`, `docs/HW_API.md` — the register model
- `TODOS.md`, "A native desktop host" — the same portability argument, one step
  short of hardware, and a sensible prerequisite
- `docs/IDEAS.md` — where this started as a parked idea
