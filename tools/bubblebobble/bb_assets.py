#!/usr/bin/env python3
"""Bubble Bobble (Go/Ebitengine remake) -> ZigMachine cart assets.

Source : the olivierh59500 Go remake's resources/ (clone of go-bubblebobble).
Outputs: apps/zig/assets/screens/bubblebobble/*.bin and the generated table file
         apps/zig/scenes/bubblebobble/assets.zig.

The Go draws on a 768x720 canvas whose playfield is 32x26 tiles of 24px
(768x624) with a 48px HUD strip top and bottom. The cart's plane is the 400x280
overscan one and the whole canvas maps by /3 to 256x240, so the playfield is
256x208 (exactly the arcade's 32x26 tiles of 8px). Frames keep their NATIVE
pixel size and the scene scales them at blit time with the Go's own goal sizes
/3 (48 -> 16, 44 -> 15, 32 -> 11 ...); tiles and the logo are pre-scaled here.

Music is the original's five YM5/YM6 tunes (LHA-wrapped, so decoded here) turned
into the same per-frame register DELTA stream larcociel5 uses: one 50 Hz frame
per tick through zg.ymWrite. SFX are the ten WAVs re-rendered to the cart
audio ring's 12 kHz signed 8-bit mono.
"""
import json
import os
import struct
import sys
import wave

from PIL import Image

SRC = "/tmp/opencode/bubblebobble/resources"
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "apps", "zig", "assets", "screens", "bubblebobble")
GEN = os.path.join(os.path.dirname(__file__), "..", "..", "apps", "zig", "scenes", "bubblebobble", "assets.zig")

RING_RATE = 12000  # the cart audio ring's rate (kickoff2 uses the same)


# --------------------------------------------------------------------------
# LHA -lh5- (port of ym-player/pkg/lzh, used by the original's .ym archives)
# --------------------------------------------------------------------------
BITBUFSIZ = 16
DICBIT = 13
DICSIZ = 1 << DICBIT
MAXMATCH = 256
THRESHOLD = 3
UCHAR_MAX = 255
NC = UCHAR_MAX + MAXMATCH + 2 - THRESHOLD
CBIT = 9
CODE_BIT = 16
NP = DICBIT + 1
NT = CODE_BIT + 3
PBIT = 4
TBIT = 5
NPT = NT


class LzhError(Exception):
    pass


