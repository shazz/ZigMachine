"""dis.py <mem.bin> <outdir> start:end [start:end ...]
Cuts 64 KB RAM image ranges and disassembles each with da65 (-> d<start>.s)."""
import os
import subprocess
import sys

DA65 = os.path.expanduser("~/.local/c64/bin/da65")
mem = open(sys.argv[1], "rb").read()
out = sys.argv[2]
for rng in sys.argv[3:]:
    a, b = (int(x, 16) for x in rng.split(":"))
    binf = os.path.join(out, f"r{a:04x}.bin")
    open(binf, "wb").write(mem[a:b])
    info = os.path.join(out, f"d{a:04x}.info")
    args = [DA65, "--cpu", "6502x", "-S", hex(a), binf]
    if os.path.exists(info):
        args = [DA65, "-i", info, binf]
    s = subprocess.run(args, capture_output=True, text=True).stdout
    open(os.path.join(out, f"d{a:04x}.s"), "w").write(s)
    print(rng, len(s.splitlines()), "lines")
