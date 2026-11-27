"""Kestrel Racing M7: the track pack builder (tools/racer/trackpack.py) and its Python twins of the cart's file rules
(twin_trk.py: trk.parse + the library's caps; twin_files.py: carfile.parse, panofile.parse + clash). The twins' constants are
read back from the Zig, every committed file passes, and each corruption is refused with the cart's own error name."""

from __future__ import annotations

import ast
import contextlib
import io
import operator
import re
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from racer import carc, kit, ktrk, panc, trackpack
from racer import twin_files as tf
from racer import twin_trk as tt
from racer.kcar_export import loads

ROOT = Path(__file__).resolve().parents[2]
ZIG = ROOT / "apps/zig/scenes/racer"
ASSETS = ROOT / "apps/zig/assets/screens/racer"
SAMPLE = kit.convert(ktrk.loads((ROOT / "tools/racer/tracks/sample_oval.ktrk.json").read_text()))


def _arith(node: ast.expr) -> int:
    """An integer expression of literals and + * << only (what the Zig constants use): nothing is executed."""
    if isinstance(node, ast.Constant) and isinstance(node.value, int):
        return node.value
    ops = {ast.Add: operator.add, ast.Mult: operator.mul, ast.LShift: operator.lshift}
    if isinstance(node, ast.BinOp) and type(node.op) in ops:
        return ops[type(node.op)](_arith(node.left), _arith(node.right))
    raise ValueError(f"not a constant expression: {ast.dump(node)}")


def zig_const(file: str, name: str) -> int:
    m = re.search(rf"pub const {name}(?:: \w+)? = ([^;]+);", (ZIG / file).read_text())
    assert m, (file, name)
    return _arith(ast.parse(m.group(1).replace("_", ""), mode="eval").body)


def reason(fn: object, *args: object) -> str:
    try:
        fn(*args)  # type: ignore[operator]  # [operator] a twin's check
    except tt.Refused as e:
        return e.why
    return "accepted"


def recrc(b: bytearray, at: int, start: int) -> bytes:
    b[at:at + 4] = zlib.crc32(b[start:]).to_bytes(4, "little")
    return bytes(b)


def gt() -> bytes:
    return carc.convert(loads((ROOT / "tools/racer/cars/gt.kcar.json").read_text()), scale=2.0)


def pan_for(track: bytes) -> bytes:
    rows, px, pal, hz = panc.test_strip()
    return panc.encode(256, rows, px, pal, hz, panc.free_entries(track, len(pal) - 1), colours=len(pal) - 1)


class TwinTest(unittest.TestCase):
    def test_the_twins_constants_are_the_carts(self) -> None:
        for file, name, mine in (("trk.zig", "MAGIC", tt.MAGIC), ("trk.zig", "VERSION", tt.VERSION), ("trk.zig", "MAX_RAMPS", tt.MAX_RAMPS),
                                 ("trk.zig", "MAX_SEG", tt.MAX_SEG), ("trk.zig", "MAX_GRID", tt.MAX_GRID), ("trk.zig", "MAX_RBAKE", tt.MAX_RBAKE),
                                 ("trk.zig", "MOOD_SIZE", tt.MOOD_SIZE), ("library.zig", "MAX_FILE", tt.MAX_FILE),
                                 ("library.zig", "MAX_VERTS", tt.MAX_VERTS), ("library.zig", "MAX_FACES", tt.MAX_FACES),
                                 ("library.zig", "MAX", trackpack.MAX_TRACKS + 1), ("carfile.zig", "MAX_MODELS", tf.MAX_MODELS),
                                 ("carfile.zig", "MAX_FILE", tf.CAR_FILE), ("carfile.zig", "MAX_SHADOW", tf.MAX_SHADOW),
                                 ("panofile.zig", "MAX_ROWS", tf.MAX_ROWS), ("panofile.zig", "MAX_LOWER", tf.MAX_LOWER),
                                 ("panofile.zig", "MAX_COLOURS", tf.MAX_COLOURS), ("panofile.zig", "MAGIC", tf.KPAN)):
            with self.subTest(name):
                self.assertEqual(zig_const(file, name), mine)

    def test_every_committed_track_the_sample_the_gt_a_set_and_a_panorama_pass(self) -> None:
        for n in ("oval", "city", "salt", "neon", "glacier"):
            self.assertEqual(reason(tt.check, (ASSETS / f"{n}.ktrk").read_bytes()), "accepted", n)
        self.assertEqual(reason(tt.check, SAMPLE), "accepted")
        self.assertEqual(reason(tf.car, (ASSETS / "gt.kcar").read_bytes()), "accepted")
        self.assertEqual(reason(tf.car, carc.pack_set([gt(), gt()], [(9, 9, 9)] * 7)), "accepted")
        self.assertEqual(reason(tf.pan, pan_for(SAMPLE), SAMPLE), "accepted")

    def test_a_corrupted_track_is_refused_with_the_carts_reason(self) -> None:
        mood_at = int.from_bytes(SAMPLE[100:104], "little")
        cases = {"Truncated": SAMPLE[:-4], "BadMagic": b"XXXX" + SAMPLE[4:], "BadCrc": SAMPLE[:-1] + b"\x00",
                 "BadBlock": SAMPLE[:36] + struct.pack("<I", 31) + SAMPLE[40:]}
        for at, v in ((mood_at + 26, 2), (mood_at + 3, 3), (mood_at + 31, 0)):  # draw_r 2, backdrop 3, a haze with no strength
            b = bytearray(SAMPLE)
            b[at] = v
            cases.setdefault("BadMood", recrc(b, 8, 128))
            self.assertEqual(reason(tt.check, recrc(b, 8, 128)), "BadMood", at - mood_at)
        for why, blob in cases.items():
            self.assertEqual(reason(tt.check, blob), why)
        self.assertIsNone(tt.raw_len(b"not a track\r\n", 13))
        self.assertEqual(tt.raw_len(SAMPLE[:512], len(SAMPLE)), len(SAMPLE))

    def test_a_corrupted_car_or_panorama_is_refused_with_the_carts_reason(self) -> None:
        g = gt()
        self.assertEqual(reason(tf.car, g[:-8]), "Truncated")
        self.assertEqual(reason(tf.car, g[:100] + bytes([g[100] ^ 1]) + g[101:]), "BadCrc")
        self.assertEqual(reason(tf.car, g + bytes(tf.CAR_FILE)), "TooBig")
        self.assertEqual(reason(tf.car, g[:4] + struct.pack("<I", 3) + g[8:]), "BadVersion")
        p = bytearray(pan_for(SAMPLE))
        p[-1] = 255  # a texel off the strip's entries
        self.assertEqual(reason(tf.pan, recrc(p, 12, 32)), "BadTexel")
        salt = (ASSETS / "salt.ktrk").read_bytes()
        used = next(f[6] for f in tt.FACE.iter_unpack(salt[int.from_bytes(salt[56:60], "little"):][:32 * 4]))
        q = bytearray(pan_for(SAMPLE))
        q[25] = used  # the strip's first entry on a colour a Salt Flats face uses
        q[32 + 4 * q[24]:] = bytes([used] * (len(q) - 32 - 4 * q[24]))
        self.assertEqual(reason(tf.pan, recrc(q, 12, 32), salt), "Clash")


