"""tools/video_order.py over the whole shelf: every cart the native host builds
(build/host/<tag>/cart.o) is recorded at one frame and analysed.

    uv run python tools/video_order_shelf.py [frame]     # -> build/vorder/shelf.txt

A cart whose plane-major rebuild does not match the machine is outside what the
RTL replay covers at that frame (its line says why); only the others answer the
line-major question.
"""

import subprocess
import sys
from pathlib import Path

import video_dump
import video_order
import video_rtl

FPGA = Path(__file__).resolve().parent.parent


def main(frame: int) -> int:
    exe = video_rtl.build_tb()
    tags = sorted(p.parent.name for p in (FPGA / "build" / "host").glob("*/cart.o"))
    report = video_order.OUT / "shelf.txt"
    report.parent.mkdir(parents=True, exist_ok=True)
    with report.open("w") as out:
        for tag in tags:
            try:
                d = video_dump.dump(tag, [frame])
                line = f"{tag} {frame} {video_order.analyse(d, frame, exe)}"
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as e:
                line = f"{tag} {frame} not recorded: {e}"
            print(line, flush=True)
            out.write(line + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(int(sys.argv[1]) if len(sys.argv) > 1 else 300))
