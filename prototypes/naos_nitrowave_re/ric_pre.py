"""F1's start from the file to its figure choice ($800..$A3E), transcribed:
the title picture onto its screen, the scroller font (columns of three plane
words, 59 lines each) and its three copies, each 4 pixels further on (roxl
through the whole copy, X carried across the passes). Held against Hatari's
RAM at the choice (dumps/f1_pre.bin):  python3 ric_pre.py"""
import sys

FILE_AT = 0x800
TITLE = 0x13BC0  # PI1
TITLE_SCREEN = 0x6E700  # (($6E66E & ~$FF) + $100)
FONTS = (0x346C4, 0x3925C, 0x3DDF4, 0x4298C)
FONT_LONGS = 0x12E6


def w(m, a):
    return int.from_bytes(m[a:a + 2], 'big')


def sw(m, a, v):
    m[a:a + 2] = (v & 0xFFFF).to_bytes(2, 'big')


def columns(m, a1, src, n, words=3):
    """n lines of one column: `words` plane words into planes 1.. of a group."""
    for _ in range(n):
        for k in range(words):
            sw(m, a1 + 2 + 2 * k, w(m, src + 2 * k))
        a1 += 8
        src += 0x28
    return a1


def font(m):
    a1 = FONTS[0]
    for row in range(5):  # $894: five rows of six letters
        for c in range(6):
            a1 = columns(m, a1, 0xFB38 + 0x938 * row + 6 * c, 0x3B)
    for off in (0x984, 0x12BC):  # $8D6 / $8F4: two one-plane columns
        a1 = columns(m, a1, 0xFB38 + off, 0x3B, 1)
    for c in range(6):  # $912
        a1 = columns(m, a1, 0x12950 + 6 * c, 0x3B)
    for c in range(3):  # $940
        a1 = columns(m, a1, 0x12950 + 0x938 + 6 * c, 0x3B)
    a0 = FONTS[0] + 0xEC0  # $972
    for _ in range(0x3B):
        m[a0 + 4:a0 + 8] = m[a0:a0 + 4]
        a0 += 8


def shifts(m, x=0):
    for src, dst in zip(FONTS, FONTS[1:]):
        m[dst:dst + 4 * FONT_LONGS] = m[src:src + 4 * FONT_LONGS]
        for _ in range(4):
            a = dst + 4 * FONT_LONGS
            for _ in range(0x25CC):
                a -= 2
                v = w(m, a)
                sw(m, a, (v << 1) | x)
                x = v >> 15
    return x


def run(m):
    m[0x4791C:0x47920] = TITLE_SCREEN.to_bytes(4, 'big')  # $85E: the background screen
    m[TITLE_SCREEN:TITLE_SCREEN + 32000] = m[TITLE + 0x22:TITLE + 0x22 + 32000]
    font(m)
    shifts(m)


if __name__ == '__main__':
    m = bytearray(0x80000)
    f = open('disk/DEMO_RIC.BIN', 'rb').read()
    m[FILE_AT:FILE_AT + len(f)] = f
    run(m)
    ref = open('dumps/f1_pre.bin', 'rb').read()[:0x80000]
    for name, lo, hi in (('file+font', 0x800, 0x47524), ('title', TITLE_SCREEN, TITLE_SCREEN + 32000)):
        bad = [i for i in range(lo, hi) if m[i] != ref[i]]
        print(name, len(bad), 'bytes differ', [hex(i) for i in bad[:8]])
    sys.exit(0)
