"""The fast edit -> board loop's edits to LiteX's openXC7 build files (soc/openxc7.py
applies them; fpga/README.md "When is a full rebuild needed").

- **Stage timing, every build.** Each tool line of build_<name>.sh runs under
  `zm_stage <stage>`, which appends "<stage> <start> <end>" to stages.txt; nextpnr
  logs to pnr.log and dumps its placement (`-o placement=`) to <name>_placement.json.
  tools/build_times.py turns both into a table and a line of build/build_times.txt.
- **Stable cell names (OPENXC7_STABLE=1).** 99 % of the netlist's cells are named
  by Yosys's global counter (`$abc$105055$...`), so any edit renames almost every
  cell. `autoname` names each one after the nets it drives. It changes the cell
  order, so a stable build's placement is not the pinned seed's: it is a dev base,
  never the release. (Keeping each RTL module's hierarchy was tried too: it raised the
  replayable share of an edited netlist from 7 to 20 % but made the base slower and
  worse; BUILD_LOOP.md.)
- **Placement replay (OPENXC7_REUSE=<a previous stable build's gateware dir>).**
  Between synthesis and P&R, tools/freeze_placement.py keeps every cell of that
  build's placement that is the same cell in the new netlist (name, type and nets)
  and nextpnr pins them (`-o preplaced=`): the rest is placed around them, and the
  router starts from a near-final placement.
"""

from __future__ import annotations

import re
import shutil
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
FREEZE = FPGA / "tools/freeze_placement.py"
STAGES = {"yosys ": "synth", "nextpnr-xilinx ": "pnr", "fasm2frames ": "frames", "xc7frames2bit ": "bit"}
STAGE_FN = 'zm_stage() { local n=$1 t=$EPOCHREALTIME; shift; "$@"; echo "$n $t $EPOCHREALTIME" >> stages.txt; }'
STABLE_MARK = "stable_names"  # the file a stable-names build leaves in its gateware dir


class ReuseBaseError(FileNotFoundError):
    def __init__(self, base: Path, why: str) -> None:
        super().__init__(
            f"OPENXC7_REUSE={base}: {why} (build a base first: `make soc-dev FRESH=1`, fpga/BUILD_LOOP.md)"
        )


def time_stages(script: Path) -> None:
    """Run every tool line of LiteX's build script under zm_stage, stages.txt emptied first."""
    lines = script.read_text().splitlines()
    out, seen = [], set()
    for line in lines:
        bare = re.sub(r"^timeout \d+ ", "", line)  # soc/openxc7.py PNR_TIMEOUT wraps nextpnr
        tool = next((t for t in STAGES if bare.startswith(t)), None)
        if tool is not None:
            seen.add(tool)
            line = f"zm_stage {STAGES[tool]} {line}"
        out.append(line)
    if "nextpnr-xilinx " not in seen:
        raise ValueError(f"{script}: no nextpnr-xilinx line to time")
    head = 2 if len(out) > 1 and out[1].startswith("set -e") else 1  # after the comment and `set -e`
    out[head:head] = [STAGE_FN, ": > stages.txt"]
    script.write_text("\n".join(out) + "\n")


def pnr_outputs(name: str) -> str:
    """nextpnr options every build gets: the log build_times.py reads, the placement dump REUSE replays."""
    return f"--log pnr.log -o placement={name}_placement.json"


def stable_names(ys: Path) -> None:
    """`autoname` before LiteX's write_json, and mark the gateware dir as a REUSE base."""
    text = ys.read_text()
    if "write_json" not in text:
        raise ValueError(f"{ys}: no write_json line")
    if "\nautoname\n" not in text:
        ys.write_text(text.replace("write_json", "autoname\nwrite_json", 1))
    (ys.parent / STABLE_MARK).write_text("yosys autoname: cell names follow the nets they drive\n")


def add_reuse(script: Path, base: Path, name: str) -> None:
    """Replay base's placement: copy its dump and netlist next to the script (REUSE may name this very
    directory, which the build overwrites), filter them against the new netlist between synthesis and
    P&R (tools/freeze_placement.py, in the container), and pin what is left (`-o preplaced=`)."""
    gw = script.parent
    for what, src in (("placement", base / f"{name}_placement.json"), ("netlist", base / f"{name}.json")):
        if not src.exists():
            raise ReuseBaseError(base, f"no {src.name} (a build from before placement dumps, or another top)")
        if not (base / STABLE_MARK).exists():
            raise ReuseBaseError(base, "not a stable-names build: its cell names do not survive an edit")
        shutil.copyfile(src, gw / f"reuse_base_{what}.json")
    freeze = (f"zm_stage freeze python3 {FREEZE} reuse_base_placement.json reuse_preplaced.tsv "
              f"--base-netlist reuse_base_netlist.json --netlist {name}.json")  # fmt: skip
    text = re.sub(
        r"^zm_stage pnr ", lambda m: f"{freeze}\n{m.group(0)}", script.read_text(), count=1, flags=re.MULTILINE
    )
    if freeze not in text:
        raise ValueError(f"{script}: no timed nextpnr line (time_stages first)")
    script.write_text(text.replace("nextpnr-xilinx ", "nextpnr-xilinx -o preplaced=reuse_preplaced.tsv ", 1))
