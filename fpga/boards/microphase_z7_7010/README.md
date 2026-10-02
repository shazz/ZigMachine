# MicroPhase Z7-Lite, XC7Z010-1CLG400

`tools/fetch_board.sh` fetches everything below, pinned to commits and
checksummed. **None of it is committed:** MicroPhase's XDC carries "Publication
of this design is not authorized without written consent from MicroPhase", and
zeST is GPL-3. `.gitignore` keeps `board.xdc`, `vendor/` and any `ps7_init*`
out of git.

| File | Source | Used for |
|---|---|---|
| `board.xdc` | MicroPhase's `Z7_LITE.xdc` (Vivado 2018.3, 2022), via `leecurrent04/MicroPhase-Z7-Lite-Board` | every PL pin. `soc/platform_z7.py` reads it, so no pin is typed anywhere else |
| `vendor/Z7-LITE_R11.pdf`, `vendor/Z7-Lite_Reference_Manual.md` | MicroPhase's own `fpga-docs` on GitHub | the schematic and the manual: clocks, DDR part, pin tables |
| `vendor/xc7z010clg400pkg.txt` | Xilinx's package file | maps a pin *function* (as the schematic names it) to a ball |
| `vendor/zest/` | [zeST](https://codeberg.org/zerkman/zest) (GPL-3), an Atari ST on this exact board | its Z7-Lite XDC and its Vivado PS7 configuration (`zest_z7lite.tcl`) |
| `vendor/zest-bin/…/boards/z7lite_7010/boot.bin` | zeST release 20260518 | **a working PS7 init (DDR3, clocks, MIO) without Vivado:** its FSBL and U-Boot bring up the ARM side |

## Verified

- **Three public copies of the MicroPhase XDC have the same pin map** (103 ports):
  `leecurrent04`, `hw/Microphase-Z7-Lite`, `tcmichals`.
- **Every HDMI pin was re-derived independently from the schematic** and the
  Xilinx package file, and matches the XDC: CLK U18/U19, D0 V20/W20, D1 T20/U20,
  D2 N20/P20, HPD P19, SCL R19, SDA T19 (TMDS_33). zeST's own XDC agrees.
- **Clocks:** `PL_CLK_50M` is on N18 (50 MHz, PL). The PS crystal is 33.333 MHz
  on E7.
- **DDR3:** one 16-bit MT41J256M16 (512 MB). The manual's pin table has D0–D15
  only, and zeST's PS7 config says `16 Bit`, `MT41J256M16 RE-125`. One community
  `preset.xml` claims 32 bits: it is wrong for this board.
- **UART:** PS MIO14/15 only, so the ARM owns it. The VexRiscv console on the
  `z7` target is `jtag_uart`, over the board's USB-JTAG.
- **`make soc` and `--target z7`** elaborate against this XDC. A Yosys synthesis
  of the whole SoC gives 2,408 LUTs (13.7 %), 1,874 FF, 4 DSP and 19 + 8 BRAM.

## The ARM side (`ps7_init`)

There is no `ps7_init.c` for the **7010** in any public repo:
`BeatSkip/Z7-Lite-Z7020-Linux` has one for the 7020 with a different DDR part.
Two routes:

1. **No Vivado (recommended first):** boot zeST's `boot.bin` for the 7010. Its
   FSBL initialises DDR, clocks and MIO, and U-Boot can then load our bitstream
   (`fpga load`) or Linux can, through the FPGA manager.
2. **Our own FSBL:** generate `ps7_init` once with Vivado or Vitis `xsct` from
   zeST's `zest_z7lite.tcl` PS7 block (zeST's `setup/recipes/fsbl.sh` does
   exactly this).
