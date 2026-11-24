"""CRC pins of PICO-8's numbers (R82 M2): the Lua reference's sin, cos, atan2 and `^0.5` over fixed inputs.

    python3 tools/racer/fix_pin.py

Runs z8lua (local-only, see ref_harness.py) on generated inputs and prints the CRC-32 of each result stream (raw
16.16 as little-endian i32). apps/zig/scenes/racer/fix_test.zig computes the same streams with fix.zig and
compares them to these constants: re-run this and update them only if the inputs below change.
Inputs: sin, cos at every 16-bit raw value, in the order 0..32767, -1..-32767, -32768; atan2(x, y) on a 301 x 301 grid of (i - 150) * 0.0371; `^0.5` of
k * 517 raw for k in 0..32767.
"""

from __future__ import annotations

import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import ref_harness  # noqa: E402

LUA = """
local one=0x0.0001
for _,f in pairs({sin,cos}) do
  for k=0,32767 do print(tostr(f(k*one),true)) end
  for k=1,32767 do print(tostr(f(-k*one),true)) end
  print(tostr(f((-32768)*one),true))
end
for i=0,300 do for j=0,300 do print(tostr(atan2((i-150)*0.0371,(j-150)*0.0371),true)) end end
for k=0,32767 do print(tostr((k*0x0.0205)^0.5,true)) end
"""
SIZES = (65536, 65536, 301 * 301, 32768)


def raw(text: str) -> int:
    v = int(text[2:6] + text[7:11], 16)
    return v - (1 << 32) if v >= 1 << 31 else v


def crcs() -> list[int]:
    exe = ref_harness.z8lua_path()
    with tempfile.TemporaryDirectory() as tmp:
        script = Path(tmp) / "pin.lua"
        script.write_text(LUA)
        out = subprocess.run([str(exe), str(script)], capture_output=True, text=True, timeout=120, check=True).stdout
    vals = [raw(ln) for ln in out.split()]
    res, at = [], 0
    for n in SIZES:
        res.append(zlib.crc32(struct.pack(f"<{n}i", *vals[at:at + n])))
        at += n
    return res


if __name__ == "__main__":
    print(" ".join(f"0x{c:08x}" for c in crcs()))
