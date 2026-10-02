"""mklaunch.py OUT.PRG [GAP_HEX]: an AUTO-folder launcher for DUNE.PRG.

DUNE.PRG hardcodes $10000 (MUSIQUE.PRG), $50000 and $60000, so it only works where
the desktop loads it (TPA well above $10000). Run from AUTO, its TEXT would land
around $9000 and MUSIQUE.PRG would overwrite it (bus error in the player).
This launcher Mshrinks itself, Mallocs a GAP to push the next TPA up, then
Pexec(0)s A:\\DUNE.PRG. Hand-assembled (no assembler needed).
"""
import struct
import sys

gap = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0x14000
code = bytearray()
code += bytes.fromhex('2a6f0004')                       # movea.l 4(a7),a5
code += bytes.fromhex('2f3c00000400 2f0d 4267 3f3c004a 4e41 4fef000c')  # Mshrink(a5,$400)
code += bytes.fromhex('2f3c') + struct.pack('>I', gap)  # move.l #gap,-(a7)
code += bytes.fromhex('3f3c0048 4e41 5c8f')             # Malloc
pea_at = len(code)
code += bytes.fromhex('487a0000 487a0000 487a0000')     # pea env / cmd / name (patched)
code += bytes.fromhex('4267 3f3c004b 4e41 4fef0010')    # Pexec(0, name, cmd, env)
code += bytes.fromhex('4267 4e41')                      # Pterm0
name = len(code)
code += b'A:\\DUNE.PRG\x00'
cmd = len(code)
code += b'\x00\x00'
env = cmd + 1
if len(code) & 1:
    code += b'\x00'
for k, target in enumerate((env, cmd, name)):
    at = pea_at + 4 * k + 2                              # displacement word, base = its own address
    struct.pack_into('>h', code, at, target - at)
hdr = struct.pack('>HIIIIIIH', 0x601A, len(code), 0, 0, 0, 0, 0, 0xFFFF)
open(sys.argv[1], 'wb').write(hdr + code)
print(len(code), 'bytes of TEXT, gap', hex(gap))
