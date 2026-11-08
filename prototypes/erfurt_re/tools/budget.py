# Split one Hatari frame profile (profile_frame's per-frame dump) into the menu's routines.
import re, sys
R = [  # (start, name) — each range runs to the next start
    (0x10000, 'other'), (0x101CA, 'IDLE: main waits for the VBL'), (0x101E8, 'other'),
    (0x1024E, 'VBL'), (0x10294, 'other'), (0x102B2, 'Timer B: rainbow 42 + records'),
    (0x10844, 'other'), (0x1085A, 'beam waits ($1085A)'), (0x10884, 'other'),
    (0x10FEE, 'VBL: colour records ($10FEE)'), (0x111E8, 'other'),
    (0x1135A, 'main: spin'), (0x116DE, 'faces'), (0x117B0, 'slot text render'), (0x11A20, 'other'),
    (0x11ABA, 'keys'), (0x11BFE, 'other'), (0x11D38, 'drum draw'), (0x11F66, 'floor'), (0x12086, 'other'),
    (0x1221A, 'shadow'), (0x122BA, 'other'), (0x122F2, 'sparkle'), (0x126E0, 'glint dispatch'),
    (0x12724, 'other'), (0x12784, 'VBL: drum colours ($12784)'), (0x12876, 'precache ($12876)'),
    (0x12A00, 'jelly'), (0x12C68, 'other'), (0x12EB4, 'scroller init'),
    (0x13178, 'scroller column ($13178/$13430)'), (0x13D0E, 'scroller draw'), (0x13EC8, 'scroller columns'),
    (0x13F54, 'other'), (0x14B48, 'glint code'), (0x1F918, 'other'),
    (0x20B68, 'MUSIC (SNDH)'), (0x2E5FE, 'other'),
]
tot = {}
for line in open(sys.argv[1]):
    m = re.match(r'^([0-9a-f]{8}) .*\((\d+), (\d+),', line)
    if not m:
        continue
    a, cyc = int(m.group(1), 16), int(m.group(3))
    name = 'TOS/other'
    for s, n in R:
        if a >= s:
            name = n
    if a >= 0x31400:
        name = 'TOS/other'
    tot[name] = tot.get(name, 0) + cyc
T = sum(tot.values())
for n, c in sorted(tot.items(), key=lambda x: -x[1]):
    print('%-36s %7d  %5.1f%%' % (n, c, 100 * c / 160256))
print('total', T)
