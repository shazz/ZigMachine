"""holes.py: the PLAY region of Mad Max's B.I.G. digi driver, [PLAY, handler), in every tune:
the bytes that relocation moves (absolute longs into the driver or the song, the jump table),
as holes relative to PLAY, and the check that every tune has the same code outside them.
Prints Zig for digi_big_map.zig."""
import re

import capstone

NAMES = ["Ace_2", "Labello", "Phantom_Of_The_Asteroid", "Sanxion", "Starpaws"]
EXTRA = ["../../docs/music/big/Labello"]
LEN = 0x740  # PLAY ($44D26 in Ace 2) to the Timer A handler ($45466)
TABLE = (0x44E0E - 0x44D26, 17)  # the command jump table: 17 relocated longs
md = capstone.Cs(capstone.CS_ARCH_M68K, capstone.CS_MODE_M68K_000 | capstone.CS_MODE_BIG_ENDIAN)
md.skipdata = True


def region(path):
    d = open(path + ".sndh", "rb").read()
    play = 0xA + int.from_bytes(d[0xA:0xC], "big")
    return play, d[play:play + LEN]


def holes(code):
    out = set()
    for ins in md.disasm(code, 0):
        if TABLE[0] <= ins.address < TABLE[0] + 4 * TABLE[1]:
            continue
        for v in re.findall(r"\$([0-9a-f]+)", ins.op_str):
            x = int(v, 16)
            if 0x40000 <= x < 0x70000:
                at = ins.bytes.find(x.to_bytes(4, "big"))
                assert at >= 2, (hex(ins.address), ins.op_str)
                out.add(ins.address + at)
    out.update(TABLE[0] + 4 * i for i in range(TABLE[1]))
    return sorted(out)


ref_play, ref = region(NAMES[0])
h = holes(ref)
mask = bytearray(ref)
for at in h:
    mask[at:at + 4] = b"\0\0\0\0"
for n in NAMES + EXTRA:
    play, c = region(n)
    m = bytearray(c)
    for at in h:
        m[at:at + 4] = b"\0\0\0\0"
    assert holes(c) == h, n
    print(f"// {n}: PLAY at image {play:#x}, same code outside the holes: {m == mask}")
print(f"const HOLES = [_]u32{{ {', '.join(hex(x) for x in h)} }};  // {len(h)} longs")
