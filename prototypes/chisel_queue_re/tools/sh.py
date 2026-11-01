"""Run shell commands on the board's Linux console (read the reply). Usage: sh.py 'cmd' ['cmd'...]"""
import sys
sys.path.insert(0, "/home/matt/projects/ZigMachine/.claude/worktrees/chisel-queue-v2/fpga/tools")
from linux_console import LinuxConsole, BoardSilent

c = LinuxConsole()
c.login()
for cmd in sys.argv[1:]:
    try:
        rc, out = c.run(cmd, timeout=float(__import__("os").environ.get("T", "20")))
        print(f"$ {cmd}  [rc={rc}]\n{out}")
    except BoardSilent as e:
        print(f"$ {cmd}  SILENT: {e}")
