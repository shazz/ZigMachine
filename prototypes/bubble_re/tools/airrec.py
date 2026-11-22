#!/usr/bin/env python3
"""Print AIRFLOW.DAT's record for rounds (1-based) given on the command line."""
import os
import sys

RE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
air = open(os.path.join(RE, 'files', 'GRAPHICS', 'AIRFLOW.DAT'), 'rb').read()


def walk(n):
    p = 0x12C
    for _ in range(n):
        b = air[p]
        p += 1 if (b & 0x80 or b == 0) else b & 0x7F
    return p


for r in map(int, sys.argv[1:]):
    p = walk(r - 1)
    b = air[p]
    print('round %d at $%x: %s' % (r, p, air[p:p + max(1, b & 0x7f if not b & 0x80 else 1)].hex(' ')))
