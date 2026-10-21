"""fps over time for one cart: `glass ctl load`, then a `stats STEP` read every STEP seconds.

    uv run --with pyserial python fps_trace.py demo-x.zmd SECS [STEP] > trace.txt
"""
import sys
import time

sys.path.insert(0, "/home/matt/projects/ZigMachine/.claude/worktrees/chisel-queue-v2/fpga/tools")
from board_fps import parse_zmstat  # noqa: E402
from linux_console import LinuxConsole  # noqa: E402

cart, secs = sys.argv[1], float(sys.argv[2])
step = int(sys.argv[3]) if len(sys.argv) > 3 else 10
c = LinuxConsole()
c.login()
t0 = time.monotonic()
print(cart, c.run(f"glass ctl load {cart}", timeout=45)[1].strip()[-80:], flush=True)
fps = []
while time.monotonic() - t0 < secs:
    time.sleep(max(0.0, step - 0.5))
    row = parse_zmstat(c.run(f"glass ctl stats {step}", timeout=20)[1]) or {}
    t = time.monotonic() - t0
    print(f"t={t:6.1f} fps={row.get('fps')} frame_c={row.get('frame_c')} cart_c={row.get('cart_c')} "
          f"state={row.get('state')} bard={row.get('bard')} song={row.get('song')}", flush=True)
    try:
        fps.append(float(row.get("fps", "")))
    except ValueError:
        pass
if fps:
    print(f"{cart}: min {min(fps):.1f} avg {sum(fps) / len(fps):.1f} max {max(fps):.1f} over {len(fps)} windows")
