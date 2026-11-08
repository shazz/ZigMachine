# Rebuild one menu frame from a RAM dump the way the Timer-B chain shows it: per-line
# palettes (VBL palette, the drum-area records, the floor records, three rainbows), then
# render the displayed screen at 1x with the colour-0 border. Prints the per-line colours.
#   reconstruct.py dump.bin out.png [screen_base]
import struct, sys
from PIL import Image

r = open(sys.argv[1], 'rb').read()
W = lambda a: struct.unpack('>H', r[a:a + 2])[0]
L = lambda a: struct.unpack('>I', r[a:a + 4])[0]
scr = int(sys.argv[3], 0) if len(sys.argv) > 3 else L(0x313C6)

SIDE, VB = 48, 30            # border pixels left/right, lines above/below
RAIN_X0 = int(sys.argv[4]) if len(sys.argv) > 4 else 0   # raster x of the first rainbow write


def ste(c):
    lv = lambda n: ((n & 7) << 1) | (n >> 3)
    return (lv(c >> 8 & 15) * 17, lv(c >> 4 & 15) * 17, lv(c & 15) * 17)


pal = [None] * 200
rain = {}
cur = [W(0x2E5FE + 2 * i) for i in range(16)]   # VBL: movem.l $2e5fe -> $ff8240


def hold(y0, y1):
    for y in range(max(0, y0), min(200, y1)):
        pal[y] = list(cur)


def rainbow(line, a1):
    rain[line] = rain[line + 1] = [W(a1 + 2 * i) for i in range(42)]
    hold(line, line + 2)
    cur[0] = 1                                   # move.w #1,(a0)


def records(a0, line, count):
    """$104FE: every 2 lines colours 0-7 from the record, then two links on."""
    for _ in range(count - 1):
        cur[0:8] = [W(a0 + 2 * i) for i in range(8)]
        hold(line, line + 2)
        line += 2
        a0 = L(L(a0 + 0x10) + 0x10)
    return line


cnt = W(0x843DC)
hold(0, 42)
rainbow(42, 0x843DE + 2 * (cnt >> 1))                 # $13FEA
a0 = L(L(0x4CD24) + 0x10)                            # $10488
cur[1:8] = [W(a0 + 2 * i) for i in range(1, 8)]
a0 = L(L(a0 + 0x10) + 0x10)
cur[8:16] = [W(0x140B8 + 2 * i) for i in range(8)]
hold(44, 46)
line = records(a0, 46, 0x3A)                         # ends at the 58th event
a0 = L(0x4DCD0)                                      # $105B2
cur[0:8] = [W(a0 + 2 * i) for i in range(8)]
hold(line, 167)
n = cnt >> 1
mid_a1 = 0x843DE + 2 * ((0x23 - n) if n else 0)      # $1400E
hold(167, 169)                                      # $105F4: colours 0-3 at line 167, no rainbow
cur[0], cur[1] = L(0x4ED52) >> 16, L(0x4ED52) & 0xFFFF
cur[2], cur[3] = L(0x4D8B8) >> 16, L(0x4D8B8) & 0xFFFF
hold(167, 169)
line = records(0x4D8E4, 169, 0x0D)
hold(line, 197)
rainbow(197, mid_a1)
hold(199, 200)
print('drum chain ended at line', line)

img = Image.new('RGB', (320 + 2 * SIDE, 200 + 2 * VB))
for y in range(-VB, 200 + VB):
    yy = min(max(y, 0), 199)
    p = pal[yy]
    for x in range(-SIDE, 320 + SIDE):
        if 0 <= y < 200 and 0 <= x < 320:
            w = scr + y * 160 + (x // 16) * 8
            b = 15 - (x % 16)
            ci = sum(((W(w + 2 * k) >> b) & 1) << k for k in range(4))
        else:
            ci = 0
        col = p[ci]
        if ci == 0 and y in rain:
            seg = (x + SIDE - RAIN_X0) // 12
            if 0 <= seg < 42:
                col = rain[y][seg]
        img.putpixel((x + SIDE, y + VB), ste(col))
img.save(sys.argv[2])
for y in range(0, 200, 2):
    print(y, ' '.join('%03x' % c for c in pal[y][:8]))
