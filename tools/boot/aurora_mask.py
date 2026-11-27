"""Variant G's aurora stream: per half frame, a change MASK and one nibble CODE per changed pixel (no ZX0).

G stores the final 565 picture's 16-bit wrapping difference from the previous frame. ZX0 of those deltas cost the
board ~4 Mc a frame (its bit reader is ~2.5 of the 2.9 Mc the cart spent: docs/boot/AURORA_BOOT.md), so G keeps no
entropy coder at all. Only ~18 % of the band's pixels change a frame, and only 97 distinct deltas exist over the film
(within 2 levels a channel for 98.6 % of them), so:

  container = row0 u8, rows u8, mask_len u16 LE, mask (mask_len bytes), codes (the rest)
  mask      rows x W/8 bytes (40 at 320, 50 at 400), one bit a pixel (MSB = leftmost), a changed pixel = 1; a run
            of zero bytes is written 0x00, n (n = 1..255 zero bytes)
  codes     a nibble per changed pixel in mask order, low nibble first: 0..14 = DELTAS[code]; 15 = escape, the next
            two nibbles (low, high) are the index into DELTAS (>= 15); then PAD zero bytes, so the cart checks the
            stream's end once per mask byte (8 pixels, at most 24 nibbles) instead of once per nibble

DELTAS is sorted by frequency (the top 15 cover ~93 % of the changes). Each frame is two containers, unpacked on the
two 60 Hz frames it is shown on; the split row is chosen per frame so both halves carry about the same number of
changed pixels (the cost is per changed pixel, so the busier 60 Hz frame sets the frame rate).
"""
import numpy as np

ESC = 15
PAD = 12  # zero bytes after the codes: 24 nibbles, the most one mask byte can read


class MaskError(ValueError):
    pass


def delta_table(d, changed):
    """u16 deltas sorted by how often they occur (most first): the codes' table."""
    vals, counts = np.unique(d[changed], return_counts=True)
    if len(vals) > 255:
        raise MaskError(f"{len(vals)} distinct deltas: an escape index is one byte")
    return vals[np.argsort(-counts, kind="stable")].astype(np.uint16)


def split_row(changed):
    """The row (1..rows-1 when it can) where the changed pixels above and below are nearest equal."""
    per_row = changed.sum(1)
    cum = np.cumsum(per_row)
    return int(np.argmin(np.abs(2 * cum[:-1] - cum[-1]))) + 1 if len(per_row) > 1 else len(per_row)


def zero_runs(mask):
    out = bytearray()
    i, n = 0, len(mask)
    while i < n:
        if mask[i]:
            out.append(mask[i])
            i += 1
            continue
        j = i
        while j < n and mask[j] == 0 and j - i < 255:
            j += 1
        out += bytes((0, j - i))
        i = j
    return bytes(out)


def nibbles(codes):
    """Codes (each < len(table)) as the nibble stream, escapes included, packed low nibble first."""
    nib = []
    for c in codes:
        nib += [int(c)] if c < ESC else [ESC, int(c) & 15, int(c) >> 4]
    if len(nib) & 1:
        nib.append(0)
    a = np.array(nib, np.uint8).reshape(-1, 2)
    return (a[:, 0] | (a[:, 1] << 4)).astype(np.uint8).tobytes()


def container(d, changed, row0, code_of):
    """One container for rows [row0, row0 + len(d)) of the band."""
    rows = len(d)
    if row0 > 255 or rows > 255:
        raise MaskError(f"rows {row0}+{rows}: the header holds bytes")
    mask = zero_runs(np.packbits(changed, axis=1).ravel())
    if len(mask) > 0xFFFF:
        raise MaskError("mask over 64 KB")
    head = bytes((row0, rows)) + len(mask).to_bytes(2, "little")
    return head + mask + nibbles(code_of[d[changed]]) + bytes(PAD)


def encode(d, table):
    """(blob, offsets u32 LE (2n + 1), split rows): two containers per frame of u16 deltas d (n, rows, W)."""
    code_of = np.zeros(65536, np.uint16)
    code_of[table] = np.arange(len(table))
    parts, splits = [], []
    for t in range(len(d)):
        ch = d[t] != 0
        s = split_row(ch)
        splits.append(s)
        parts += [container(d[t, :s], ch[:s], 0, code_of), container(d[t, s:], ch[s:], s, code_of)]
    offs = np.cumsum([0] + [len(p) for p in parts]).astype("<u4").tobytes()
    return b"".join(parts), offs, splits


def apply(plane, c, table, band_rows):
    """The cart's loop (masked.zig) in Python: add container `c` to `plane` (band rows x W u16, in place)."""
    row_bytes = plane.shape[1] // 8
    if len(c) < 4:
        raise MaskError("short container")
    row0, rows, mlen = c[0], c[1], int.from_bytes(c[2:4], "little")
    if row0 + rows > band_rows or 4 + mlen > len(c):
        raise MaskError("container header out of range")
    mask, codes = c[4:4 + mlen], c[4 + mlen:]
    bits, i = bytearray(), 0
    while i < mlen:
        if mask[i] == 0:
            bits += bytes(mask[i + 1])
            i += 2
        else:
            bits.append(mask[i])
            i += 1
    if len(bits) != rows * row_bytes:
        raise MaskError(f"mask is {len(bits)} bytes, {rows * row_bytes} expected")
    nib = np.stack([np.frombuffer(codes, np.uint8) & 15, np.frombuffer(codes, np.uint8) >> 4], 1).ravel()
    at = np.nonzero(np.unpackbits(np.frombuffer(bytes(bits), np.uint8)))[0]
    n = 0
    flat = plane[row0:row0 + rows].reshape(-1)
    for p in at:
        k = int(nib[n])
        n += 1
        if k == ESC:
            k = int(nib[n]) | int(nib[n + 1]) << 4
            n += 2
        flat[p] = (int(flat[p]) + int(table[k])) & 0xFFFF
