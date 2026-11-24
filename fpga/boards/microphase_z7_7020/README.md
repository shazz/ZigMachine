# PEREGRINE: MicroPhase Z7-Lite with a Zynq XC7Z020-1CLG400C

KESTREL's big brother (ordered 14 Nov 2026). The vendor's manual (`../microphase_z7_7010/vendor/
Z7-Lite_Reference_Manual.md`) sells the Z7-Lite as ONE PCB in two versions: XC7Z010-1CLG400C or
XC7Z020-1CLG400C, the same DDR3, the same CLG400 package. So the part is `xc7z020clg400-1` (speed
grade -1, from the manual), and the pinout is KESTREL's.

- `make BOARD=peregrine ...` selects this directory (`fpga/boards/boards.mk`, `soc/boards.py`).
- Not tracked (like KESTREL's): `board.xdc` and `vendor/`. `tools/fetch_board.sh peregrine` makes both.

## board.xdc: KESTREL's, checked ball by ball (24 Nov 2026)

`tools/board_xdc.py derive kestrel peregrine` writes this directory's `board.xdc` from KESTREL's after
checking every `PACKAGE_PIN` against BOTH chips' Xilinx package files (`vendor/xc7z0x0clg400pkg.txt`):
the ball exists, it has the same function on both (`IO_L13P_T2_MRCC_34`: same pair, same clock
capability, same bank), it is a user I/O, and its bank type takes the IOSTANDARD (LVCMOS33 and TMDS_33
need an HR bank). `tools/board_xdc.py check <board>` checks one board's file alone.

Result: all 103 ports of the vendor file pass on xc7z020clg400; nothing had to change. An independent
check with Vivado 2026.1 (`get_package_pins` on both parts, BANK and BANK_TYPE of all 400 balls) agrees:
the only differing balls are bank 13's, no-connect on the 7010 and HR user I/O on the 7020, and the board
file names none of them. Banks 34 and 35 (every PL pin the board uses) are HR on both.

Two quirks of the vendor file, the same on both boards: `T12`/`U12` are both `PL_KEY2`/`PL_LED2` and
`GPIO1_17P/N`, and `H20` is both `ETH_nRST` and `GPIO2_17N`. Only the ports a design uses are
constrained, so the SoC (which uses neither header) is unaffected.

## Building

- `make BOARD=peregrine bitstream`: the release SoC with Vivado into `build/peregrine/release/`. The SoC
  parameters are `soc/boards.py` `Board.soc` (R41 B2): PEREGRINE starts with KESTREL's v1.3 set
  (`soc/board_soc.py` `KESTREL_V13`), so its first bitstream is KESTREL's SoC on the bigger chip.
- `make BOARD=peregrine bringup`: blink, the HDMI test pattern and the OSD test, with Vivado
  (`boards/bringup.mk`) into `build/peregrine/bringup/<top>/<top>.bit`.
- `make test-board BOARD=peregrine`: the board's checks without hardware (XDC, release SoC, card tool);
  build.sh's `boards` gate runs them for both boards.
- openXC7: the 7020's chipdb is not generated or pinned yet (`tools/openxc7.sh chipdb` with
  `ZM_CHIP=xc7z020`), so `make soc-z7` / `blink` / `hdmi-test` do not build for PEREGRINE yet.

## The first bitstream (24 Nov 2026): KESTREL's SoC on the 7020

`make BOARD=peregrine bitstream` (Vivado 2026.1, `fit_timing`), 40 min, placed and routed first try:
LUT 15,823 placed / 17,018 after synthesis of 53,200 (29.7 / 32.0 %), FF 15,934 (15.0 %), slices
6,515 / 13,300 (49 %), RAMB36 44 / 140, DSP 72 / 220. Every constraint met: sys 100 MHz WNS +0.352 ns,
comp 125 MHz +0.553, pix 40 MHz +1.178, pix5x 200 MHz +0.555, hold +0.018, TNS 0. The headroom (R85):
~36,000 LUT, 96 RAMB36, 148 DSP. Full table: `docs/hardware/boards/PEREGRINE.md`.

## Boot chain: what is part-specific (checked 24 Nov 2026)

