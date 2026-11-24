# PEREGRINE: what differs from KESTREL

PEREGRINE is the ZigMachine on the **same MicroPhase Z7-Lite PCB** as KESTREL, with a Zynq XC7Z020-1CLG400C
instead of the XC7Z010. Everything not listed here is KESTREL's: the cart ABI (`docs/hardware/ABI_RULES.md`,
one for both boards), the SD card layout, glass, the kernel and rootfs, the SoC's RTL. The board directory
`fpga/boards/microphase_z7_7020/README.md` has the build commands, the boot-chain evidence and the day-1
checklist; `PEREGRINE_IDEAS.md` (here) is what the extra fabric might go to (R84, R85).

## The chip

| | KESTREL (XC7Z010-1) | PEREGRINE (XC7Z020-1) |
|---|---|---|
| LUT / FF | 17,600 / 35,200 | 53,200 / 106,400 |
| Block RAM (RAMB36) | 60 | 140 |
| DSP48E1 | 80 | 220 |
| PL I/O banks | 34, 35 (HR) | 34, 35 (HR) + 13 (HR, not wired to anything the board file names) |
| PS | dual Cortex-A9, 512 MiB DDR3 (one MT41J256M16) | the same |
| IDCODE | 0x03722093 | 0x03727093 |
| openXC7 chipdb | pinned (`make toolchain`) | none yet: Vivado only |

## The build

- `make BOARD=peregrine ...`: the part, `board.xdc` (KESTREL's, every ball checked on both chips by
  `fpga/tools/board_xdc.py`) and `fpga/build/peregrine/`.
- The release SoC's parameters are `fpga/soc/boards.py` `Board.soc`. Today PEREGRINE's are KESTREL's v1.3
  (ZIGGY I$/D$ 16 KiB 2-way + f32 FPU + ZM-X, BARD SndNdD16Dyn8Sx, CHISEL, posted stores, prefetch refills,
  sys 100 / comp 125 MHz, the `fit_timing` directives). Each change for PEREGRINE is a new `SocParams`
  value, measured first (R85).

## The boot

- **`BOOT.BIN` is the one part-specific boot file.** zeST's image embeds a bitstream its FSBL loads
  before U-Boot; the 7010's fails on a 7020. PEREGRINE boots zeST's `z7lite_7020/boot.bin` (or plan A's
  SPL image, which carries no bitstream). `fpga/tools/card.py stage --boot-dir` refuses the wrong one.
- `zigmachine.bit` is per board (U-Boot refuses a .bit for the other part); `KESTREL/BOARD` says
  `peregrine`, and a card staged for one board refuses to install on the other.

## The first PEREGRINE bitstream (KESTREL's SoC on the 7020)

`make BOARD=peregrine bitstream`, 24 Nov 2026 (branch feat/peregrine-prep, Vivado 2026.1, `fit_timing`:
AreaOptimized_high synthesis, so the LUTs are the area-optimised count; a default synthesis was ~1,100 LUT
more on KESTREL). 40 min, placed and routed first try, every constraint met. The .bit is 4,045,766 bytes
(KESTREL's ~2 MB), IDCODE 7z020.

| Resource | Used | 7020 total | % | Free | On the 7010 (its totals; slices from its 10-11 Nov builds; BRAM/DSP: the same netlist, inferred) |
|---|---|---|---|---|---|
| LUT after synthesis | 17,018 | 53,200 | 32.0 | 36,182 | 17,600 total: the 7010 is full |
| LUT placed | 15,823 | 53,200 | 29.7 | **37,377** | |
| of which LUT as memory | 866 | 17,400 | 5.0 | | |
| Flip-flops | 15,934 | 106,400 | 15.0 | 90,466 | |
| Slices | 6,515 | 13,300 | 49.0 | 6,785 | 4,400 / 4,400 (100 %) |
| Block RAM (RAMB36 tiles) | 44 | 140 | 31.4 | 96 | 44 / 60 |
| DSP48E1 | 72 | 220 | 32.7 | 148 | 72 / 80 |

| Clock | Period | WNS (setup) | WHS (hold) | KESTREL |
|---|---|---|---|---|
| sys (ZIGGY, bus) 100 MHz | 10 ns | **+0.352 ns** | +0.018 | +0.011 ns (11 Nov lut-diet build, one seed) |
| comp (FRESCO) 125 MHz | 8 ns | +0.553 ns | +0.029 | |
| pix 40 MHz | 25 ns | +1.178 ns | +0.061 | |
| pix5x 200 MHz | 5 ns | +0.555 ns | +0.168 | |
| crossings (worst: sys -> comp) | | +1.271 ns | | |

TNS 0 on 46,893 endpoints, THS 0. On the 7020 the same SoC uses under a third of the fabric and closes 100 MHz
with +0.35 ns of setup slack where KESTREL had +0.01. R85's budget: ~36,000 LUT, 96 RAMB36 and 148 DSP
free before anything is taken out, and the timing slack says sys above 100 MHz is worth a sweep (`--sys-mhz`, a `SocParams` field).
