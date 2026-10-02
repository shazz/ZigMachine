"""sections.py PROG.dis: the 'set-up' instructions of a linearised VBL program
(anything that is not a repeated data move), with run counts of the bodies
between them -- the program's skeleton."""
import re
import sys

SETUP = re.compile(r'movem|movea\.l  [$#]|move\.l   a[456], |suba|moveq|addi\.l|adda\.l   d[67]|'
                   r'lea\.l    \$[0-9a-f]+\.l|move\.l   \$|jmp|tst|beq|clr|jsr|ff82|\(a3\)')
body = 0
for line in open(sys.argv[1]):
    if SETUP.search(line):
        if body:
            print(f'        ... {body} data instructions')
            body = 0
        print(line.rstrip())
    else:
        body += 1
if body:
    print(f'        ... {body} data instructions')
