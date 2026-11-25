"""The Aurora boot baker (tools/boot/): settings, photo, palette, packing, falcon, sound and a tiny end-to-end bake.

Needs numpy + pillow: the gate runs it as `uv run --with numpy --with pillow python -m unittest tools.tests.test_aurora_bake`.
Plain `unittest discover` (system python, no numpy) skips the module loudly instead of failing.
"""
import json
import sys
import tempfile
import unittest
import wave
from pathlib import Path

try:
    import numpy as np
except ImportError as e:  # the bake gate line installs it; discovery without it must not turn red
    raise unittest.SkipTest(f"tools/tests/test_aurora_bake.py skipped: {e} (run it through uv, see the gate line)") from e

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "boot"))
import aurora_bake as bake  # noqa: E402
import aurora_common as common  # noqa: E402
import aurora_falcon as falcon  # noqa: E402
import aurora_pack as pack  # noqa: E402
import aurora_palette as palette  # noqa: E402
import aurora_photo as photo  # noqa: E402
import aurora_sound as sound  # noqa: E402

SETTINGS = ROOT / "tools/boot/aurora_settings.json"
PHOTO = ROOT / "apps/zig/assets/screens/aurora_boot/stars2.jpg"
WAV = ROOT / "apps/zig/assets/screens/aurora_boot/boot_northern_lights_8s5.wav"
ZX0PACK = ROOT / "zig-out/bin/zx0pack"


class SettingsTest(unittest.TestCase):
    def test_load_merges_the_named_preset_colours(self):
        p = common.load_settings(SETTINGS)
        self.assertEqual(p["c1"], (0.2, 0.9, 0.85))
        self.assertEqual(p["steps"], 51)

    def test_missing_key_is_refused_not_defaulted(self):
        with tempfile.TemporaryDirectory() as d:
            bad = json.loads(SETTINGS.read_text())
            del bad["gain"]
            Path(d, "s.json").write_text(json.dumps(bad))
            with self.assertRaisesRegex(common.SettingsError, "gain"):
                common.load_settings(Path(d, "s.json"))

    def test_unknown_preset_and_missing_file_are_refused(self):
        with tempfile.TemporaryDirectory() as d:
            bad = json.loads(SETTINGS.read_text()) | {"preset": "Neon"}
            Path(d, "s.json").write_text(json.dumps(bad))
            with self.assertRaisesRegex(common.SettingsError, "Neon"):
                common.load_settings(Path(d, "s.json"))
            with self.assertRaises(common.SettingsError):
                common.load_settings(Path(d, "nope.json"))

    def test_beats_follow_the_settings_timeline(self):
        b = common.beats(common.load_settings(SETTINGS))
        self.assertEqual((b.a0, b.a1, b.m0), (1.0, 6.0, 1.7))
        self.assertAlmostEqual(b.end, 7.85)
        self.assertAlmostEqual(b.total, 8.45)


class PhotoTest(unittest.TestCase):
    def test_missing_photo_is_a_photo_error(self):
        with self.assertRaises(photo.PhotoError):
            photo.resize_cover("/nonexistent/sky.jpg")

    def test_extraction_finds_the_stars_and_paints_them_out(self):
        rgb = photo.resize_cover(PHOTO)
        stars, cleaned = photo.extract(rgb, 0.10)
        self.assertEqual(rgb.shape, (200, 320, 3))
        self.assertEqual(len(stars), 237)  # the lab's JSON says 254 with the browser's resampler
        x, y, _, _ = stars[0]
        self.assertTrue((cleaned[y - 1:y + 2, x - 1:x + 2] == cleaned[y, x]).all())
        self.assertGreater(len(stars), len(photo.extract(cleaned, 0.10)[0]))


class PaletteTest(unittest.TestCase):
    def test_few_colours_are_kept_exactly_and_zero_stays_zero(self):
        keys = np.array([0, 1, 33, 1, 33, 2049, 0], dtype=np.uint16)
        uniq, counts = palette.histogram(keys)
        pal = palette.build(uniq, counts, 256)
        idx = palette.quantise(keys, uniq, pal)
        self.assertTrue((pal[idx] == palette.unpack(keys)).all())
        self.assertEqual(tuple(pal[0]), (0, 0, 0))
        self.assertEqual(idx[0], 0)

    def test_palette_never_exceeds_256_and_error_is_a_few_levels(self):
        rng = np.random.default_rng(3)
        keys = (rng.integers(0, 24, 5000) | (rng.integers(0, 48, 5000) << 5) | (rng.integers(0, 24, 5000) << 11)).astype(np.uint16)
        uniq, counts = palette.histogram(keys)
        pal = palette.build(uniq, counts, 256)
        self.assertLessEqual(len(pal), 256)
        _, worst = palette.error(uniq, counts, pal, palette._nearest(palette.unpack(uniq).astype(float), pal.astype(float)))
        self.assertLessEqual(worst.max(), 6)

    def test_bad_sizes_and_empty_input_are_refused(self):
        uniq, counts = palette.histogram(np.array([5, 9], dtype=np.uint16))
        with self.assertRaises(palette.PaletteError):
            palette.build(uniq, counts, 300)
        with self.assertRaises(palette.PaletteError):
            palette.build(*palette.histogram(np.zeros(4, dtype=np.uint16)), size=16)


