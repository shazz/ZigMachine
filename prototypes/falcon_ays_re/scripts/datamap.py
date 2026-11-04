# DATA segment map from the relocations: every DATA address the TEXT references, the size up to
# the next referenced address, and the TEXT pcs that reference it. usage: datamap.py <text.dis>
import collections
import re
import sys

refs = collections.defaultdict(list)
for line in open(sys.argv[1]):
    pc = line[:6]
    for a in re.findall(r'D:([0-9a-f]{6})', line):
        refs[int(a, 16)].append(pc)
DATA_END = 54074 + 1863374
addrs = sorted(refs)
for i, a in enumerate(addrs):
    nxt = addrs[i + 1] if i + 1 < len(addrs) else DATA_END
    pcs = sorted(set(refs[a]))
    print('%06x %8d  %s' % (a, nxt - a, ' '.join(pcs[:6]) + (' ...' if len(pcs) > 6 else '')))
