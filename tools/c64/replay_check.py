"""replay_check.py <replay-exe> <writes.bin> <regs.vic> <vicedir> <workdir>: run a write
stream through the scene's sprite unit (replay.zig) for every frame VICE captured in
<vicedir>, then compare (compare.py)."""
import glob
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART = os.path.join(ROOT, "apps/zig/assets/screens/c64_1988")

exe, writes, regs, vicedir, work = sys.argv[1:6]
frames = sorted(int(os.path.basename(p)[1:-4]) for p in glob.glob(os.path.join(vicedir, "f*.png")))
os.makedirs(work, exist_ok=True)
subprocess.run([exe, writes, regs, os.path.join(ART, "bank3.bin"), os.path.join(ART, "bank0.bin"), work]
               + [str(f) for f in frames], check=True)
subprocess.run([sys.executable, "-I", os.path.join(os.path.dirname(__file__), "compare.py"), work, vicedir]
               + [str(f) for f in frames], check=True)
