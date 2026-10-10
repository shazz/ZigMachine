"""Simulate the OSD test bitstream's logic before the board: CXXRTL of
rtl/board/osd_test_core.v driven through osd_uboot_demo.sh's steps (the checks of
tests/tb/osd_test_tb.cpp), and the frame after each step as a PNG in
build/osd_test/ to look at: osd_1_poweron, osd_2_message, osd_3_off, osd_4_colours.

    uv run python tools/osd_test_sim.py    # make -C fpga osd-test-sim
"""

import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA))
sys.path.insert(0, str(FPGA / "tests"))
# After the path inserts:
from test_rtl_osd_test import run

from tools.hdmi_test_sim import ppm_to_png

OUT = FPGA / "build" / "osd_test"
STEPS = ("1_poweron", "2_message", "3_off", "4_colours")


def main() -> int:
    code, out = run(FPGA, OUT / "sim", [str(OUT)])
    print(out, end="")
    if code != 0:
        return code
    for step in STEPS:
        ppm = OUT / f"osd_{step}.ppm"
        ppm_to_png(ppm, OUT / f"osd_{step}.png")
        ppm.unlink()
        print(f"osd-test-sim: {OUT / f'osd_{step}.png'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