class _Lzh:
    def __init__(self, data):
        self.input = bytes(data)
        self.inputPos = 0
        self.bitbuf = 0
        self.subbitbuf = 0
        self.bitcount = 0
        self.bitsRemaining = 0
        self.left = [0] * (2 * NC - 1)
        self.right = [0] * (2 * NC - 1)
        self.c_len = [0] * NC
        self.pt_len = [0] * NPT
        self.c_table = [0] * 4096
        self.pt_table = [0] * 256
        self.blocksize = 0
        self.decode_j = 0
        self.decode_i = 0
        self.outbuf = bytearray(DICSIZ)

    def fillbuf(self, n):
        if n < 0 or n > BITBUFSIZ or n > self.bitsRemaining:
            raise LzhError("truncated or invalid LZH bitstream")
        self.bitsRemaining -= n
        self.bitbuf = (self.bitbuf << n) & 0xFFFF
        while n > self.bitcount:
            self.bitbuf |= (self.subbitbuf << (n - self.bitcount)) & 0xFFFF
            n -= self.bitcount
            if self.inputPos < len(self.input):
                self.subbitbuf = self.input[self.inputPos]
                self.inputPos += 1
            else:
                self.subbitbuf = 0
            self.bitcount = 8
        self.bitcount -= n
        self.bitbuf |= self.subbitbuf >> self.bitcount

    def getbits(self, n):
        x = self.bitbuf >> (BITBUFSIZ - n)
        self.fillbuf(n)
        return x

    def init_getbits(self):
        self.bitbuf = 0
        self.subbitbuf = 0
        self.bitcount = 0
        self.inputPos = 0
        self.bitsRemaining = len(self.input) * 8 + BITBUFSIZ
        self.fillbuf(BITBUFSIZ)

    def make_table(self, nchar, bitlen, tablebits, table):
        count = [0] * 17
        nxt = [0] * 17
        for i in range(nchar):
            length = bitlen[i]
            if length > 16:
                raise LzhError("invalid LZH Huffman code length")
            if length != 0:
                count[length] += 1
        code = 0
        for length in range(1, 17):
            code = (code + count[length - 1]) << 1
            nxt[length] = code
            if code + count[length] > (1 << length):
                raise LzhError("oversubscribed LZH Huffman tree")
        if code + count[16] != (1 << 16):
            raise LzhError("incomplete LZH Huffman tree")
        for i in range(len(table)):
            table[i] = 0
        available = nchar

        def cget(ref):
            k, i = ref
            return (table if k == 0 else self.left if k == 1 else self.right)[i]

        def cset(ref, v):
            k, i = ref
            if k == 0:
                table[i] = v
            elif k == 1:
                self.left[i] = v
            else:
                self.right[i] = v

        for symbol in range(nchar):
            length = bitlen[symbol]
            if length == 0:
                continue
            code = nxt[length]
            nxt[length] += 1
            if length <= tablebits:
                for i in range(code << (tablebits - length), (code + 1) << (tablebits - length)):
                    table[i] = symbol
                continue
            ref = (0, code >> (length - tablebits))
            for bit in range(length - tablebits - 1, -1, -1):
                if cget(ref) == 0:
                    if available >= len(self.left):
                        raise LzhError("LZH Huffman tree is too large")
                    self.left[available] = 0
                    self.right[available] = 0
                    cset(ref, available)
                    available += 1
                e = cget(ref)
                if e < nchar or e >= available:
                    raise LzhError("invalid LZH Huffman branch")
                ref = (1, e) if (code & (1 << bit)) == 0 else (2, e)
            cset(ref, symbol)

    def tree_symbol(self, symbol, alphabet, tablebits):
        mask = 1 << (BITBUFSIZ - 1 - tablebits)
        while symbol >= alphabet:
            if mask == 0 or symbol >= len(self.left):
                raise LzhError("invalid LZH Huffman tree")
            symbol = self.left[symbol] if (self.bitbuf & mask) == 0 else self.right[symbol]
            mask >>= 1
        return symbol

    def read_pt_len(self, nn, nbit, i_special):
        n = self.getbits(nbit)
        if n > nn:
            raise LzhError("invalid LZH position table length")
        if n == 0:
            c = self.getbits(nbit)
            if c >= nn:
                raise LzhError("invalid LZH position symbol")
            for i in range(nn):
                self.pt_len[i] = 0
            for i in range(256):
                self.pt_table[i] = c
        else:
            i = 0
            while i < n:
                c = self.bitbuf >> (BITBUFSIZ - 3)
                if c == 7:
                    mask = 1 << (BITBUFSIZ - 1 - 3)
                    while mask & self.bitbuf:
                        mask >>= 1
                        c += 1
                if c > 16:
                    raise LzhError("invalid LZH position code length")
                self.fillbuf(3 if c < 7 else c - 3)
                self.pt_len[i] = c
                i += 1
                if i == i_special:
                    c = self.getbits(2)
                    if i + c > n:
                        raise LzhError("invalid LZH position zero run")
                    while c > 0:
                        self.pt_len[i] = 0
                        i += 1
                        c -= 1
            while i < nn:
                self.pt_len[i] = 0
                i += 1
            self.make_table(nn, self.pt_len, 8, self.pt_table)

    def read_c_len(self):
        n = self.getbits(CBIT)
        if n > NC:
            raise LzhError("invalid LZH character table length")
        if n == 0:
            c = self.getbits(CBIT)
            if c >= NC:
                raise LzhError("invalid LZH character symbol")
            for i in range(NC):
                self.c_len[i] = 0
            for i in range(4096):
                self.c_table[i] = c
        else:
            i = 0
            while i < n:
                c = self.tree_symbol(self.pt_table[self.bitbuf >> (BITBUFSIZ - 8)], NT, 8)
                self.fillbuf(self.pt_len[c])
                if c <= 2:
                    if c == 0:
                        c = 1
                    elif c == 1:
                        c = self.getbits(4) + 3
                    else:
                        c = self.getbits(CBIT) + 20
                    if i + c > n:
                        raise LzhError("invalid LZH character zero run")
                    while c > 0:
                        self.c_len[i] = 0
                        i += 1
                        c -= 1
                else:
                    self.c_len[i] = c - 2
                    i += 1
            while i < NC:
                self.c_len[i] = 0
                i += 1
            self.make_table(NC, self.c_len, 12, self.c_table)

    def decode_c(self):
        if self.blocksize == 0:
            self.blocksize = self.getbits(16)
            if self.blocksize == 0:
                raise LzhError("empty LZH Huffman block")
            self.read_pt_len(NT, TBIT, 3)
            self.read_c_len()
            self.read_pt_len(NP, PBIT, -1)
        self.blocksize -= 1
        j = self.tree_symbol(self.c_table[self.bitbuf >> (BITBUFSIZ - 12)], NC, 12)
        self.fillbuf(self.c_len[j])
        return j

    def decode_p(self):
        j = self.tree_symbol(self.pt_table[self.bitbuf >> (BITBUFSIZ - 8)], NP, 8)
        self.fillbuf(self.pt_len[j])
        if j != 0:
            j -= 1
            j = (1 << j) + self.getbits(j)
        return j

    def decode_size(self, size):
        self.init_getbits()
        self.blocksize = 0
        self.decode_j = 0
        out = bytearray()
        while len(out) < size:
            count = min(size - len(out), DICSIZ)
            self.decode_buffer(count)
            out += self.outbuf[:count]
        return bytes(out)

    def decode_buffer(self, count):
        r = 0
        while self.decode_j > 0 and r < count:
            self.outbuf[r] = self.outbuf[self.decode_i]
            self.decode_i = (self.decode_i + 1) & (DICSIZ - 1)
            r += 1
            self.decode_j -= 1
        while r < count:
            c = self.decode_c()
            if c <= UCHAR_MAX:
                self.outbuf[r] = c
                r += 1
            else:
                self.decode_j = c - (UCHAR_MAX + 1 - THRESHOLD)
                distance = self.decode_p() + 1
                self.decode_i = (r - distance) & (DICSIZ - 1)
                while self.decode_j > 0 and r < count:
                    self.outbuf[r] = self.outbuf[self.decode_i]
                    self.decode_i = (self.decode_i + 1) & (DICSIZ - 1)
                    r += 1
                    self.decode_j -= 1


