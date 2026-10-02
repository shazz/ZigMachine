"""dr.py FILE.dis FROM TO: the lines of a .dis listing whose address is in [FROM, TO)."""
import sys

a, b = int(sys.argv[2], 0), int(sys.argv[3], 0)
for line in open(sys.argv[1]):
    try:
        x = int(line[:6], 16)
    except ValueError:
        continue
    if a <= x < b:
        print(line.rstrip()[:96])
