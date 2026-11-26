"""LOCAL ONLY: reads freds72's PICO-8 data carts (the Virtua Racing tracks and models) into Python objects.

This file holds NO data: it is the decoder of the layout the engine's own `unpack_*` functions read (vracing_main.p8,
MIT, freds72). The carts it reads are derived from Sega's Mega Drive game: keep them, and everything this decodes,
out of the repository (the importer writes under a git-ignored directory; see tools/racer/vr_import.py).

A cart's data lives in the PICO-8 memory image 0x0000..0x42FF (gfx, map, flags, music, sfx), read as one byte stream
that moves on to the next cart at 0x4300 (`mpeek`).
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Callable

MEM = 0x4300
SFX_LINES = 64
SFX_BYTES = 68


def _hex_bytes(line: str) -> list[int]:
    return [int(line[i:i + 2], 16) for i in range(0, len(line) - 1, 2)]


def _sections(text: str) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    cur: list[str] | None = None
    for ln in text.splitlines():
        if ln.startswith("__") and ln.endswith("__"):
            cur = out.setdefault(ln.strip("_"), [])
        elif cur is not None:
            cur.append(ln.strip())
    return out


def _sfx(line: str) -> list[int]:
    head = _hex_bytes(line[:8])
    notes = []
    for k in range(32):
        s = line[8 + 5 * k:13 + 5 * k]
        pitch, wave, vol, fx = int(s[0:2], 16), int(s[2], 16), int(s[3], 16), int(s[4], 16)
        w = pitch | ((wave & 7) << 6) | (vol << 9) | (fx << 12) | ((wave >> 3) << 15)
        notes += [w & 255, w >> 8]
    return notes + head


def load_memory(path: Path) -> bytes:
    """The 0x4300 bytes `reload(0, 0, 0x4300, file)` copies in."""
    sec = _sections(path.read_text())
    mem = bytearray(MEM)
    gfx = sec.get("gfx", [])
    for y, ln in enumerate(gfx[:128]):
        for x in range(64):
            mem[y * 64 + x] = int(ln[2 * x + 1], 16) << 4 | int(ln[2 * x], 16)
    for y, ln in enumerate(sec.get("map", [])[:32]):
        mem[0x2000 + y * 128:0x2000 + (y + 1) * 128] = bytes(_hex_bytes(ln))
    flags = [b for ln in sec.get("gff", []) for b in _hex_bytes(ln)]
    mem[0x3000:0x3000 + len(flags)] = bytes(flags[:256])
    for p, ln in enumerate(sec.get("music", [])[:64]):
        flag = int(ln[:2], 16)
        chans = _hex_bytes(ln[3:11])
        for c in range(4):
            mem[0x3100 + p * 4 + c] = chans[c] | (((flag >> c) & 1) << 7)
    for s, ln in enumerate(sec.get("sfx", [])[:SFX_LINES]):
        mem[0x3200 + s * SFX_BYTES:0x3200 + (s + 1) * SFX_BYTES] = bytes(_sfx(ln))
    return bytes(mem)


class Stream:
    """`mpeek` and the `unpack_*` readers of vracing_main.p8."""

    def __init__(self, folder: Path) -> None:
        self.folder = folder
        self.cart_id = 0
        self.mem = 0
        self.data = load_memory(folder / "vracing_0.p8")

    def load(self, cart_id: int, mem: int) -> None:
        self.cart_id, self.mem = cart_id, mem
        self.data = load_memory(self.folder / f"vracing_{cart_id}.p8")

    def peek(self) -> int:
        if self.mem == MEM:
            self.load(self.cart_id + 1, 0)
        v = self.data[self.mem]
        self.mem += 1
        return v

    def int_(self, w: int = 1) -> int:
        return self.peek() if w == 1 else (self.peek() << 8) | self.peek()

    def variant(self) -> int:
        h = self.peek()
        return ((h & 0x7F) << 8) | self.peek() if h & 0x80 else h

    def double(self) -> float:
        return (self.int_(2) - 16384) / 128

    def array(self, fn: Callable[[int], Any]) -> list[Any]:
        return [fn(i) for i in range(self.variant())]

    def vec(self, scale: float = 1.0) -> list[float]:
        return [self.double() * scale for _ in range(3)]

    def string(self) -> str:
        itoa = "_0123456789abcdefghijklmnopqrstuvwxyz"
        return "".join(itoa[c - 1] for c in self.array(lambda _: self.int_()))

    def face(self, verts: list[list[float]]) -> dict[str, Any]:
        flags, c = self.int_(), self.int_()
        ni = 4 if flags & 2 else 3
        return {"flags": flags, "c": c, "v": [self.variant() - 1 for _ in range(ni)]}  # Lua tables are 1-based

    def model(self, scale: float) -> dict[str, Any]:
        """Vertices, faces (inner faces and border edges as the track format has them)."""
        verts = self.array(lambda _: self.vec(scale))
        faces = []

        def one(_: int) -> None:
            f = self.face(verts)
            if f["flags"] & 8:
                f["inner"] = self.array(lambda _i: self.face(verts))
            n = (f["flags"] >> 5) & 7
            if n:
                bi = self.int_()
                f["borders"] = [(bi >> (4 * i)) & 0xF for i in range(n)]
            faces.append(f)

        self.array(one)
        return {"verts": verts, "faces": faces}


def read_models(folder: Path, s: Stream | None = None) -> dict[str, Any]:
    """The car models of vracing_0 (vertices in units; the models' scale is 1/32 of the track's). Leaves `s` at the track directory."""
    s = s or Stream(folder)
    s.load(0, 0)
    out: dict[str, Any] = {}

    def one(_: int) -> None:
        name = s.string()
        s.int_()  # the stored scale, overridden to 1/32 by the engine
        dists = s.array(lambda _i: s.double())
        lods = []

        def lod(_i: int) -> None:
            m = s.model(1 / 32)

            def group(_g: int) -> None:
                gname = s.string()
                off = s.vec(1 / 32)
                fs = s.array(lambda _f: (s.face(m["verts"]), s.vec()))
                m.setdefault("groups", {})[gname] = {"offset": off, "faces": [{**f, "n": n} for f, n in fs]}

            s.array(group)
            lods.append(m)

        s.array(lod)
        out[name] = {"lod_dist": dists, "lods": lods}

    s.array(one)
    out["_end"] = {"cart": s.cart_id, "mem": s.mem}
    return out


def read_track(folder: Path, track_id: int) -> dict[str, Any]:
    """`unpack_track(track_id)`: needs the models read first (the track directory follows them)."""
    s = Stream(folder)
    read_models(folder, s)
    s.mem += track_id * 3
    cart, mem = s.int_(), s.int_(2)
    s.load(cart, mem)
    tid, colors = s.int_(), s.int_()
    t: dict[str, Any] = {"id": tid, "ground_color": colors & 0xF, "sky_color": (colors & 0xF0) >> 4, "start_pos": s.vec()}
    t.update(s.model(1.0))
    voxels = {}
    s.array(lambda _: voxels.__setitem__(s.variant(), s.array(lambda _f: s.variant())))
    t["voxels"] = {str(k): v for k, v in voxels.items()}
    pairs = s.array(lambda _: (s.variant() - 1, s.variant() - 1))
    t["segments"] = [list(p) for p in pairs]
    t["checkpoints"] = s.array(lambda _: s.variant())
    return t