def lzh_decompress(data):
    if len(data) < 7:
        raise LzhError("data too small")
    start = -1
    for i in range(len(data) - 6):
        if data[i + 2] == 0x2D and data[i + 3] == 0x6C and data[i + 4] == 0x68 and data[i + 6] == 0x2D:
            start = i
            break
    if start < 0:
        return data  # not LHA: already raw
    if len(data) - start < 24:
        raise LzhError("truncated LZH header")
    header = data[start:]
    if header[0] < 22:
        raise LzhError("invalid LZH header size")
    if header[20] != 0:
        raise LzhError("unsupported LZH header level")
    name_end = 22 + header[21]
    if name_end + 2 > len(header):
        raise LzhError("truncated LZH filename or CRC")
    method = header[5:6]
    packed, original = struct.unpack_from("<II", header, 7)
    payload_start = start + (name_end + 2 if method == b"5" else header[0] + 2)
    if payload_start > len(data):
        raise LzhError("truncated LZH header")
    payload = data[payload_start:payload_start + min(packed, len(data) - payload_start)]
    if method == b"0":
        return payload[:original]
    return _Lzh(payload).decode_size(original)


# --------------------------------------------------------------------------
# YM5/YM6 -> per-frame register delta stream (the larcociel5 format)
# --------------------------------------------------------------------------
def ym_frames(path):
    """[(r0..r13 per 50 Hz frame)] from an LHA-wrapped YM5/YM6 file."""
    raw = lzh_decompress(open(path, "rb").read())
    if raw[:4] not in (b"YM5!", b"YM6!"):
        raise ValueError("%s: not YM5/YM6 (%r)" % (path, raw[:4]))
    if raw[4:12] != b"LeOnArD!":
        raise ValueError("%s: bad YM header" % path)
    off = 12
    nb_frame, attrib, nb_drum, clock, rate, loop_frame = struct.unpack_from(">IIHIHI", raw, off)
    off += 4 + 4 + 2 + 4 + 2 + 4
    skip = struct.unpack_from(">H", raw, off)[0]
    off += 2 + skip
    for _ in range(nb_drum):
        dsize = struct.unpack_from(">I", raw, off)[0]
        off += 4 + dsize
    for _ in range(3):  # name, author, comment
        end = raw.index(b"\x00", off)
        off = end + 1
    data = raw[off:]
    interleaved = (attrib & 1) != 0
    out = []
    if interleaved:
        for f in range(nb_frame):
            out.append([data[r * nb_frame + f] for r in range(14)])
    else:
        for f in range(nb_frame):
            out.append(list(data[f * 16:f * 16 + 14]))
    return out, rate, loop_frame


