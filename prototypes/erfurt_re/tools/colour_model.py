# Check the per-line colour model against reconstruct.py's chain walk.
#   scroller colour (c4, c6) of line y = hi word of long G[(y - 43) + phase], G = $4DD36
#   drum colours: long D[(y - 43) + $99 - phase], D = $4E462: c1 = c3 = c5 = c7 = hi, c2 = lo
import struct, subprocess, sys
dump = sys.argv[1]
r = open(dump, 'rb').read()
W = lambda a: struct.unpack('>H', r[a:a + 2])[0]
L = lambda a: struct.unpack('>I', r[a:a + 4])[0]
out = subprocess.run([sys.executable, '-P', 'tools/reconstruct.py', dump, 'work/_tmp.png'],
                     capture_output=True, text=True).stdout
rows = {}
for ln in out.splitlines()[1:]:
    p = ln.split()
    if len(p) == 9:
        rows[int(p[0])] = [int(x, 16) for x in p[1:]]
phase = W(0x4EB8E)
print('phase', phase, 'drum top', W(0x4EB98), 'n', W(0x4EB9A), 'bottom', W(0x4EBCC))
bad = 0
for y in range(44, 167, 2):
    g = L(0x4DD36 + 4 * ((y - 43) + phase)) >> 16
    d = L(0x4E462 + 4 * ((y - 43) + 0x99 - phase))
    got = rows[y]
    ok_s = got[4] == g and got[6] == g
    ok_d = got[1] in (d >> 16, 0, 0x777) and got[2] in (d & 0xFFFF, 0, 0x012)
    if not (ok_s and ok_d):
        bad += 1
        print(y, ['%03x' % c for c in got], 'pred g %03x d %08x' % (g, d))
print('mismatching pairs', bad)
