"""Compare two bench_collect CSVs (before / after): the memory lines and anything that moved > 5 %."""
from __future__ import annotations

import csv
import glob
import sys


def load(pattern: str) -> dict[str, dict[str, str]]:
    return {r["name"]: r for r in csv.DictReader(open(sorted(glob.glob(pattern))[-1]))}


a, b = load(sys.argv[1]), load(sys.argv[2])
print(f"| {'bench':22s} | before c/op | after c/op | MB/s before | MB/s after |")
print("|---|---:|---:|---:|---:|")
for n in a:
    if n not in b:
        continue
    ca, cb = float(a[n]["cyc_per_op"]), float(b[n]["cyc_per_op"])
    if abs(cb - ca) / max(ca, 1e-9) > 0.05 or n.startswith(("ld.", "st.", "cp.", "memcpy", "vr.")):
        print(f"| {n:22s} | {ca:.2f} | {cb:.2f} | {a[n]['mb_s']} | {b[n]['mb_s']} |")