class PackTest(unittest.TestCase):
    def setUp(self):
        self.pal = np.array([[0, 0, 0], [1, 1, 1], [2, 2, 2], [10, 20, 10]], dtype=np.int16)

    def test_hysteresis_error_is_bounded_and_the_last_frame_exact(self):
        idx = np.array([[[1]], [[2]], [[3]], [[0]]], dtype=np.uint8)
        held = pack.hysteresis(idx, self.pal, 2)
        err = np.abs(self.pal[held] - self.pal[idx]).max()
        self.assertLessEqual(err, 2)
        self.assertEqual(int(held[-1, 0, 0]), 0)

    def test_deltas_round_trip_mod_256(self):
        idx = np.array([[[0, 200]], [[255, 3]], [[1, 0]]], dtype=np.uint8)
        self.assertTrue((pack.undelta(pack.deltas(idx)) == idx).all())

    def test_entries_that_would_overflow_are_replaced_by_one_that_fits(self):
        idx = np.array([[[3, 3]]], dtype=np.uint8)  # entry 3 adds (10, 20, 10)
        room = np.array([[[31, 63, 31], [5, 5, 5]]])
        n = pack.fit_headroom(idx, self.pal, room)
        self.assertEqual(n, 1)
        self.assertTrue((self.pal[idx] <= room[None]).all())
        self.assertEqual(int(idx[0, 0, 0]), 3)

    def test_band_of_an_empty_aurora_is_refused(self):
        with self.assertRaises(pack.PackError):
            pack.band_rows(np.zeros((2, 8, 8), dtype=np.uint16))

    def test_missing_packer_is_a_clear_error(self):
        with tempfile.TemporaryDirectory() as d, self.assertRaisesRegex(pack.PackError, "zx0pack not found"):
            pack.zx0(b"abc", "/nonexistent/zx0pack", d)


class FalconTest(unittest.TestCase):
    def test_every_star_gets_its_own_dot_and_a_delay(self):
        p = common.load_settings(SETTINGS)
        stars = [(10 + 3 * i, 20 + (7 * i) % 150, 0.5, 0.0) for i in range(60)]
        _, dot_of, delay = falcon.assign(stars, p)
        self.assertEqual(sorted(dot_of), list(range(60)))
        self.assertTrue(all(0 <= d <= 0.35 for d in delay))

    def test_the_model_has_its_vertices_and_projects_inside_the_screen_at_hold(self):
        p = common.load_settings(SETTINGS)
        self.assertEqual(len(falcon.NAMES), 42)
        proj = falcon.projected(common.beats(p).m1, p, common.beats(p))
        self.assertTrue(((proj[:, 0] > -20) & (proj[:, 0] < 340)).all())


class SoundTest(unittest.TestCase):
    def test_conversion_is_8_bit_mono_trimmed_and_deterministic(self):
        a, rate = sound.convert(WAV, 8.4667)
        b, _ = sound.convert(WAV, 8.4667)
        self.assertEqual(a.dtype, np.int8)
        self.assertEqual(len(a), round(8.4667 * rate))
        self.assertTrue((a == b).all())
        self.assertGreater(int(np.abs(a.astype(int)).max()), 100)
        self.assertLess(abs(int(a[-1])), 3)  # the closing ramp

    def test_missing_wrong_depth_and_too_short_sounds_are_refused(self):
        with self.assertRaises(sound.SoundError):
            sound.convert("/nonexistent.wav", 1.0)
        with self.assertRaisesRegex(sound.SoundError, "needs"):
            sound.convert(WAV, 30.0)
        with tempfile.TemporaryDirectory() as d:
            p = Path(d, "eight.wav")
            with wave.open(str(p), "wb") as w:
                w.setnchannels(1); w.setsampwidth(1); w.setframerate(8000); w.writeframes(b"\x80" * 100)
            with self.assertRaisesRegex(sound.SoundError, "16-bit"):
                sound.read_wav(p)


@unittest.skipUnless(ZX0PACK.exists(), f"{ZX0PACK} not built (zig build installs it): the end-to-end bake is skipped")
class BakeTest(unittest.TestCase):
    def test_two_frame_bake_is_deterministic_and_complete(self):
        outs = []
        for _ in range(2):
            d = tempfile.mkdtemp()
            bake.bake(SETTINGS, PHOTO, d, ZX0PACK, frames=2, sound=WAV)
            outs.append({f.name: f.read_bytes() for f in Path(d).iterdir()})
        self.assertEqual(outs[0], outs[1])
        self.assertEqual(sorted(outs[0]), ["aurora.idx", "aurora.zx0", "aurora_meta.zig", "aurora_ref.json", "boot.raw", "sky.zx0", "stars.zx0"])
        self.assertIn(b"pub const N_STARS: u32 = 237;", outs[0]["aurora_meta.zig"])
        self.assertEqual(len(outs[0]["boot.raw"]), json.loads(outs[0]["aurora_ref.json"])["sizes"]["sound"])


if __name__ == "__main__":
    unittest.main()
