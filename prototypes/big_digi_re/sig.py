"""sig.py: digi.maskedHash (FNV-1a 64, holes read as 0) of PLAY's [0, LEN) for digi_big_map.zig, in every tune."""
import re

LEN = 0x5A6
src = open("../../libs/zig/players/digi_big_map.zig").read()
longs = [int(x, 16) for x in re.search(r"const LONGS = \[_\]u32\{([^}]*)\}", src).group(1).replace(" ", "").split(",")]
holes = [(a, a + 4) for a in longs] + [(0x152, 0x153), (0x452, 0x458), (0x4BC, 0x4CE)]


def masked(b):
    h = 0xCBF29CE484222325
    for i, v in enumerate(b):
        if any(s <= i < e for s, e in holes):
            v = 0
        h = ((h ^ v) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


for n in ["Ace_2", "Labello", "Phantom_Of_The_Asteroid", "Sanxion", "Starpaws", "../../docs/music/big/Labello"]:
    d = open(n + ".sndh", "rb").read()
    play = 0xA + int.from_bytes(d[0xA:0xC], "big")
    print(f"{n}: play {play:#x} sig {masked(d[play:play + LEN]):#018X}")
