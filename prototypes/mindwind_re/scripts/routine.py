"""routine.py <text.dis> <hexaddr> [max_rts]: print a routine from <hexaddr> to its rts, dropping NOPs and
the fullscreen kernel's per-line boilerplate (border switches, line-list loads), so the WORK
interleaved into the kernel reads as plain code. The kernel lines are counted, not printed: '; [k]'
marks how many scanlines passed since the previous printed instruction."""
import re
import sys

KERNEL = {'move.b d0, $820a.w', 'move.b #$2, $820a.w', 'move.l (a5)+, d6', 'move.l (a5)+, d7', 'movea.w #$8240, a0',
          'move.b #$1, (a6)', 'move.w d7, (a0)', 'move.b d0, (a6)', 'movep.l d6, -$5d(a6)', 'move.w d7, $8264.w',
          'move.b #$2, (a6)'}
lines = open(sys.argv[1]).read().splitlines()
start = int(sys.argv[2], 16)
max_rts = int(sys.argv[3]) if len(sys.argv) > 3 else 1
idx = next(i for i, l in enumerate(lines) if int(l[:6], 16) >= start)
rts = 0
k = 0
prev_movep = False
for l in lines[idx:]:
    ins = l[29:].strip()
    if ins == 'nop':
        continue
    was = prev_movep
    prev_movep = ins == 'movep.l d6, -$5d(a6)'
    if ins in KERNEL or (ins == 'swap d7' and was):
        if '#$2, $820a' in ins:
            k += 1
        continue
    print(f'{l[:6]}: {ins}' + (f'   ; [{k} lines]' if k else ''))
    k = 0
    if ins.startswith('rts') or ins.startswith('rte'):
        rts += 1
        if rts >= max_rts:
            break