class PackTest(unittest.TestCase):
    def files(self, tmp: Path, blobs: dict[str, bytes]) -> Path:
        d = tmp / "in"
        d.mkdir(exist_ok=True)
        for name, b in blobs.items():
            (d / name).write_bytes(b)
        return d

    def test_an_hd_pack_lands_in_hd_racer_as_given(self) -> None:
        with tempfile.TemporaryDirectory() as t:
            d = self.files(Path(t), {"SAMPLE.KTR": SAMPLE, "CAR.KCR": gt()})
            with contextlib.redirect_stdout(io.StringIO()) as said:
                self.assertEqual(trackpack.main([str(d), "--hd", str(Path(t) / "sd")]), 0)
            self.assertIn("CAR.KCR SAMPLE.KTR", said.getvalue())
            self.assertEqual((Path(t) / "sd/HD/RACER/SAMPLE.KTR").read_bytes(), SAMPLE)

    def test_a_zmd_pack_carries_the_cart_and_lists_the_files(self) -> None:
        if not trackpack.CART.is_file():
            self.skipTest("no site/carts/demo-racer.wasm")
        with tempfile.TemporaryDirectory() as t:
            d = self.files(Path(t), {"SAMPLE.KTR": SAMPLE, "SAMPLE.PAN": pan_for(SAMPLE)})
            out = trackpack.write_zmd(trackpack.collect([d]), Path(t) / "p.zmd", "PACK")
            img = out.read_bytes()
            n = struct.unpack_from("<H", img, 0x2E4)[0]
            names = [img[0x300 + 32 * i:0x310 + 32 * i].rstrip(b"\0").decode() for i in range(n)]
            self.assertEqual(names, ["BOOT.WSM", "SAMPLE.KTR", "SAMPLE.PAN"])

    def test_the_pack_rules_refuse_by_name(self) -> None:
        cases = [({"SAMPLE.PAN": pan_for(SAMPLE)}, "no .KTR in the pack"), ({"SAMPLE.KTR": SAMPLE[:-1] + b"\0"}, "BadCrc"),
                 ({"TOOLONGNAME.KTR": SAMPLE}, "not an 8.3 name"), ({"NOTES.KTR": b"not a track\r\n"}, "not_track"),
                 ({"A.KTR": SAMPLE, "B.PAN": pan_for(SAMPLE)}, "no B.KTR")]
        for blobs, want in cases:
            with self.subTest(want), tempfile.TemporaryDirectory() as t, self.assertRaisesRegex(trackpack.PackError, want):
                trackpack.check(trackpack.collect([self.files(Path(t), blobs)]))

    def test_a_panorama_in_an_hd_pack_is_refused_and_too_many_tracks_are(self) -> None:
        with tempfile.TemporaryDirectory() as t:
            items = trackpack.collect([self.files(Path(t), {"SAMPLE.KTR": SAMPLE, "SAMPLE.PAN": pan_for(SAMPLE)})])
            with self.assertRaisesRegex(trackpack.PackError, "own disk only"):
                trackpack.check(items, hd=True)
            many = [trackpack.Item(f"T{k}.KTR", Path("x"), SAMPLE, SAMPLE) for k in range(16)]
            with self.assertRaisesRegex(trackpack.PackError, "16 tracks"):
                trackpack.check(many)

    def test_a_car_file_for_no_track_here_is_a_warning(self) -> None:
        items = [trackpack.Item("SAMPLE.KTR", Path("x"), SAMPLE, SAMPLE), trackpack.Item("CITY.KCR", Path("y"), gt(), gt())]
        self.assertEqual(len(trackpack.check(items)), 1)


if __name__ == "__main__":
    unittest.main()
