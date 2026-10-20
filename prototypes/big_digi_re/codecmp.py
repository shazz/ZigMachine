"""codecmp.py: the five drivers' code from PLAY on, as instruction shapes (absolute operands masked), compared."""
import difflib
import re

import capstone

NAMES = "Ace_2 Labello Phantom_Of_The_Asteroid Sanxion Starpaws".split()
md = capstone.Cs(capstone.CS_ARCH_M68K, capstone.CS_MODE_M68K_000 | capstone.CS_MODE_BIG_ENDIAN)
md.skipdata = True


def shapes(name, n=1600):
    d = open(name + ".sndh", "rb").read()
    play = 0xA + int.from_bytes(d[0xA:0xC], "big")  # bra.w at 8
    out = []
    for ins in md.disasm(d[play:play + 0x2400], play):
        out.append(f"{ins.mnemonic} {re.sub(r'\$[0-9a-f]{4,}', 'ADDR', ins.op_str)}")
        if len(out) >= n:
            break
    return play, out


ref_play, ref = shapes("Ace_2")
for n in NAMES:
    play, s = shapes(n)
    sm = difflib.SequenceMatcher(None, ref, s, autojunk=False)
    print(n, hex(play), f"ratio {sm.ratio():.3f}",
          [(t, i1, i2, j1, j2) for t, i1, i2, j1, j2 in sm.get_opcodes() if t != "equal"][:12])
