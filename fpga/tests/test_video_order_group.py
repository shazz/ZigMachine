"""The board's line-major rule (cycles/bplanes.h) at the state level: tools/video_order_group.py
rebuilds what every pass consumes when each run of handler-free planes is composited line by line,
and the RTL replay of that rebuild must equal the machine on every corpus frame. With the rule
ignored (every plane one group, handlers interleaved), frames whose handlers write what another
plane reads must change: s:medium (RESOLUTION per line) and s:overscan (RES_FLICKER, HSCROLL)."""

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


tb = lm.tb  # the session's replay testbench
