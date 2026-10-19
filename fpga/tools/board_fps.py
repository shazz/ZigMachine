"""Every cart on the shelf, loaded on the board in turn and measured: frame rate, BARD load, state.

    uv run --with pyserial python fpga/tools/board_fps.py [--tty /dev/ttyUSB0] [--secs 10] [--window 5]
        [--keys keys.txt] [--only a.zmd,b.zmd] [--out fpga/build/board_fps]

Over the board's Linux serial console (a root shell), through the running glass's control channel
(`glass ctl`, docs/FPGA_GLASS.md "The control channel"): `load` each disk, play its key script, wait
--secs from the load, read `stats <--window>` (the ZMSTAT line), next. Writes <out>/fps_<time>.csv and
.md, a row a cart as it goes, so a run cut short keeps what it measured.
A firmware with the video probe (cycles/vstat.h) adds its fields (vs_n= ... cal_fill2=): the CSV
keeps them, the .md adds a per-pass table (tools/board_fps_probe.py).

Recovery: a cart that does not boot (CartSilent), traps, or hangs (state=stalled: RUNNING but no frame
for 2 s) is recorded and the next cart loaded (a hung one gets `quit-cart` first). If the shell stops
answering and Ctrl-C does not bring it back, or glass stops answering twice in a row, the run stops
and reports (exit 2). Exit 0 otherwise, whatever the carts did.

The key script (--keys): a line a cart, `<file.zmd> <at>:<key>[:down|up|tap] ...`, `at` in seconds
after the load, key as `glass ctl key` takes it (`1`, `space`, `enter`, `f1`, `0xE012`), or
`<at>:joy=<bits>` (`joy=fire`, `joy=0`). `#` starts a comment. E.g.:
    demo-union.zmd   2:1  4:space
    demo-joust.zmd   1:joy=fire  1.2:joy=0
"""

from __future__ import annotations

import argparse
import csv
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

import board_fps_probe as probe
from linux_console import BoardSilent, LinuxConsole

FIELDS = ("cart", "fps", "frame_ms", "frames", "missed", "bard", "player", "state", "err", "song")
CSV_FIELDS = FIELDS + probe.FIELDS  # the video probe's, from a firmware that has it (board_fps_probe.py)
BAD = ("stalled", "booting", "request")  # still in the window, going nowhere: stopped before the next
NO_GLASS, GLASS_TIMEOUT = 3, 4  # `glass ctl` exit codes (ctl_sock.zig)


class Abort(RuntimeError):
    """The board or glass stopped answering: the run cannot go on."""


def parse_zmstat(text: str) -> dict[str, str] | None:
    """The fields of the first ZMSTAT line in `text`; song (last) takes the rest of the line."""
    for line in text.splitlines():
        if line.startswith("ZMSTAT "):
            head, _, song = line[len("ZMSTAT ") :].partition(" song=")
            out = dict(kv.split("=", 1) for kv in head.split() if "=" in kv)
            out["song"] = song.strip() or "-"
            return out
    return None


@dataclass
class Step:
    at: float
    ctl: str  # the `glass ctl` arguments


def parse_keys(text: str) -> dict[str, list[Step]]:
    scripts: dict[str, list[Step]] = {}
    for n, raw in enumerate(text.splitlines(), 1):
        words = raw.split("#", 1)[0].split()
        if not words:
            continue
        steps = []
        for w in words[1:]:
            at, sep, what = w.partition(":")
            if not sep or not what:
                raise ValueError(f"keys line {n}: {w!r} is not <at>:<key> or <at>:joy=<bits>")
            if what.startswith("joy="):
                steps.append(Step(float(at), f"joy {what[4:]}"))
            else:
                key, _, mode = what.partition(":")
                steps.append(Step(float(at), f"key {key} {mode or 'tap'}"))
        scripts[words[0]] = sorted(steps, key=lambda s: s.at)
    return scripts


