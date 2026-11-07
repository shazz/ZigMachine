"""trace_bin.py <trace.txt> <out.bin>: trace_all.py's stream as the scene's VIC writes.

Per frame 1..N: u32 count, then count records of (u16 line, u8 cycle, u8 reg, u8 value), reg
as apps/zig/scenes/c64_1988/vic.zig numbers them: $D000-$D02E -> 0..$2E, a sprite pointer
($07F8+i or $F3F8+i) -> $30+i, $DD00 -> $38. Stores that change nothing the sprite unit sees
($D012, $D019, $D01A, the part flag) are dropped; a read-modify-write of $D016 is kept (its
cycle is what matters)."""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(__file__))
import frames as F  # noqa: E402


def reg_of(addr: int) -> int | None:
    if addr in (0xD012, 0xD019, 0xD01A):
        return None
    if 0xD000 <= addr <= 0xD02E:
        return addr - 0xD000
    if 0x07F8 <= addr <= 0x07FF:
        return 0x30 + addr - 0x07F8
    if 0xF3F8 <= addr <= 0xF3FF:
        return 0x30 + addr - 0xF3F8
    if addr == 0xDD00:
        return 0x38
    return None


def main() -> None:
    # A capture frame n is lines 288..311 of the engine's frame n-1 then 0..287 of frame n:
    # the engine runs whole PAL frames, lines 0..311.
    fr = F.load(sys.argv[1])
    eng: dict[int, list[bytes]] = {}
    for n in sorted(fr):
        for line, cyc, addr, val in fr[n]:
            r = reg_of(addr)
            if r is None or (val in ("RMW", "??") and r != 0x16):
                continue
            v = 0 if val in ("RMW", "??") else int(val, 16)
            eng.setdefault(n - 1 if line >= 288 else n, []).append(struct.pack("<HBBB", line, cyc, r, v))
    with open(sys.argv[2], "wb") as out:
        for n in range(1, max(fr) + 1):
            recs = eng.get(n, [])
            out.write(struct.pack("<I", len(recs)) + b"".join(recs))


main()
