"""The Aurora boot baker (tools/boot/): settings, photo, packing, falcon, sound and a tiny end-to-end bake.

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
import aurora_photo as photo  # noqa: E402
import aurora_sound as sound  # noqa: E402

SETTINGS = ROOT / "tools/boot/aurora_settings.json"
PHOTO = ROOT / "apps/zig/assets/screens/aurora_boot/stars2.jpg"
WAV = ROOT / "apps/zig/assets/screens/aurora_boot/boot_northern_lights_8s5.wav"
ZX0PACK = ROOT / "zig-out/bin/zx0pack"
FONT = bake.FONT  # local only (never committed): without it the end-to-end bake is skipped


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
        self.assertEqual(len(stars), 214)  # 237 over the whole height; the lab's JSON says 254 with the browser's resampler
        x, y, _, _ = stars[0]
        self.assertGreater(int(rgb[y, x].max()), int(cleaned[y, x].max()))  # the star's own pixel is no longer the peak
        self.assertGreater(len(stars), len(photo.extract(cleaned, 0.10)[0]))


class StarBandTest(unittest.TestCase):
    def _sky(self):
        yy, xx = np.mgrid[0:200, 0:320]
        base = (20 + yy * 0.8 + xx * 0.4)[..., None] * np.array([1.0, 1.2, 1.0])
        img = np.clip(base, 0, 255)
        for x, y in ((50, 30), (100, 120), (60, 150)):
            img[y, x] = 250
        return img.astype(np.uint8)

    def test_no_star_is_found_below_the_band(self):
        stars, _ = photo.extract(self._sky(), 0.10, band=(0.0, 70.0))
        self.assertEqual(sorted((x, y) for x, y, _, _ in stars), [(50, 30), (100, 120)])  # row 150 is 75 %
        self.assertTrue(all(y < 140 for _, y, _, _ in stars))
        low, _ = photo.extract(self._sky(), 0.10, band=(0.0, 100.0))
        self.assertIn((60, 150), [(x, y) for x, y, _, _ in low])  # it IS a detectable star: only the band excluded it

    def test_a_band_that_starts_lower_skips_the_top(self):
        stars, _ = photo.extract(self._sky(), 0.10, band=(30.0, 100.0))
        self.assertEqual(sorted((x, y) for x, y, _, _ in stars), [(60, 150), (100, 120)])

    def test_painting_a_star_out_of_a_gradient_leaves_no_flat_block_and_no_star(self):
        img = self._sky()
        _, cleaned = photo.extract(img, 0.10)
        block = cleaned[29:32, 49:52, 1].astype(int)
        self.assertGreater(len(set(block.ravel().tolist())), 3)  # a gradient, not one flat value
        ref = np.asarray(self._sky(), dtype=int)
        ref[30, 50] = ref[30, 49]
        self.assertLessEqual(np.abs(cleaned[29:32, 49:52].astype(int) - ref[29:32, 49:52]).max(), 4)
        self.assertLess(int(cleaned[30, 50, 1]), 100)  # the 250 spike is gone


class PackTest(unittest.TestCase):
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


class FontTest(unittest.TestCase):
    def test_a_missing_font_is_refused_before_any_rendering(self):
        with tempfile.TemporaryDirectory() as d, self.assertRaisesRegex(bake.WordError, "font not found"):
            bake.bake(SETTINGS, PHOTO, d, ZX0PACK, frames=2, sound=WAV, font=Path(d, "none.otf"))


@unittest.skipUnless(ZX0PACK.exists() and FONT.exists(), f"{ZX0PACK} (zig build) or the local font {FONT}: the end-to-end bake is skipped")
class BakeTest(unittest.TestCase):
    def test_two_frame_bake_is_deterministic_and_complete(self):
        outs = []
        for _ in range(2):
            d = tempfile.mkdtemp()
            bake.bake(SETTINGS, PHOTO, d, ZX0PACK, frames=2, sound=WAV)
            outs.append({f.name: f.read_bytes() for f in Path(d).iterdir()})
        self.assertEqual(outs[0], outs[1])
        self.assertEqual(sorted(outs[0]), ["aurora.idx", "aurora.msk", "aurora_meta.zig", "aurora_ref.json", "boot.raw", "overlay.bin",
                                           "sky.zx0", "word.bin"])
        self.assertIn(b"pub const N_STARS: u32 = 214;", outs[0]["aurora_meta.zig"])
        self.assertIn(b"pub const AURORA_FRAMES: u32 = 3;", outs[0]["aurora_meta.zig"])
        ref = json.loads(outs[0]["aurora_ref.json"])
        self.assertEqual(len(outs[0]["boot.raw"]), ref["sizes"]["sound"])
        self.assertEqual(sorted(ref["overlay_md5"]), sorted(str(f) for f in bake.aset.OVERLAY_PROBES))


if __name__ == "__main__":
    unittest.main()
