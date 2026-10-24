"""The board's line-major rule (cycles/bplanes.h) at the state level: tools/video_order_group.py
rebuilds what every pass consumes when each run of handler-free planes is composited line by line,
and the RTL replay of that rebuild must equal the machine on every corpus frame. With the rule
ignored (every plane one group, handlers interleaved), frames whose handlers write what another
plane reads must change: s:medium (RESOLUTION per line) and s:overscan (RES_FLICKER, HSCROLL).

Pure handlers (own palette, RES_FLICKER bumps: cycles/vseq_group.c) may join a group when the
sequencer stores RES_FLICKER before each pass as the plane's own handler left it (`fw`): s:overscan,
whose planes flicker on different lines, then equals the machine; s:medium (RESOLUTION, which
vseq_group_ok keeps out of a handler group) still does not."""

import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_rtl_linemajor as lm  # the corpus with leonard, and its sources
import video_order_group as vog


@pytest.mark.parametrize("key", lm.KEYS)
def test_the_rule_never_changes_a_frame(tb: Path, key: str) -> None:
    d, frames = lm._source(key)
    for f in frames:
        ok, line = vog.analyse(d, f, tb)
        assert ok, f"{key} {f}: {line}"


@pytest.mark.parametrize("key", ["s:medium", "s:overscan"])
def test_the_rule_ignored_changes_a_frame_whose_handlers_talk(tb: Path, key: str) -> None:
    d, frames = lm._source(key)
    ok, line = vog.analyse(d, frames[0], tb, every=True)
    assert not ok, f"{key}: interleaving its handler planes went unnoticed ({line})"


def test_pure_handlers_join_a_group_with_the_firmware_flicker(tb: Path) -> None:
    d, frames = lm._source("s:overscan")
    for f in frames:
        ok, line = vog.analyse(d, f, tb, every=True, fw=True)
        assert ok, f"s:overscan {f}: {line}"


def test_the_firmware_flicker_does_not_make_resolution_safe(tb: Path) -> None:
    d, frames = lm._source("s:medium")
    ok, line = vog.analyse(d, frames[0], tb, every=True, fw=True)
    assert not ok, f"s:medium: a RESOLUTION handler in a group went unnoticed ({line})"


tb = lm.tb  # the session's replay testbench
