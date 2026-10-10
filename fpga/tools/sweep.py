"""sweep.py GATEWARE [--seeds 1 2 3 4] [--jobs 2] [--out DIR]: place and route one
synthesised netlist with N seeds, at most two openXC7 containers at a time.

GATEWARE is a LiteX build's gateware directory (its <name>.json netlist, .xdc and the
build_<name>.sh soc/openxc7.py wrote). Each seed gets DIR/s<seed>/ with the netlist
linked in, the build script minus Yosys (and minus any REUSE replay: a sweep places from
scratch) and its own seed, run through tools/pnr_slot.sh (the box's two P&R slots, slot 0
being the lock every other P&R target takes). Every seed ends with a .bit, so the winner
needs no rebuild: pin it in soc/openxc7.py SEED and copy its bit.

    make -C fpga sweep SEEDS="1 2 3 4 5 6"   # the last `make soc-z7` netlist
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA))
from soc import openxc7, openxc7_fast

RESULT = re.compile(r"Max frequency for clock\s+'([^']+)': ([\d.]+) MHz \((PASS|FAIL) at ([\d.]+) MHz\)")


def prepare(src: Path, name: str, seed: int, out: Path, timeout: int = 900) -> Path:
    """DIR/s<seed>/: the netlist and constraints linked, the P&R-only script; a seed whose
    router never converges (pass 3's cdc_s8 ran into a 1,500 s cap) is cut at `timeout` s."""
    d = out / f"s{seed}"
    d.mkdir(parents=True, exist_ok=True)
    for ext in ("json", "xdc"):
        link = d / f"{name}.{ext}"
        link.unlink(missing_ok=True)
        link.symlink_to(src / f"{name}.{ext}")
    text = (src / f"build_{name}.sh").read_text()
    lines = [ln for ln in text.splitlines() if not re.match(r"^((zm_stage synth )?yosys |zm_stage freeze )", ln)]
    script = d / f"build_{name}.sh"
    script.write_text(re.sub(r" -o preplaced=\S+", "", "\n".join(lines) + "\n"))
    openxc7.set_seed(script, seed)
    if "zm_stage" not in script.read_text():  # a build from before stage timing
        openxc7_fast.time_stages(script)
    text = re.sub(
        r"^zm_stage pnr (timeout \d+ )?nextpnr",
        f"zm_stage pnr timeout {timeout} nextpnr",
        script.read_text(),
        flags=re.MULTILINE,
    )
    script.write_text(text)
    return d


def place(d: Path, name: str, seed: int) -> int:
    cmd = [str(FPGA / "tools/pnr_slot.sh"), str(FPGA / "tools/openxc7.sh"), "run", "bash", f"build_{name}.sh"]
    with (d / "run.log").open("w") as log:
        rc = subprocess.run(cmd, cwd=d, stdout=log, stderr=subprocess.STDOUT, check=False).returncode
    subprocess.run([sys.executable, str(FPGA / "tools/build_times.py"), str(d), "--label", f"{name} sweep seed={seed}"],
                   check=False, stdout=subprocess.DEVNULL)  # fmt: skip
    return rc


def verdict(d: Path) -> tuple[bool, float, str]:
    """(every clock passes, the worst fmax / target, a one-line summary) from DIR/s<seed>/pnr.log."""
    log = d / "pnr.log"
    found: dict[str, tuple[float, bool, float]] = {}
    for clock, mhz, ok, target in RESULT.findall(log.read_text(errors="replace") if log.exists() else ""):
        found[clock] = (float(mhz), ok == "PASS", float(target))  # the last report is the routed one
    if not found:
        return False, 0.0, "no timing report (failed?)"
    worst = min(f / t for f, _, t in found.values())
    text = ", ".join(f"{c} {f:.1f}{'' if ok else ' FAIL'}" for c, (f, ok, _) in found.items())
    return all(ok for _, ok, _ in found.values()), worst, text


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("gateware", type=Path)
    ap.add_argument("--seeds", type=int, nargs="+", default=[1, 2, 3, 4])
    ap.add_argument("--jobs", type=int, default=2, help="seeds at once (the box takes two 6 GB containers)")
    ap.add_argument("--out", type=Path, help="default: build/sweep/<name>")
    ap.add_argument("--timeout", type=int, default=900, help="seconds of nextpnr a seed gets")
    a = ap.parse_args()
    src = a.gateware.resolve()
    scripts = sorted(src.glob("build_*.sh"))
    if not scripts:
        print(f"sweep: no build_*.sh in {src}", file=sys.stderr)
        return 1
    name = scripts[0].stem.removeprefix("build_")
    out = (a.out or FPGA / f"build/sweep/{name}").resolve()
    dirs = {s: prepare(src, name, s, out, a.timeout) for s in a.seeds}
    with ThreadPoolExecutor(max_workers=min(a.jobs, 2)) as pool:
        rcs = dict(zip(a.seeds, pool.map(lambda s: place(dirs[s], name, s), a.seeds), strict=True))
    rows = sorted(((verdict(dirs[s]), s) for s in a.seeds), key=lambda r: (r[0][0], r[0][1]), reverse=True)
    print(f"sweep of {src} ({len(a.seeds)} seeds, best first):")
    for (ok, _, text), s in rows:
        print(f"  seed {s:3d}  {'PASS' if ok else 'fail'}  {text}  rc={rcs[s]}  {dirs[s]}/{name}.bit")
    return 0


if __name__ == "__main__":
    sys.exit(main())