@dataclass
class Glass:
    """`glass ctl` over the console, with the run's recovery rules."""

    con: LinuxConsole
    failures: int = 0
    log: list[str] = field(default_factory=list)

    def ctl(self, args: str, timeout: float = 15.0) -> tuple[int, str]:
        try:
            rc, out = self.con.run(f"glass ctl {args}", timeout)
        except BoardSilent as e:
            if not self.con.revive():
                raise Abort(f"the board stopped answering ({e})") from e
            rc, out = GLASS_TIMEOUT, str(e)
        if rc == NO_GLASS:  # glass died: S99glass restarts it within a second or two
            rc, out = self._wait_glass(args, timeout)
        self.failures = self.failures + 1 if rc in (NO_GLASS, GLASS_TIMEOUT) else 0
        if self.failures >= 2:
            raise Abort(f"glass stopped answering (`glass ctl {args}`: {out.strip()[-120:]})")
        return rc, out

    def _wait_glass(self, args: str, timeout: float) -> tuple[int, str]:
        for _ in range(10):
            time.sleep(1.5)
            rc, out = self.con.run(f"glass ctl {args}", timeout)
            if rc != NO_GLASS:
                return rc, out
        raise Abort("glass stopped answering: not listening for 15 s (crashed, and S99glass did not restart it?)")


def measure(g: Glass, cart: str, steps: list[Step], secs: float, window: int) -> dict[str, str]:
    t0 = time.monotonic()
    rc, out = g.ctl(f"load {cart}", timeout=45.0)
    if rc == 0:
        for s in steps:
            time.sleep(max(0.0, t0 + s.at - time.monotonic()))
            g.ctl(s.ctl)
        time.sleep(max(0.0, t0 + secs - time.monotonic()))
    _, text = g.ctl(f"stats {window}")
    row = parse_zmstat(text) or {"state": "no_zmstat", "err": out.strip().replace("\n", " ")[-80:] or "-"}
    if row.get("state") in BAD:
        g.ctl("quit-cart")
    row["cart"] = cart
    return row


def shelf(g: Glass) -> list[str]:
    rc, out = g.ctl("list")
    if rc != 0:
        raise Abort(f"`glass ctl list` failed ({rc}): {out.strip()[-200:]} (an old glass without ctl?)")
    return [ln.split("\t", 1)[0] for ln in out.splitlines() if "\t" in ln]


def write_md(path: Path, rows: list[dict[str, str]], note: str) -> None:
    lines = ["| " + " | ".join(FIELDS) + " |", "|" + "---|" * len(FIELDS)]
    lines += ["| " + " | ".join(r.get(f, "-") for f in FIELDS) + " |" for r in rows]
    lines += probe.md_table(rows)
    path.write_text("\n".join(lines) + "\n" + (f"\n{note}\n" if note else ""))


def run(g: Glass, carts: list[str], keys: dict[str, list[Step]], args: argparse.Namespace, out: Path) -> int:
    stamp = time.strftime("%Y%m%d-%H%M%S")
    out.mkdir(parents=True, exist_ok=True)
    csv_path, md_path = out / f"fps_{stamp}.csv", out / f"fps_{stamp}.md"
    rows: list[dict[str, str]] = []
    note, rc = "", 0
    with csv_path.open("w", newline="") as f:
        w = csv.DictWriter(f, CSV_FIELDS, extrasaction="ignore", restval="-")
        w.writeheader()
        for i, cart in enumerate(carts):
            try:
                row = measure(g, cart, keys.get(cart, []), args.secs, args.window)
            except Abort as e:
                note, rc = f"STOPPED at {cart} ({i}/{len(carts)} measured): {e}", 2
                break
            rows.append(row)
            w.writerow(row)
            f.flush()
            print(f"{cart}: {row.get('fps')} fps, {row.get('state')}, bard {row.get('bard')}", flush=True)
    write_md(md_path, rows, note)
    print(md_path.read_text() + f"\n{csv_path}\n{md_path}")
    return rc


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tty", default=None, help="the board's Linux console (default $BOARD_TTY or /dev/ttyUSB0)")
    ap.add_argument("--secs", type=float, default=10.0, help="seconds from the load to the stats read")
    ap.add_argument("--window", type=int, default=5, help="seconds the fps is measured over (1..50)")
    ap.add_argument("--keys", type=Path, help="per-cart key scripts (see above)")
    ap.add_argument("--only", help="comma-separated disks, in this order, instead of the whole shelf")
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parent.parent / "build" / "board_fps")
    args = ap.parse_args(argv)
    if not 1 <= args.window <= 50 or args.window > args.secs:
        ap.error("--window must be 1..50 and no longer than --secs")
    keys = parse_keys(args.keys.read_text()) if args.keys else {}
    con = LinuxConsole(args.tty)
    con.login()
    g = Glass(con)
    try:
        carts = args.only.split(",") if args.only else shelf(g)
    except Abort as e:
        print(f"board_fps: {e}", file=sys.stderr)
        return 2
    return run(g, carts, keys, args, args.out)


if __name__ == "__main__":
    sys.exit(main())
