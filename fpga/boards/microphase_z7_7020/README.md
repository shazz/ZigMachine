# PEREGRINE: MicroPhase Z7 with a Zynq XC7Z020 (CLG400)

KESTREL's big brother (ordered 14 Nov 2026). Not brought up yet: everything here is a placeholder
until the board is on the desk.

- `make BOARD=peregrine ...` selects this directory (`fpga/boards/boards.mk`, `soc/boards.py`).
- **Unverified**: the part `xc7z020clg400-1` (speed grade) and the pinout. Copy the vendor's
  constraint file to `board.xdc` here (it is not tracked, like KESTREL's); until then a build stops
  with `BoardXdcMissingError`.
- The openXC7 chipdb for the 7020 is not generated or pinned yet (`tools/openxc7.sh chipdb` with
  `ZM_CHIP=xc7z020`); Vivado needs none.
- Bring-up order: the 7010's (`../microphase_z7_7010/README.md`): blink, HDMI test, OSD test, then the SoC.
