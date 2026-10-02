"""mk_f6_sndh.py OUT.sndh: F6's own music as an SNDH -- its sample replay, relocated at init.

F6 plays a ProTracker module (WASTELND, "musicdisk iii - 1725", Mahoney & Kaktus) as
samples on the YM: init $E50E (copies the samples down from $61F00 and builds its tables),
two routines a VBL ($E64A sequencer, $EAB8 channel set-up) and the mixer in Timer C
($ECA8, 2457600 / 4 / $53 = 7.4 kHz, writing three volume registers a sample). Its code
addresses its variables ABSOLUTELY, so the SNDH carries the part's memory from $E50E to
the part's end (the replay, its tables, the module) and a relocation table: the init
below adds (load address - $E50E) to every absolute long in the replay's code (CODE),
points the sample buffer ($61F00) past the image (zeroed memory), then calls $E50E and
starts Timer C as the part does ($FA1D = $10, $FA23 = $53, IERB/IMRB bit 5).
No archive SNDH plays this module (sndh_match.py: nothing).
"""
import re
import struct
import sys

import capstone

PART = '/home/matt/projects/ZigMachine/prototypes/snyd90_re/parts/p6_00c000.bin'
B0, LOAD = 0xE50E, 0xC000
# The replay's code (its variables and tables lie between: $E8F8..$EAB8, $EC90..$ECA8).
CODE = ((0xE50E, 0xE8F8), (0xEAB8, 0xEC90), (0xECA8, 0xED08))
BUF_ADDR = 0x61F00  # the replay's sample buffer top
BUF_SIZE = 0x10000
part = open(PART, 'rb').read()
blob = bytearray(part[B0 - LOAD:])


def relocs() -> tuple[list[int], list[int]]:
    """Offsets (from B0) of the absolute longs in the replay's code; those naming the buffer."""
    md = capstone.Cs(capstone.CS_ARCH_M68K, capstone.CS_MODE_M68K_000 | capstone.CS_MODE_BIG_ENDIAN)
    md.skipdata = True
    rel, buf = [], []
    for ins in (i for lo, hi in CODE for i in md.disasm(bytes(blob[lo - B0:hi - B0]), lo)):
        values = {int(m.group(1), 16) for m in re.finditer(r'\$([0-9a-f]+)\.l', ins.op_str)}
        values |= {int(m.group(1), 16) for m in re.finditer(r'#\$([0-9a-f]+)', ins.op_str)}
        for k in range(2, ins.size - 3, 2):
            v = struct.unpack('>I', ins.bytes[k:k + 4])[0]
            if v not in values:
                continue
            if v == BUF_ADDR:
                buf.append(ins.address - B0 + k)
            elif LOAD <= v < LOAD + len(part):
                rel.append(ins.address - B0 + k)
    return rel, buf


code = bytearray()


def w(*xs: int) -> None:
    for x in xs:
        code.extend(struct.pack('>H', x & 0xFFFF))


def l(x: int) -> None:
    code.extend(struct.pack('>I', x & 0xFFFFFFFF))


fixups = []  # (offset of a pc-relative word, label)


def pc(op: int, label: str) -> None:
    w(op)
    fixups.append((len(code), label))
    w(0)


def build() -> bytes:
    rel, buf = relocs()
    assert len(buf) == 1, buf
    hdr = bytearray(b'\x60\x00\x00\x00' * 3 + b'SNDH')
    for tag in (b'TITLWasteland (SNYD 90 F6)\0', b'COMMMahoney & Kaktus\0',
                b'RIPPthe SYNC part of the Swedish New Year Demo disk (SNYD_90.MSA)\0',
                b'YEAR1990\0', b'##01\0', b'!V50\0', b'FLAG~c\0'):  # VBL: Timer C is the mixer's
        hdr += tag
    if len(hdr) & 1:
        hdr += b'\0'
    hdr += b'HDNS'
    base = len(hdr)
    labels = {'init': base}
    w(0x48E7, 0xFFFE)
    pc(0x41FA, 'blob')                          # lea blob(pc),a0
    w(0x2208, 0x0481); l(B0)                    # move.l a0,d1; sub.l #B0,d1
    pc(0x43FA, 'relocs')                        # lea relocs(pc),a1
    w(0x3019)                                   # move.w (a1)+,d0
    loop = len(code)
    w(0x3419, 0xD3B0, 0x2000)                   # move.w (a1)+,d2; add.l d1,0(a0,d2.w)
    w(0x51C8, loop - (len(code) + 2))           # dbra d0,loop
    w(0x2408, 0x0682); l(len(blob) + BUF_SIZE)  # move.l a0,d2; add.l #top,d2
    w(0x2142, buf[0])                           # move.l d2,buf(a0)
    w(0x4E90)                                   # jsr (a0): $E50E
    pc(0x41FA, 'blob')                          # (the init changes a0)
    w(0x43E8, 0xECA8 - B0, 0x21C9, 0x0114)      # lea timer_c(a0),a1; move.l a1,$114.w
    w(0x11FC, 0x0000, 0xFA1D, 0x11FC, 0x0053, 0xFA23, 0x11FC, 0x0010, 0xFA1D)
    w(0x08F8, 0x0005, 0xFA09, 0x08F8, 0x0005, 0xFA15)
    w(0x4CDF, 0x7FFF, 0x4E75)
    labels['exit'] = base + len(code)
    w(0x08B8, 0x0005, 0xFA09)                   # Timer C off
    for reg in (8, 9, 10):
        w(0x11FC, reg, 0x8800, 0x11FC, 0, 0x8802)
    w(0x4E75)
    labels['play'] = base + len(code)
    w(0x48E7, 0xFFFE)
    pc(0x41FA, 'blob')
    w(0x4EA8, 0xE64A - B0)                      # jsr $E64A
    pc(0x41FA, 'blob')
    w(0x4EA8, 0xEAB8 - B0)                      # jsr $EAB8
    w(0x4CDF, 0x7FFF, 0x4E75)
    labels['relocs'] = base + len(code)
    w(len(rel) - 1, *rel)
    labels['blob'] = base + len(code)
    for at, name in fixups:
        code[at:at + 2] = struct.pack('>h', labels[name] - (base + at))
    for k, name in enumerate(('init', 'exit', 'play')):
        hdr[4 * k + 2:4 * k + 4] = struct.pack('>h', labels[name] - (4 * k + 2))
    print(f'{len(rel)} relocations, buffer at +{len(blob):#x}', file=sys.stderr)
    return bytes(hdr) + bytes(code) + bytes(blob)


if __name__ == '__main__':
    open(sys.argv[1], 'wb').write(build())
