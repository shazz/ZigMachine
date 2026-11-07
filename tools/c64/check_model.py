"""check_model.py <dir>: run vicmodel over every captured frame, report mismatches."""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import vicmodel  # noqa: E402

bad = 0
files = sorted(glob.glob(os.path.join(sys.argv[1], "f*.trace")), key=lambda f: int(os.path.basename(f)[1:-6]))
for t in files:
    base = t[:-6]
    vic = open(base + ".vic", "rb").read()
    bank, screen = vicmodel.bank_screen(base, vic)
    ref = vicmodel.png_indices(base + ".png")
    n, box = min(vicmodel.diff(vicmodel.run(base, bank, screen, vb), ref) for vb in (False, True))
    if n:
        bad += 1
        print(os.path.basename(base), "mismatch", n, box)
print(f"{len(files) - bad}/{len(files)} frames exact")
