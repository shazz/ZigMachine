# An audio CPU for the SNDH player: softcore survey

**Status (2026-10-09): not built.** For now the SNDH player (Musashi, the 68000 emulator, through wasm2c)
runs **in software on the cart CPU** (Matt's decision; ADR in `decisions.md`). A dedicated audio CPU comes
later, and possibly a second sound chip. This page records the options for when we get there.

## Why one would be needed

The cart CPU runs the cart, the machine and the sequencer in one frame: 1.67 M cycles at 100 MHz for
60 fps. A 50 Hz SNDH replay routine is cheap. Digidrum tunes are not: their MFP timers fire thousands of
times a second, and each interrupt runs through Musashi. The cost per frame of an easy tune and of a heavy
one is measured with the audio-in-SoC work. That number decides whether an audio CPU is needed at all,
and how big it must be.

## The candidates

LUT counts are for Xilinx 7-series. The 7010 has 17,600 LUTs; the board SoC with the blitter uses about
9.6K.

| Core | ISA | LUTs | FFs | Speed | Fit for Musashi |
|---|---|---|---|---|---|
| **SERV** | RV32I, bit-serial | **~200** | — | ~32 clocks per instruction (~1/30 of a pipelined core) | too slow: Musashi runs many RISC-V instructions per 68000 instruction |
| **PicoRV32** | RV32I(M) | ~1,000 | — | 3-4 clocks per instruction | works, but slow per LUT |
| **FemtoRV** (variants) | RV32I(M) | < 1,280 (IceStick budget) | — | multi-cycle | same class as PicoRV32 |
| **VexRiscv "small and productive"** | RV32I | **816** | 534 | 0.82 DMIPS/MHz, 232 MHz | **good fit**: our `vexgen` flow already generates VexRiscv |
| **VexRiscv "small and productive" + 4 KB I$** | RV32I | 730 | 570 | 0.70 DMIPS/MHz, 220 MHz | good fit if it runs from DDR |
| **VexRiscv "full, no cache"** | RV32IM | 1,418 | 949 | 1.21 DMIPS/MHz, 216 MHz | headroom for heavy digidrum tunes |
| **VexRiscv "full"** (4 KB I$/D$) | RV32IM | 1,840 | 1,158 | 1.21 DMIPS/MHz, 199 MHz | the comfortable choice from DDR |
| **fx68k** (a real 68000, cycle-exact) | 68000 | **3,357** (measured here) | — | the real chip's timing | runs SNDH natively, no Musashi; GPL-3; the largest |

The VexRiscv numbers are from the VexRiscv README (Artix-7). fx68k was measured with this repo's Yosys flow
(`docs/ZIGMACHINE_IN_FPGA.md`).

## Recommendation

**A small VexRiscv, 0.8-1.8K LUTs.**
- It's the same generator, toolchain and seal work as the cart CPU (`fpga/vexgen`).
- It can run faster than the cart clock if needed.
- RV32IM ("full") gives headroom for digidrum tunes; RV32I is enough for 50 Hz replays.

**The CPU is the cheap part; memory is the real cost.** Musashi, the SNDH file and the 68000's RAM add up
to roughly 100-200 KB, and block RAM is tight on the 7010. So the audio CPU would most likely run from
DDR, through the last free HP port (HP3: HP0 is the cart CPU, HP1 the video DMA, HP2 the blitter), with a
small instruction cache. It would sit inside the same 32 MiB cart window as everything else
(`soc/zm_hp.py` `ddr_addr`).

**fx68k only wins** if a tune needs cycle-exact 68000 timing (some digidrum tricks). It costs 2-4× the
LUTs, and as GPL-3 it makes the bitstream a combined work.

## Sources

- [VexRiscv: configurations and their area/performance on Artix-7](https://github.com/SpinalHDL/VexRiscv)
- [PicoRV32 README](https://software.mcgoron.com/Hardware/picorv32/raw/commit/7fd24a96b21b1bff6f58ae1132814f4bea38ffbe/README.md)
- [FemtoRV README (with the SERV comparison)](https://gitlab.rhrk.uni-kl.de/pena/learn-fpga/-/blob/af66c2f7db064aaba57f8de29b7b4508b76af1fe/FemtoRV/README.md)
- [OpenCores 68000 cores (TG68, ao68000)](https://opencores.org/usercontent/doc/1397504713)
- fx68k: measured in this repo (`docs/ZIGMACHINE_IN_FPGA.md`)
