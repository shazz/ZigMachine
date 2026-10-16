"""The split images (decisions.md 2026-10-15) in the board SoC sim with the sound CPU
(build/soc_hp_snd, ZM_AUDIO=snd: the shelf's audio): the sim's system image at 0, the cart's
lean image at CART_IMG_AT, its shelf disk after it (tools/ddr_init.py --cart), and the
verdict tools/hp_sim_run.py gives the monolithic image: ran to the end, no underrun, the
hashes equal scene_hash.mjs's and the native host's for the same frames and disk.

    uv run python tools/hp_sim_split.py tutorial raytrace --frames 60 --every 10 --run-id split
    uv run python tools/hp_sim_split.py tutorial --mono ...       # the monolithic sim_snd image, same model
    uv run python tools/hp_sim_split.py tutorial --abi-skew 0x20000u --frames 2 --every 1
                                       # a cart claiming table 2.0: the system must refuse it
--build-only under prototypes/_gate_logs/build.lock, then --no-build under a sim lock.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA))
sys.path.insert(0, str(FPGA / "gen"))
import cycles_run  # after the path insert: tools/ is not a package
import glass_cart
import video_sim_report

HCYC = FPGA / "build/hcycles"
SOC = FPGA / "build/soc_hp_snd"


def carts_dir(skew: str) -> Path:
    return HCYC / "split" / f"carts{'_v' + skew if skew else ''}"


def image(tag: str, mode: str, skew: str) -> Path:
    """The DDR image of one run: mono (fw.bin) or split (sys.bin + cart.bin), with the disk."""
    disk = cycles_run.shelf_disk(tag)
    disk_args = ["--disk", str(disk)] if disk else []
    if mode == "mono":
        fw, out = HCYC / "sim_snd" / tag / "fw.bin", HCYC / "sim_snd" / tag / "zm_ddr.init"
        cmd = [str(fw), str(out), *disk_args]
    else:
        out = carts_dir(skew) / tag / "zm_ddr.init"
        cmd = [str(HCYC / "split/sim_snd/sys.bin"), str(out), "--cart", str(carts_dir(skew) / tag / "cart.bin")]
        cmd += disk_args
    subprocess.run(["uv", "run", "python", str(FPGA / "tools/ddr_init.py"), *cmd], cwd=FPGA, check=True)
    return out


def build(tags: list[str], mode: str, skew: str, frames: int, every: int) -> None:
    common = ["ZM_AUDIO=snd", *([f"ZM_CART_VERSION={skew}"] if skew else [])]
    cycles_run.make("memmap", *[f"build/host/{t}/host" for t in tags], frames=frames, every=every, jobs=1)
    if mode == "mono":
        cycles_run.make(*[f"build/hcycles/sim_snd/{t}/fw.bin" for t in tags], *common, frames=frames, every=every, jobs=1)
    else:
        cycles_run.make("split-sys-sim", *common, frames=frames, every=every, jobs=1)
        for t in tags:
            cycles_run.make("split-cart", f"CART={t}", *common, frames=frames, every=every, jobs=1)
    for t in tags:
        image(t, mode, skew)
        cycles_run.references(t, frames, every, disk=True)


def run_one(tag: str, mode: str, skew: str, run_id: str, timeout: int) -> str:
    rundir = Path("/dev/shm") / f"zm_hp_{tag}_{mode}{'_skew' if skew else ''}_{run_id}"
    env = dict(os.environ, ZM_SOC=str(SOC), ZM_INIT="sim_zm_ddr.init")
    init = (HCYC / "sim_snd" / tag if mode == "mono" else carts_dir(skew) / tag) / "zm_ddr.init"
    cmd = ["systemd-run", "--user", "--scope", "-q", "-p", "MemoryMax=6G", "-p", "MemorySwapMax=0"]
    rc = subprocess.run([*cmd, str(FPGA / "tools/cycles_sim.sh"), str(init), str(rundir), str(timeout)],
                        env=env, check=False).returncode  # fmt: skip
    dst = HCYC / "uart" / f"{tag}+{mode}{'+skew' if skew else ''}.txt"
    dst.parent.mkdir(parents=True, exist_ok=True)
    uart = rundir / "uart.txt"
    text = uart.read_text(errors="replace") if uart.exists() else ""
    dst.write_text(text)
    subprocess.run(["rm", "-rf", str(rundir)], check=False)
    run = video_sim_report.parse(text)
    if skew:
        refused = "ZM CARTABI table" in text and run.end == glass_cart.TRAP_CART_ABI
        return f"hp {tag:16} {mode} skew={skew} rc={rc} {'ok refused' if refused else 'FAIL ran'}  ({dst.name})"
    total = run.json["total"][:16] if run.json else "-"
    verdict = video_sim_report.verdict(tag, run, disk=cycles_run.shelf_disk(tag) is not None)
    return f"hp {tag:16} {mode} rc={rc} {verdict} total={total}  ({dst.relative_to(FPGA)})"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("carts", nargs="+")
    ap.add_argument("--frames", type=int, default=10)
    ap.add_argument("--every", type=int, default=5)
    ap.add_argument("--timeout", type=int, default=4 * 3600)
    ap.add_argument("--mono", action="store_true", help="the monolithic sim_snd image instead, for comparison")
    ap.add_argument("--abi-skew", default="", help="build the carts claiming this table version (ZM_CART_VERSION)")
    ap.add_argument("--run-id", default="split", help="suffix of the /dev/shm run directory")
    ap.add_argument("--build-only", action="store_true")
    ap.add_argument("--no-build", action="store_true")
    a = ap.parse_args()
    mode = "mono" if a.mono else "split"
    if not a.no_build:
        build(a.carts, mode, a.abi_skew, a.frames, a.every)
    if a.build_only:
        return 0
    lines = [run_one(t, mode, a.abi_skew, a.run_id, a.timeout) for t in a.carts]
    for line in lines:
        print(line, flush=True)
    return 0 if all(" ok" in line.split("  (")[0] for line in lines) else 1


if __name__ == "__main__":
    sys.exit(main())