def ym_delta(path):
    frames, rate, loop = ym_frames(path)
    blob = bytearray()
    blob += struct.pack("<H", len(frames))
    for f, regs in enumerate(frames):
        if f == 0:
            mask = 0x3FFF
        else:
            prev = frames[f - 1]
            mask = 0
            for i in range(14):
                if regs[i] != prev[i]:
                    mask |= 1 << i
        blob += struct.pack("<H", mask)
        for i in range(14):
            if mask & (1 << i):
                blob += bytes([regs[i]])
    return bytes(blob), len(frames), rate, loop


# --------------------------------------------------------------------------
# palette
# --------------------------------------------------------------------------
# The UI colours live in the LAST eight slots so the scene can name them: text,
# panels and bars come from here, never from the art's own colours.
UI_SLOTS = [
    (8, 12, 27, 255),     # 248 ink
    (19, 29, 49, 255),    # 249 panel
    (235, 245, 255, 255), # 250 white
    (130, 159, 177, 255), # 251 muted
    (112, 240, 137, 255), # 252 green
    (255, 108, 177, 255), # 253 pink
    (255, 220, 106, 255), # 254 yellow
    (0, 0, 0, 255),       # 255 black
]
UI_BASE = 256 - len(UI_SLOTS)


def build_palette(sprite_colours, logo_img):
    pal = [(0, 0, 0, 0)]  # 0 is the transparent key
    for c in sorted(sprite_colours):
        if len(pal) >= UI_BASE:
            break
        pal.append((c[0], c[1], c[2], 255))
    room = UI_BASE - len(pal)
    q = logo_img.convert("RGB").quantize(colors=max(1, room), method=Image.MEDIANCUT)
    seen = set((p[0], p[1], p[2]) for p in pal)
    for px in q.convert("RGB").getdata():
        if len(pal) >= UI_BASE:
            break
        key = (px[0], px[1], px[2])
        if key in seen:
            continue
        seen.add(key)
        pal.append((key[0], key[1], key[2], 255))
    while len(pal) < UI_BASE:
        pal.append((0, 0, 0, 255))
    for c in UI_SLOTS:
        pal.append(c)
    return pal