| Piece | Same file on both boards? | Evidence |
|---|---|---|
| `BOOT.BIN` (zeST's, what KESTREL boots) | **No** | zeST's FSBL loads a bitstream partition BEFORE U-Boot; the 7010 image's carries IDCODE 7z010 (0x03722093), so on a 7020 it fails before boot.scr runs. Use zeST's `z7lite_7020/boot.bin` (same release, `tools/fetch_board.sh peregrine` puts it in `vendor/zest-bin/`). |
| zeST's FSBL / ps7_init | Different but equivalent | `tools/ps7_from_bootbin.py` on both images: DDR, MIO and ARM PLL tables identical. Only the IO PLL differs (x54 = 1800 MHz on the 7020's, x48 = 1600 on the 7010's) with dividers that keep SDIO 100, UART 100, PCAP 200 and FCLK0 100 MHz. The SoC uses no FCLK. |
| zeST's U-Boot partition | Yes | 7 bytes differ: its build date. Its DTB partition (0x800000) is identical. |
| Plan A's `BOOT.BIN.ours` (U-Boot SPL) | Yes | It carries no bitstream; its ps7_init is read from the 7010 FSBL, and the PS is the same silicon. Not yet run on either board. |
| `boot.scr` (`glass/boot/boot.cmd`) | Yes | `fpga loadb` reads the part off the .bit header and compares it to the IDCODE's name (U-Boot `drivers/fpga/xilinx.c`, `arch/arm/mach-zynq/cpu.c` lists 7Z020): a KESTREL .bit on PEREGRINE prints "Wrong bitstream ID" and boots on without a PL. The 7020's .bit (~4 MB) at 0x1000000 ends below the DTB at 0x1F00000. The AFI writes are PS registers. |
| zImage, `zigmachine.dtb`, rootfs, glass | Yes | Same PS, same 512 MiB DDR3, same cart-window reservation; nothing in glass or the DTS names the part. |
| `zigmachine.bit` | **No** | `card.py stage` refuses a .bit for the other part (header). |
| `KESTREL/BOARD` | **No** | `peregrine`; install.sh refuses a card of the other board, or a card with no BOARD file. |

`card.py stage --board peregrine --boot-dir DIR ...` stages a card from blank: DIR holds BOOT.BIN (refused
if its FSBL bitstream is for the 7010), boot.scr, zImage, zigmachine.dtb, rootfs.cpio.uboot (and
u-boot.img for plan A). Copy `up/` onto a FAT32 card from a PC; install.sh is for updating a card that
already has its `KESTREL/BOARD`.

## Day 1 (bring-up checklist)

Keep KESTREL's card and board untouched; PEREGRINE gets its own card. On the bench, compare each step
with KESTREL running the same thing.

1. **Power and JTAG.** J1 to JTAG (KESTREL README "Programming the PL over JTAG").
   `openFPGALoader -c digilent_hs2 --detect` must list an **xc7z020** (IDCODE 0x03727093) and the ARM DAP.
2. **Blink.** `make BOARD=peregrine bringup`, then `openFPGALoader -c digilent_hs2
   fpga/build/peregrine/bringup/blink_top/blink_top.bit`: PL_LED1/PL_LED2 alternate 0.5 s each
   (proves N18's 50 MHz and the LED balls).
3. **HDMI.** `.../hdmi_test_top/hdmi_test_top.bit` with HDMI1 on the monitor KESTREL uses: 800x600@60
   bars, castellations, the bouncing box, PL_LED2 lit, PL_LED1 at 1 Hz. Compare against KESTREL's
   `make hdmi-test` picture on the same monitor and cable.
4. **SD boot to U-Boot.** J1 to SD, a card with zeST's **z7lite_7020** `BOOT.BIN` alone: the UART
   (921600 on KESTREL's boot.scr; zeST's U-Boot default first) shows `CPU: Zynq 7z020` and DRAM 512 MiB.
   This is the first proof that the 7010's DDR/MIO init is right for this PCB.
5. **OSD.** From U-Boot, `fatload` + `fpga loadb` the `osd_test_top.bit`, then `fpga/tools/osd_uboot_demo.sh`
   (KESTREL README): `md.l 0x43C00000 1` reads 0x5A4D474C and the OSD changes the screen (GP0 works).
6. **The SoC.** A full card: `card.py stage --board peregrine --boot-dir <z7lite_7020 BOOT.BIN + boot.scr
   + plan A kernel/DTB/rootfs> --bit build/peregrine/release/gateware/platform_z7.bit --system <sys.bin>
   --cart <tag> ...`. Expect the KESTREL menu on HDMI, Wi-Fi join, carts from the shelf.
7. **Compare with KESTREL** on the same carts: OSD fps (the same SoC at the same clocks should give
   the same fps: a difference is DDR timing or a clock, not the chip), audio, `board_fps.py` numbers,
   and `bdiag` / `board_preflight.py` (HP0/HP1 bursts). Then record the part as verified
   (`soc/boards.py` `verified=True`) and the bitstream's board in R85.

If step 4 fails: try plan A's `BOOT.BIN.ours` (no bitstream inside), then re-read the PS7 tables from
zeST's 7020 image (`ZEST_BOOT=<7020 boot.bin> fpga/glass/boot/build_planA.sh`).
