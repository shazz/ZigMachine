# Print rip/text.dis from TEXT address <hex> for <n> lines.  usage: rout.py <dis> <hex> [n]
import sys

dis, addr = sys.argv[1], int(sys.argv[2], 16)
n = int(sys.argv[3]) if len(sys.argv) > 3 else 60
on = False
for line in open(dis):
    if not on and int(line[:6], 16) >= addr:
        on = True
    if on:
        sys.stdout.write(line)
        n -= 1
        if n == 0:
            break