def nearest(pal_index, colour):
    return pal_index.get((colour[0], colour[1], colour[2]), 0)


# --------------------------------------------------------------------------
def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.dirname(GEN), exist_ok=True)

    # --- art inventory ----------------------------------------------------
    manifest = json.load(open(os.path.join(SRC, "sprites.json")))
    anims = sorted(manifest.keys())

    sprite_colours = set()
    for name in anims:
        for rel in manifest[name]:
            im = Image.open(os.path.join(SRC, rel)).convert("RGBA")
            for px in im.getdata():
                if px[3] > 128:
                    sprite_colours.add((px[0], px[1], px[2]))
    tile_imgs = []
    for n in range(1, 26):
        im = Image.open(os.path.join(SRC, "tiles", "%02d.png" % n)).convert("RGBA")
        tile_imgs.append(im)
        for px in im.getdata():
            if px[3] > 128:
                sprite_colours.add((px[0], px[1], px[2]))
    logo_src = Image.open(os.path.join(SRC, "logo.png")).convert("RGBA")

    palette = build_palette(sprite_colours, logo_src)
    pal_index = {}
    for i, c in enumerate(palette):
        if i and (c[0], c[1], c[2]) not in pal_index:
            pal_index[(c[0], c[1], c[2])] = i

    def to_index(im):
        w, h = im.size
        out = bytearray(w * h)
        data = list(im.getdata())
        for i, px in enumerate(data):
            out[i] = 0 if px[3] <= 128 else nearest(pal_index, px)
        return out

    # --- sprites (native size, scene scales at blit time) -----------------
    frames = []          # (w, h, bytes)
    frame_off = []
    blob = bytearray()
    anim_table = []      # (name, first, count)
    for name in anims:
        first = len(frames)
        for rel in manifest[name]:
            im = Image.open(os.path.join(SRC, rel)).convert("RGBA")
            idx = to_index(im)
            frame_off.append((len(blob), im.size[0], im.size[1]))
            blob += idx
            frames.append(im.size)
        anim_table.append((name, first, len(manifest[name])))
    open(os.path.join(OUT, "frames.bin"), "wb").write(blob)

    # --- tiles (16x16 -> the playfield's 8x8) ----------------------------
    tiles = bytearray()
    for im in tile_imgs:
        tiles += to_index(im.resize((8, 8), Image.BOX))
    open(os.path.join(OUT, "tiles.bin"), "wb").write(tiles)

    # --- logo (450x324 -> 117x84, the Go draws it 350x252 at /3) ---------
    logo = to_index(logo_src.resize((117, 84), Image.LANCZOS))
    open(os.path.join(OUT, "logo.bin"), "wb").write(logo)

    # --- levels -----------------------------------------------------------
    levels = json.load(open(os.path.join(SRC, "levels.json")))
    KINDS = {"zenchan": 0, "monsta": 1, "mighta": 2, "pulpul": 3, "banebou": 4, "invader": 5}
    SPECIAL = {"": 0, "water": 1, "thunder": 2, "fire": 3}
    lvl_blob = bytearray()
    spawns = []
    lvl_table = []
    for lv in levels:
        rows = lv["tiles"]
        assert len(rows) == 26 and all(len(r) == 32 for r in rows)
        for r in rows:
            lvl_blob += bytes(r)
        first = len(spawns)
        for e in lv["enemies"]:
            spawns.append((KINDS[e["kind"]], e["col"], e["row"]))
        lvl_table.append(dict(
            number=lv["number"],
            player=(lv["player"]["col"], lv["player"]["row"]),
            food=(lv["food_spawn"]["col"], lv["food_spawn"]["row"]),
            power=(lv["power_spawn"]["col"], lv["power_spawn"]["row"]),
            special=SPECIAL[lv["special"]], special_count=lv["special_count"],
            first=first, count=len(lv["enemies"]),
        ))
    open(os.path.join(OUT, "levels.bin"), "wb").write(lvl_blob)

    # --- music (the five original tunes, LHA-wrapped YM5/YM6) -------------
    MUSIC = ["bubble-2", "bubble-1", "bubble-3", "bubble-4", "bubble-5"]  # menu, theme, hurry, gameover, win
    music_blob = bytearray()
    music_table = []
    for name in MUSIC:
        d, nframes, rate, loop = ym_delta(os.path.join(SRC, "audio", name + ".ym"))
        music_table.append((len(music_blob), nframes, rate, loop))
        music_blob += d
    open(os.path.join(OUT, "music.bin"), "wb").write(music_blob)

    # --- sfx (10 WAVs -> 12 kHz signed 8-bit mono) ------------------------
    SFX = ["shoot", "jump", "pop", "death", "food", "item", "fire", "water", "explosion", "laser"]
    sfx_blob = bytearray()
    sfx_table = []
    for name in SFX:
        w = wave.open(os.path.join(SRC, "audio", name + ".wav"))
        assert w.getnchannels() == 1 and w.getsampwidth() == 2
        rate = w.getframerate()
        n = w.getnframes()
        raw = struct.unpack("<%dh" % n, w.readframes(n))
        out_n = int(n * RING_RATE / rate)
        pcm = bytearray(out_n)
        for i in range(out_n):
            src = min(n - 1, int(i * rate / RING_RATE))
            v = raw[src] >> 8
            pcm[i] = v & 0xFF
        sfx_table.append((len(sfx_blob), out_n))
        sfx_blob += pcm
    open(os.path.join(OUT, "sfx.bin"), "wb").write(sfx_blob)

    # --- generated Zig tables --------------------------------------------
    def zig_str(s):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

    def ident(name):
        out = []
        for ch in name:
            out.append(ch if (ch.isalnum() or ch == "_") else "_")
        s = "".join(out)
        if s[0].isdigit():
            s = "_" + s
        return s

    with open(GEN, "w") as f:
        f.write("// --------------------------------------------------------------------------\n")
        f.write("// GENERATED by tools/bubblebobble/bb_assets.py -- do not edit.\n")
        f.write("// Frames keep the Go art's native size; the scene scales them at blit time.\n")
        f.write("// --------------------------------------------------------------------------\n")
        f.write("const zg = @import(\"zigos\");\n\n")
        f.write("pub const FRAMES_BIN = @embedFile(\"../../assets/screens/bubblebobble/frames.bin\");\n")
        f.write("pub const TILES_BIN = @embedFile(\"../../assets/screens/bubblebobble/tiles.bin\");\n")
        f.write("pub const LOGO_BIN = @embedFile(\"../../assets/screens/bubblebobble/logo.bin\");\n")
        f.write("pub const LEVEL_TILES = @embedFile(\"../../assets/screens/bubblebobble/levels.bin\");\n")
        f.write("pub const MUSIC_BIN = @embedFile(\"../../assets/screens/bubblebobble/music.bin\");\n")
        f.write("pub const SFX_BIN = @embedFile(\"../../assets/screens/bubblebobble/sfx.bin\");\n\n")
        f.write("pub const PALETTE: [256]zg.Color = .{\n")
        for i in range(256):
            r, g, b, a = palette[i] if i < len(palette) else (0, 0, 0, 0)
            if i == 0:
                a = 0
            f.write("    .{ .r = %d, .g = %d, .b = %d, .a = %d },\n" % (r, g, b, a))
        f.write("};\n\n")
        f.write("// The reserved UI slots (the generator's UI_SLOTS, palette indices 248..255).\n")
        f.write("pub const INK: u8 = 248;\npub const PANEL: u8 = 249;\npub const WHITE: u8 = 250;\n")
        f.write("pub const MUTED: u8 = 251;\npub const GREEN: u8 = 252;\npub const PINK: u8 = 253;\n")
        f.write("pub const YELLOW: u8 = 254;\npub const BLACK: u8 = 255;\n\n")

        f.write("pub const Anim = enum(u8) {\n")
        for name, _, _ in anim_table:
            f.write("    %s,\n" % ident(name))
        f.write("};\n\n")

        f.write("pub const AnimInfo = struct { name: []const u8, first: u16, count: u16 };\n")
        f.write("pub const ANIMS: [%d]AnimInfo = .{\n" % len(anim_table))
        for name, first, count in anim_table:
            f.write("    .{ .name = %s, .first = %d, .count = %d },\n" % (zig_str(name), first, count))
        f.write("};\n\n")

        f.write("pub const Frame = struct { off: u32, w: u8, h: u8 };\n")
        f.write("pub const FRAMES: [%d]Frame = .{\n" % len(frame_off))
        for off, w, h in frame_off:
            f.write("    .{ .off = %d, .w = %d, .h = %d },\n" % (off, w, h))
        f.write("};\n\n")

        f.write("pub const TILE: u16 = 8;\n")
        f.write("pub const COLUMNS: u16 = 32;\n")
        f.write("pub const ROWS: u16 = 26;\n")
        f.write("pub const PLAY_W: u16 = 256;\n")
        f.write("pub const PLAY_H: u16 = 208;\n")
        f.write("pub const LOGO_W: u16 = 117;\n")
        f.write("pub const LOGO_H: u16 = 84;\n\n")

        f.write("pub const MusicInfo = struct { off: u32, frames: u16, rate: u16, loop: u16 };\n")
        f.write("pub const MUSIC: [%d]MusicInfo = .{\n" % len(music_table))
        for off, nf, rate, loop in music_table:
            f.write("    .{ .off = %d, .frames = %d, .rate = %d, .loop = %d },\n" % (off, nf, rate, loop))
        f.write("};\n\n")

        f.write("pub const SfxInfo = struct { off: u32, len: u32 };\n")
        f.write("pub const SFX: [%d]SfxInfo = .{\n" % len(sfx_table))
        for off, ln in sfx_table:
            f.write("    .{ .off = %d, .len = %d },\n" % (off, ln))
        f.write("};\n\n")

        f.write("pub const Spawn = struct { kind: u8, col: u8, row: u8 };\n")
        f.write("pub const SPAWNS: [%d]Spawn = .{\n" % len(spawns))
        for kind, col, row in spawns:
            f.write("    .{ .kind = %d, .col = %d, .row = %d },\n" % (kind, col, row))
        f.write("};\n\n")

        f.write("pub const LevelInfo = struct {\n")
        f.write("    number: u8,\n    player: [2]u8,\n    food: [2]u8,\n    power: [2]u8,\n")
        f.write("    special: u8,\n    special_count: u8,\n    first: u16,\n    count: u16,\n};\n")
        f.write("pub const LEVELS: [%d]LevelInfo = .{\n" % len(lvl_table))
        for L in lvl_table:
            f.write("    .{ .number = %d, .player = .{%d,%d}, .food = .{%d,%d}, .power = .{%d,%d}, .special = %d, .special_count = %d, .first = %d, .count = %d },\n"
                    % (L["number"], L["player"][0], L["player"][1], L["food"][0], L["food"][1],
                       L["power"][0], L["power"][1], L["special"], L["special_count"], L["first"], L["count"]))
        f.write("};\n")

    print("palette %d entries (%d sprite/tile + logo)" % (len(palette), len(sprite_colours)))
    print("frames %d %d bytes   tiles %d   logo %d   levels %d   music %d   sfx %d"
          % (len(frames), len(blob), len(tiles), len(logo), len(lvl_blob), len(music_blob), len(sfx_blob)))
    for i, (off, nf, rate, loop) in enumerate(music_table):
        print("  music %d: %5d frames @ %d Hz loop=%d  (%d bytes)" % (i, nf, rate, loop, len(music_blob)))


if __name__ == "__main__":
    main()
