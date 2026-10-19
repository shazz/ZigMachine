"""bench_collect.py: the ZIGGY bench's log read off the board through devmem, over a fake shell that
answers `devmem` from a dict of DDR words, as busybox would."""

from __future__ import annotations

import struct
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import bench_collect as bc

HDR = bc.glass_map.DDR_CART_BASE + bc.glass_cart.CART_IMG_AT
LOG_CPU = bc.glass_map.CART_CPU_BASE + 0x30D390  # where the cart's .bss would start
TEXT = "ZMBENCH-INFO cart=bench\nZMBENCH name=st.sw.16K size=16384 cyc=110592 med=110600 ops=4096 dwait=1 dwr=4096\n"


class FakeShell:
    """DDR as words; `states` are the log's (done) values poll after poll."""

    def __init__(self, tag: bytes = b"bench", states: tuple[int, ...] = (1,)) -> None:
        self.words: dict[int, int] = {}
        self.states, self.polls, self.cmds = list(states), 0, []
        self.put(HDR, struct.pack("<I", bc.HDR_MAGIC))
        self.put(HDR + bc.BSS_START_AT, struct.pack("<I", LOG_CPU))
        self.put(HDR + bc.TAG_AT, tag.ljust(8, b"\0"))
        self.log = bc.cart_phys(LOG_CPU)
        raw = TEXT.encode()
        self.put(self.log, struct.pack("<4I", bc.LOG_MAGIC, 0, len(raw), 2) + raw.ljust(-(-len(raw) // 4) * 4, b"\0"))

    def put(self, at: int, data: bytes) -> None:
        for i in range(0, len(data), 4):
            self.words[at + i] = struct.unpack_from("<I", data, i)[0]

    def run(self, cmd: str, timeout: float = 10.0) -> tuple[int, str]:
        self.cmds.append(cmd)
        if cmd.startswith("glass ctl"):
            return 0, ""
        addrs = [int(t.rstrip(";"), 16) for t in cmd.split() if t.startswith("0x")]
        if addrs[:1] == [self.log] and len(addrs) == bc.LOG_HDR_WORDS:  # a poll of the log header
            done = self.states[min(self.polls, len(self.states) - 1)]
            self.polls += 1
            self.words[self.log + 4] = done
        return 0, "\n".join(f"0x{self.words.get(a, 0):08X}" for a in addrs)


@pytest.fixture(autouse=True)
def no_sleep(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(bc.time, "sleep", lambda s: None)


def test_the_log_is_found_from_the_cart_header_and_read_whole() -> None:
    sh = FakeShell()
    text = bc.collect(sh, None, 10.0)
    assert text == TEXT
    (row,) = bc.parse(text)
    assert row["name"] == "st.sw.16K" and bc.derived(row)["cyc_per_op"] == "27.00"
    assert bc.derived(row)["mb_s"] == "14.8"  # 16384 B in 110592 cycles at 100 MHz


def test_a_cart_window_without_the_bench_is_refused() -> None:
    with pytest.raises(bc.NotRunning, match="not the bench"):
        bc.collect(FakeShell(tag=b"hello"), None, 10.0)


def test_after_a_load_a_log_left_done_by_an_earlier_run_is_not_taken() -> None:
    # Arrange: the old run's log says done, the new one is running for two polls, then done.
    sh = FakeShell(states=(1, 0, 0, 1))
    # Act
    text = bc.collect(sh, "demo-bench.zmd", 600.0)
    # Assert
    assert sh.cmds[0] == "glass ctl load demo-bench.zmd" and sh.polls == 4 and text == TEXT


def test_a_bench_that_never_finishes_times_out(monkeypatch: pytest.MonkeyPatch) -> None:
    clock = iter(range(0, 1000, 5))
    monkeypatch.setattr(bc.time, "monotonic", lambda: float(next(clock)))
    with pytest.raises(bc.NotRunning, match="did not finish"):
        bc.collect(FakeShell(states=(0,)), None, 30.0)


def test_a_short_devmem_reply_is_an_error_not_a_short_log() -> None:
    sh = FakeShell()
    sh.run = lambda cmd, timeout=10.0: (0, "0x00000001")  # type: ignore[method-assign]  # one word for many
    with pytest.raises(bc.NotRunning, match="devmem read 1 of 4"):
        bc.find_log(sh)


def test_the_csv_carries_cycles_an_op_and_mb_s(tmp_path: Path) -> None:
    stem = bc.save(TEXT, tmp_path)
    rows = stem.with_suffix(".csv").read_text().splitlines()
    assert rows[0] == "name,size,cyc,med,ops,dwait,dwr,cyc_per_op,mb_s"
    assert rows[1] == "st.sw.16K,16384,110592,110600,4096,1,4096,27.00,14.8"
