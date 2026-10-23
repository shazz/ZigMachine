"""The tube reaches zm_video_out's TUBE parameter: black, the board's and the browser's alike
(soc/zm_video_pipe.py; the RTL side is tests/test_rtl_video_tube.py). Elaborates
ZMVideo only, with a platform that takes no sources: no toolchain."""

import inspect
from pathlib import Path

from migen import Instance

from soc import zigmachine_soc
from soc.zm_video_pipe import TUBE_BOARD, TUBE_BROWSER, ZMVideo


class _Platform:
    def add_source(self, *_: object) -> None: ...

    def add_verilog_include_path(self, *_: object) -> None: ...


def _tube(video: ZMVideo) -> int:
    out = [s for s in video._fragment.specials if isinstance(s, Instance) and s.of == "zm_video_out"]
    assert len(out) == 1
    params = {i.name: i.value for i in out[0].items if isinstance(i, Instance.Parameter)}
    return params["TUBE"].value


def test_the_sims_pipeline_shows_the_browsers_tube() -> None:
    assert TUBE_BROWSER == 0  # black: docs/css/crt.css .container, vmix.c, zm_video_mix.v
    assert _tube(ZMVideo(_Platform(), None, max_burst=0)) == TUBE_BROWSER


def test_the_browsers_tube_is_the_css_one() -> None:
    """The page's tube is the model's: crt.css paints .container (and its border) black."""
    css = (Path(__file__).resolve().parents[2] / "docs/css/crt.css").read_text()
    block = css[css.index(".container {") : css.index("}", css.index(".container {"))]
    assert "background: #000000;" in block and "#121010" not in block


def test_a_board_pipeline_shows_black_behind_the_planes() -> None:
    assert TUBE_BOARD == 0
    assert _tube(ZMVideo(_Platform(), None, max_burst=0, tube=TUBE_BOARD)) == TUBE_BOARD


def test_the_board_soc_builds_its_pipeline_with_the_board_tube() -> None:
    """Text, not elaboration: the board SoC needs the Z7 platform and its PS7."""
    assert "tube=TUBE_BOARD" in inspect.getsource(zigmachine_soc.ZigMachineSoC._add_video_pipe)
