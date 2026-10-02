"""bspr_check.py: the F2 model against the Musashi oracle (m68loop from the
Hatari dump h2.2400, 142 main-loop passes after the loop started) at many
frames over a long run: screens, erase tables and the state variables."""
import subprocess

import bspr_model as B

START = 142
CHECK = [2, 60, 200, 201, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 5000, 6000, 8000]
subprocess.run(['./m68loop', 'dumps/h2.2400', '1140', str(CHECK[-1]), 'dumps/ol2',
                ','.join(map(str, CHECK))], check=True)
p = B.Part()
done = 0
for k in CHECK:
    while done < START + k:
        p.frame()
        done += 1
    ref = open(f'dumps/ol2.{k}', 'rb').read()
    bad = []
    for name, lo, hi in (('screen A', B.SCR_A, B.SCR_A + 0xE900), ('screen B', B.SCR_B, B.SCR_B + 0xE900),
                         ('tables+vars', 0x12636, 0x12A68)):
        n = sum(1 for i in range(lo, hi) if p.m[i] != ref[i])
        if n:
            bad.append(f'{name} {n}')
    print(k, 'state', p.w(B.V_PSTATE), hex(p.l(B.V_PATH)), 'glob', p.w(B.V_GSTATE), hex(p.l(B.V_GLOB)),
          'OK' if not bad else 'DIFF ' + ', '.join(bad))
