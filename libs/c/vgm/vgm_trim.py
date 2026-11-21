"""A VGM cut to start `seconds` in, for BARD benches (libs/c/vgm/README.md "BARD load"): the bench image
has room for ~50 KB of songs and runs a few frames, so it needs the busy middle of a tune, small.

    python3 libs/c/vgm/vgm_trim.py <in.vgm> <out.vgm[z]> <seconds> [keep seconds]

The cut replays the commands before the start into register state (the last write to every YM2612 and
PSG register, every channel's key state, the PCM position) and writes that as the new file's first
commands, then the commands from the start on (for `keep` seconds, then the end). Notes keyed before the
cut start again from their attack, as the engine's own seek does. YM2612 + SN76489 files only (data blocks
of type 0 kept, DAC streams dropped). A .vgz output is gzipped.
"""
import gzip
import struct
import sys

from vgm_write import Vgm

WAITS = {0x62: 735, 0x63: 882}


def decode(d, pos):
    """The command at pos: (what it does or None, its wait in 44.1 kHz samples, its size); None at the end."""
    c = d[pos]
    if c in (0x52, 0x53):
        return ("ym", c & 1, d[pos + 1], d[pos + 2]), 0, 3
    if c == 0x50:
        return ("psg", d[pos + 1]), 0, 2
    if c == 0x61:
        return None, d[pos + 1] | d[pos + 2] << 8, 3
    if c in WAITS:
        return None, WAITS[c], 1
    if 0x70 <= c <= 0x7F:
        return None, (c & 15) + 1, 1
    if 0x80 <= c <= 0x8F:
        return ("dac",), c & 15, 1
    if c == 0x67:
        n = struct.unpack_from("<I", d, pos + 3)[0] & 0x7FFFFFFF
        return ("block", d[pos + 2], d[pos + 7:pos + 7 + n]), 0, 7 + n
    if c == 0xE0:
        return ("seek", struct.unpack_from("<I", d, pos + 1)[0]), 0, 5
    if c == 0x66:
        return None
    n = 1 if c == 0x4F or 0x30 <= c <= 0x3F else 4 if c >= 0x90 else 2
    return ("skip",), 0, n + 1


def parse(d):
    """Every command: (offset, what, wait, size)."""
    ver = struct.unpack_from("<I", d, 8)[0]
    pos = 0x34 + struct.unpack_from("<I", d, 0x34)[0] if ver >= 0x150 else 0x40
    while pos < len(d):
        one = decode(d, pos)
        if one is None:
            return
        yield (pos, *one)
        pos += one[2]


def trim(d, start, keep):
    v = Vgm(ym=struct.unpack_from("<I", d, 0x2C)[0], psg=struct.unpack_from("<I", d, 0x0C)[0])
    ym, keys, psg, pcm, t, body = {}, {}, [], 0, 0, bytearray()
    for pos, cmd, wait, size in parse(d):
        if cmd and cmd[0] == "block" and cmd[1] == 0:
            v.data_block(bytes(cmd[2]))
        if t < start:
            if cmd and cmd[0] == "ym":
                (keys if cmd[2] == 0x28 and cmd[1] == 0 else ym)[(cmd[1], cmd[2]) if cmd[2] != 0x28 else cmd[3] & 7] = cmd
            elif cmd and cmd[0] == "psg":
                psg.append(cmd[1])
            elif cmd and cmd[0] == "dac":
                pcm += 1
            elif cmd and cmd[0] == "seek":
                pcm = cmd[1]
        elif t < start + keep and (not cmd or cmd[0] not in ("block", "skip")):
            body += d[pos:pos + size]
        t += wait
    for (port, reg), cmd in sorted(ym.items(), key=lambda kv: (kv[0][1] & 0xF4 == 0xA0, kv[0])):
        if reg not in (0x2A,) and not (0xA0 <= reg <= 0xA2 or 0xA8 <= reg <= 0xAA):
            v.ym_write(port, reg, cmd[3])
    for (port, reg), cmd in sorted(ym.items()):
        if 0xA0 <= reg <= 0xA2 or 0xA8 <= reg <= 0xAA:
            hi = ym.get((port, reg + 4))
            if hi:
                v.ym_write(port, reg + 4, hi[3])
            v.ym_write(port, reg, cmd[3])
    for b in psg:  # every PSG byte: its registers are latched pairs, replayed in order
        v.psg_write(b)
    for cmd in keys.values():
        v.ym_write(0, 0x28, cmd[3])
    v.pcm_seek(pcm)
    v.cmds += body
    v.samples = keep
    return v.bytes()


def main():
    d = open(sys.argv[1], "rb").read()
    start = int(float(sys.argv[3]) * 44100)
    keep = int(float(sys.argv[4]) * 44100) if len(sys.argv) > 4 else 10 * 44100
    out = trim(d, start, keep)
    if sys.argv[2].endswith(".vgz"):
        out = gzip.compress(out, compresslevel=9, mtime=0)
    open(sys.argv[2], "wb").write(out)
    print(f"{sys.argv[2]}: {len(out)} bytes, from {start / 44100:.1f} s for {keep / 44100:.1f} s")


if __name__ == "__main__":
    main()
