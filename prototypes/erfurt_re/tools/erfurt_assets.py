# Rip the Erfurt Megademo menu's assets for apps/zig/scenes/erfurt_menu.
#   erfurt_assets.py <menu_d1_at10000.bin> <post-init RAM dump> <out dir>
# The menu file is the menu extracted from the disks and relocated to $10000 (kept locally).
# Tables the menu GENERATES at init (drum font, colour ramps, floor patterns) are taken
# from a RAM dump of the running menu: they never change after init (checked across
# consecutive frames). Every table is the original's; nothing is re-derived.
import os, struct, sys

menu = open(sys.argv[1], 'rb').read()
ram = open(sys.argv[2], 'rb').read()
out = sys.argv[3]
os.makedirs(out, exist_ok=True)


def f(addr, n):                       # bytes of the relocated menu file at a run address
    return menu[addr - 0x10000: addr - 0x10000 + n]


def m(addr, n):                       # bytes of the post-init RAM
    return ram[addr: addr + n]


def put(name, data):
    open(os.path.join(out, name), 'wb').write(data)
    print('%-16s %6d bytes' % (name, len(data)))


put('logo.raw', f(0x2E61E, 43 * 160))          # 43 lines, ST planar, 4 planes
put('logo_pal.dat', f(0x2E5FE, 32))            # 16 STE words
put('rainbow.dat', f(0x140C8, 35 * 2))         # $140C8: the hue wheel
put('profile.dat', f(0x31022, 91 * 2) + f(0x310D8, 91 * 2))   # drum front / back profiles
put('scrollfont.raw', f(0x308A2, 60 * 32))     # 60 glyphs, 16x16, 1 plane
text = f(0x1FB31, 0x2000)
put('scrolltext.txt', text[:text.index(b'\0')])
put('sine.dat', f(0x3118E, 256 * 2))           # 256 words, +-2048
put('kick.dat', f(0x1F91A, 21 * 2))            # the drum's hop impulses
put('shadow.raw', f(0x14130, 8 * 0x120))       # 8 x 12 rows x 12 words (plane 1)
put('sparkle.dat', f(0x14A30, 8 * 2))          # sparkle band widths
# generated at init (RAM)
put('drumfont.raw', m(0x60CB0, 0x40 * 32))     # 64 glyphs ' '..'_', 16x16
put('ramp_scroll.dat', m(0x4DD36, 280 * 4))    # G: scroller colours (hi word used)
put('ramp_drum.dat', m(0x4E462, 280 * 4))      # D: drum front (hi) / back (lo)
put('floor.raw', m(0x4EDCE, 0xC300))           # 8x16 + 11x32 + 12x64 patterns, 20 words
put('floor_z.dat', m(0x4ED14, 31 * 2))         # per floor line depth phase

# The generated "eori #imm,d16(a1)" code of the logo glint ($14A40: 66 pointers) as data:
# per step a count, then (byte offset, xor word) pairs.
glint = bytearray()
L = lambda a: struct.unpack('>I', f(a, 4))[0]
for step in range(0x42):
    pc = L(0x14A40 + 4 * step)
    ops = []
    while True:
        op = struct.unpack('>H', f(pc, 2))[0]
        if op == 0x4E75:
            break
        if op == 0x0A69:                       # eori.w #imm,d16(a1)
            imm, d16 = struct.unpack('>Hh', f(pc + 2, 4))
            ops.append((d16, imm))
            pc += 6
        elif op == 0x0AA9:                     # eori.l #imm,d16(a1)
            imm, d16 = struct.unpack('>Ih', f(pc + 2, 6))
            ops.append((d16, imm >> 16))
            ops.append((d16 + 2, imm & 0xFFFF))
            pc += 8
        else:
            raise SystemExit('glint step %d: unexpected opcode %04x at %x' % (step, op, pc))
    glint += struct.pack('>H', len(ops))
    for d16, v in ops:
        assert 0 <= d16 < 43 * 160, d16
        glint += struct.pack('>HH', d16, v)
put('glint.dat', bytes(glint))

# Floor colours 0-3 per row pair, lines 167..198, walked off the Timer-B chain
W = lambda a: struct.unpack('>H', m(a, 2))[0]
LL = lambda a: struct.unpack('>I', m(a, 4))[0]
rows = [LL(0x4ED52) >> 16, LL(0x4ED52) & 0xFFFF, LL(0x4D8B8) >> 16, LL(0x4D8B8) & 0xFFFF]
fl = bytearray(struct.pack('>4H', *rows))      # line 167
a0 = 0x4D8E4
for _ in range(12):
    fl += struct.pack('>4H', *[W(a0 + 2 * i) for i in range(4)])
    a0 = LL(LL(a0 + 0x10) + 0x10)
put('floor_pal.dat', bytes(fl))                # 13 x 4 words
