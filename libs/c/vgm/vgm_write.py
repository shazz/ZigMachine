"""A minimal VGM 1.60 writer for our own test tunes (libs/c/vgm/test_vgms.py, the cart's tune).

The file is everything this module makes: no third-party music. VGM layout from the VGM specification
(vgmrips.net, v1.71): a 0x100-byte header (data at 0x100), little-endian fields.
"""
import struct

NTSC_YM = 7670453
NTSC_PSG = 3579545


class Vgm:
    def __init__(self, ym=NTSC_YM, psg=NTSC_PSG):
        self.ym, self.psg = ym, psg
        self.cmds = bytearray()
        self.samples = 0
        self.loop_at = None
        self.pcm = b""

    def ym_write(self, port, reg, val):
        self.cmds += bytes([0x52 + port, reg & 0xFF, val & 0xFF])

    def psg_write(self, byte):
        self.cmds += bytes([0x50, byte & 0xFF])

    def wait(self, n):
        self.samples += n
        while n > 0:
            k = min(n, 65535)
            self.cmds += bytes([0x61]) + struct.pack("<H", k)
            n -= k

    def data_block(self, pcm):
        """The YM2612 PCM bank (type 0); write before the commands that play it."""
        self.pcm += pcm
        self.cmds += bytes([0x67, 0x66, 0x00]) + struct.pack("<I", len(pcm)) + pcm

    def pcm_seek(self, off):
        self.cmds += bytes([0xE0]) + struct.pack("<I", off)

    def dac_wait(self, n):
        """0x8n: the bank's next byte to the DAC, then wait n (0..15)."""
        self.samples += n
        self.cmds += bytes([0x80 | n])

    def loop_here(self):
        self.loop_at = len(self.cmds)

    def bytes(self):
        body = self.cmds + b"\x66"
        h = bytearray(0x100)
        h[0:4] = b"Vgm "
        struct.pack_into("<I", h, 0x04, 0x100 + len(body) - 4)
        struct.pack_into("<I", h, 0x08, 0x160)
        struct.pack_into("<I", h, 0x0C, self.psg)
        struct.pack_into("<I", h, 0x18, self.samples)
        if self.loop_at is not None:
            struct.pack_into("<I", h, 0x1C, 0x100 + self.loop_at - 0x1C)
        struct.pack_into("<I", h, 0x24, 60)
        struct.pack_into("<H", h, 0x28, 0x0009)  # SN76489 feedback: the Sega taps
        h[0x2A] = 16  # shift register width
        struct.pack_into("<I", h, 0x2C, self.ym)
        struct.pack_into("<I", h, 0x34, 0x100 - 0x34)
        return bytes(h) + bytes(body)


# The YM2612's operator register offsets in slot order S1, S3, S2, S4 are 0, 4, 8, C; by operator
# number (op1..op4) they are 0, 8, 4, C.
OP_OFF = (0x0, 0x8, 0x4, 0xC)


def patch(v, ch, alg, fb, ops, pan=0xC0, ams=0, pms=0):
    """ops: four dicts by operator number (1..4): dt, mul, tl, ks, ar, dr, sr, sl, rr, am, ssg."""
    port, c = ch // 3, ch % 3
    for i, o in enumerate(ops):
        r = OP_OFF[i] + c
        v.ym_write(port, 0x30 + r, o.get("dt", 0) << 4 | o.get("mul", 1))
        v.ym_write(port, 0x40 + r, o.get("tl", 0))
        v.ym_write(port, 0x50 + r, o.get("ks", 0) << 6 | o.get("ar", 31))
        v.ym_write(port, 0x60 + r, o.get("am", 0) << 7 | o.get("dr", 0))
        v.ym_write(port, 0x70 + r, o.get("sr", 0))
        v.ym_write(port, 0x80 + r, o.get("sl", 0) << 4 | o.get("rr", 15))
        v.ym_write(port, 0x90 + r, o.get("ssg", 0))
    v.ym_write(port, 0xB0 + c, fb << 3 | alg)
    v.ym_write(port, 0xB4 + c, pan | ams << 4 | pms)


def freq(v, ch, block, fnum):
    port, c = ch // 3, ch % 3
    v.ym_write(port, 0xA4 + c, block << 3 | fnum >> 8)
    v.ym_write(port, 0xA0 + c, fnum & 0xFF)


def key(v, ch, ops=0xF):
    v.ym_write(0, 0x28, ops << 4 | (ch % 3 + (4 if ch >= 3 else 0)))
