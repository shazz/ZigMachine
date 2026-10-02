"""List / extract every file of the SNYD_89.ST FAT12 image (media byte F7 defeats mtools)."""
import os
import struct
import sys

d = open(sys.argv[1], 'rb').read()
outdir = sys.argv[2]
os.makedirs(outdir, exist_ok=True)
bps, spc, res, nfats, ndir, tot, media, spf = struct.unpack('<HBHBHHBH', d[11:24])
fat = d[res * bps:(res + spf) * bps]
root = (res + nfats * spf) * bps
data0 = root + ndir * 32


def nxt(c):
    o = c * 3 // 2
    v = fat[o] | (fat[o + 1] << 8)
    return (v >> 4) if c & 1 else (v & 0xFFF)


def chain(c, size):
    out = bytearray()
    while 2 <= c < 0xFF0:
        o = data0 + (c - 2) * spc * bps
        out += d[o:o + spc * bps]
        c = nxt(c)
    return bytes(out[:size])


def walk(off, n, path):
    for i in range(n):
        e = d[off + 32 * i: off + 32 * i + 32]
        if e[0] in (0, 0xE5) or e[0] == 0x2E:
            continue
        name = e[:8].decode('latin1').rstrip()
        ext = e[8:11].decode('latin1').rstrip()
        attr = e[11]
        cl = struct.unpack('<H', e[26:28])[0]
        size = struct.unpack('<I', e[28:32])[0]
        full = name + ('.' + ext if ext else '')
        print(f'{path}{full:14s} attr={attr:02x} cl={cl:4d} size={size}')
        if attr & 0x10:
            sub = chain(cl, 1 << 20)
            os.makedirs(os.path.join(outdir, path, full), exist_ok=True)
            # a subdirectory is a chain of clusters; walk its entries in place
            tmp = sub
            for j in range(len(tmp) // 32):
                e2 = tmp[32 * j:32 * j + 32]
                if e2[0] == 0:
                    break
            walk_bytes(tmp, path + full + '/')
        else:
            open(os.path.join(outdir, path, full), 'wb').write(chain(cl, size))


def walk_bytes(buf, path):
    global d
    for j in range(len(buf) // 32):
        e = buf[32 * j:32 * j + 32]
        if e[0] == 0:
            break
        if e[0] in (0xE5, 0x2E):
            continue
        name = e[:8].decode('latin1').rstrip()
        ext = e[8:11].decode('latin1').rstrip()
        attr = e[11]
        cl = struct.unpack('<H', e[26:28])[0]
        size = struct.unpack('<I', e[28:32])[0]
        full = name + ('.' + ext if ext else '')
        print(f'{path}{full:14s} attr={attr:02x} cl={cl:4d} size={size}')
        if not attr & 0x10:
            open(os.path.join(outdir, path, full), 'wb').write(chain(cl, size))


print('bps', bps, 'spc', spc, 'res', res, 'fats', nfats, 'dir', ndir, 'tot', tot, 'media', hex(media), 'spf', spf)
walk(root, ndir, '')
