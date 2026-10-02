"""The plane mixer's oracle (tools/video_dump/vmix.c) against the browser itself:
headless Chrome composes the same canvases (tools/mix_chrome.mjs) and its
screenshot must equal vmix's picture byte for byte. Opt-in (ZM_CHROME=1): it
needs Chrome and playwright, and starts a browser per check.
"""

import os
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
sys.path.insert(0, str(FPGA / "tests"))
import video_mix
from test_rtl_video import _source

pytestmark = pytest.mark.skipif(
    os.environ.get("ZM_CHROME") != "1", reason="set ZM_CHROME=1 to check the browser model against headless Chrome"
)


@pytest.mark.parametrize("key", ["union_main", "gen4_3615", "dhs_0pxl0reg", "s:alpha", "s:bgalpha", "s:worst"])
def test_browser_model_is_chromes_picture_of_a_recorded_frame(key: str) -> None:
    frames_dir, frames, _ = _source(key)
    for f in frames:
        assert video_mix.chrome_check_frame(frames_dir, f) == 0


@pytest.mark.parametrize(("seed", "mask"), [(1, 15), (2, 5), (3, 10), (4, 1)])
def test_browser_model_is_chromes_picture_of_random_canvases(seed: int, mask: int) -> None:
    assert video_mix.chrome_check_random(FPGA / "build" / "vdump" / "_mixrand", seed, mask) == 0
