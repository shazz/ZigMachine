"""drvdiff.py: where the five B.I.G. digi tunes' driver blocks (image $4D2, assembled at $44000) differ."""
import sys

NAMES = "Ace_2 Labello Phantom_Of_The_Asteroid Sanxion Starpaws".split()
OFF, LEN, ORG = 0x4D2, 0x1E6C, 0x44000


def block(name):
    return open(name + ".sndh", "rb").read()[OFF:OFF + LEN]


def runs(a, b):
    out = []
    for i in (i for i in range(len(a)) if a[i] != b[i]):
        if out and i - out[-1][1] <= 4:
            out[-1][1] = i
        else:
            out.append([i, i])
    return out


ref = block(sys.argv[1] if len(sys.argv) > 1 else "Ace_2")
for n in NAMES:
    r = runs(ref, block(n))
    print(n, sum(e - s + 1 for s, e in r), [(hex(ORG + s), e - s + 1) for s, e in r][:60])
