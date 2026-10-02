"""ST RAM -> chunky/RGB helpers shared by the model/compare scripts."""
import struct

import numpy as np


def st_rgb(w):
    def c(n):
        n &= 0xF
        n = ((n & 7) << 1) | (n >> 3)
        return n * 17
    return (c(w >> 8), c(w >> 4), c(w))


def palette(mem, at):
    return np.array([st_rgb(v) for v in struct.unpack('>16H', bytes(mem[at:at + 32]))], np.uint8)


def chunky(mem, addr, stride, lines, width=None):
    """Indices [lines, width] of a planar screen whose lines are `stride` bytes."""
    width = width or (stride // 8) * 16
    groups = (width + 15) // 16
    out = np.zeros((lines, groups * 16), np.uint8)
    buf = np.frombuffer(bytes(mem[addr:addr + stride * lines + 8]), np.uint8)
    for y in range(lines):
        row = buf[y * stride: y * stride + groups * 8].reshape(groups, 4, 2)
        words = (row[:, :, 0].astype(np.uint16) << 8) | row[:, :, 1]
        for b in range(16):
            bits = (words >> (15 - b)) & 1
            out[y, b::16] = bits[:, 0] | (bits[:, 1] << 1) | (bits[:, 2] << 2) | (bits[:, 3] << 3)
    return out[:, :width]
