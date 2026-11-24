"""One per-board SD-card staging tool (docs/hardware/FPGA_GLASS.md, "Staging a card").

    uv run python tools/card.py stage --board kestrel --name card_x --cart joust --system build/.../sys.bin \
        [--bit F.bit] [--rootfs-base IMG --rootfs-overlay DIR] [--shelf-from shelf.txt] --out build/cards
    uv run python tools/card.py install --host root@192.168.0.15 build/cards/card_x

Refuses a bitstream for another part than the board's, a system and carts of different table versions, a
card name that exists, a MISSING/STALE cart row, a shelf with a duplicate or mid-file comment line.
install.sh refuses a card whose KESTREL/BOARD names another board. Nothing is written to a device and
nothing reaches a board unless `install` is run."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from card_stage.cli import main

if __name__ == "__main__":
    sys.exit(main())
