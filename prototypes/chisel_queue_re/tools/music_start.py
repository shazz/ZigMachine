"""Music start latency: `glass ctl load` a cart, then poll `glass ctl stats 1` and timestamp the
first window whose BARD load is non-zero; every console line glass logs meanwhile is printed with
its time from the load.   music_start.py demo-x.zmd [SECS]"""
import sys
import time

sys.path.insert(0, "/home/matt/projects/ZigMachine/.claude/worktrees/chisel-queue-v2/fpga/tools")
from board_fps import parse_zmstat  # noqa: E402
from linux_console import LinuxConsole  # noqa: E402

cart, secs = sys.argv[1], float(sys.argv[2]) if len(sys.argv) > 2 else 8
c = LinuxConsole()
c.login()
c.run("glass ctl quit-cart >/dev/null 2>&1; true", timeout=10)
time.sleep(1)
t0 = time.monotonic()
rc, out = c.run(f"glass ctl load {cart}", timeout=45)
t_load = time.monotonic() - t0
first = None
player = None
while time.monotonic() - t0 < secs:
    rc, out = c.run("glass ctl stats 1", timeout=10)
    t = time.monotonic() - t0
    r = parse_zmstat(out) or {}
    bard = r.get("bard", "-")
    now = bard.split("/")[0]
    if player is None and r.get("player", "-") not in ("-",) and "not_started" not in r.get("player", ""):
        player = (t, r.get("player"))
    if first is None and now not in ("-", "0", ""):
        first = t
        break
print(f"{cart}: loaded {t_load:.2f} s, player {player}, first BARD load {first if first is None else round(first, 2)} s (from the load command)")
