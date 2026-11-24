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

## openXC7

The 7020's chipdb is not generated or pinned yet (`tools/openxc7.sh chipdb` with `ZM_CHIP=xc7z020`):
PEREGRINE builds with Vivado (`make BOARD=peregrine bitstream`).
