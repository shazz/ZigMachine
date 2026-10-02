"""dam_check.py: the F3 model against the Musashi oracle (m68loop from the
main-loop-entry dump) at many frames over a long run; RAM from $2400 up (the
music replay's state below is not modelled), plus the logo's state."""
import subprocess

import dam_main as D
from dam_model import SNAP, Part

CHECK = [1, 300, 2000, 4000, 4500, 5000, 5500, 6000, 8000, 10000, 12000, 16000, 20000]
subprocess.run(['./m68loop', SNAP, '4ac', str(CHECK[-1]), 'dumps/ol3', ','.join(map(str, CHECK))], check=True)
p = Part()
done = 0
for k in CHECK:
    while done < k:
        D.frame(p)
        done += 1
    ref = open(f'dumps/ol3.{k}', 'rb').read()
    n = sum(1 for i in range(0x2400, 0x7A000) if p.m[i] != ref[i])
    o = int.from_bytes(ref[D.P_STATE:D.P_STATE + 2], 'big'), int.from_bytes(ref[D.P_TAB:D.P_TAB + 4], 'big'), int.from_bytes(ref[D.P_N:D.P_N + 2], 'big')
    print(k, 'logo state', hex(p.w(D.P_STATE)), hex(p.l(D.P_TAB)), p.w(D.P_N), 'oracle', [hex(x) for x in o], 'OK' if n == 0 else f'DIFF {n}')
