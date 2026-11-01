"""The read bypass (soc/zm_hp_bypass.py, WishboneHP `read_bypass`): a cache-line refill goes to
DDR ahead of the posted stores unless one of them, buffered or still awaiting its B, is on the
refill's line; a single read keeps the full drain; an IO store keeps its fence.

Two benches: the model port (tests/hp_port_model.py) records every AR beside the stores still
unanswered, the invariant ("no AR for a line with an unanswered store") whatever the RAM model's
write timing; the DDR model with a slow write channel (test_hp_posted.Bench) checks the data.
Break tests (ZM_RTL_BREAK=1) build each zm_hp_bypass mutant and require a failure."""

from __future__ import annotations

import os

import pytest
import test_io_fence
from hp_port_model import B_LAT, PortBench, Seen, Sim, port
from migen import run_simulation
from test_hp_posted import Bench, access

from soc.zm_hp import CPU_BASE

M, L = CPU_BASE + 0x1000, CPU_BASE + 0x2000  # two lines: the stores' and the refill's
BREAK = pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")


def refill(b: PortBench | Bench, line: int) -> Sim:
    """VexRiscv's refill: an incrementing 8-beat burst, the last beat cti 111; returns
    (the 8 words, cycles from the request to the last acknowledge)."""
    words, total = [], 0
    for i in range(8):
        w, n = yield from access(b, line + 4 * i, cti=0b111 if i == 7 else 0b010)  # type: ignore[arg-type]
        words.append(w)
        total += n + 1
    return words, total


Op = tuple[str, int]  # ("st", addr): a one-word store; ("rf", line): a refill; ("rd", addr): a single read


def _run(ops: list[Op], b_lat: int = B_LAT, read_bypass: bool = True, break_: str = "") -> Seen:
    """`ops` in order on the model port, writes answered `b_lat` after their AW."""
    p, seen = PortBench(read_bypass, break_), Seen()

    def cpu() -> Sim:
        for i, (op, a) in enumerate(ops):
            if op == "rf":
                yield from refill(p, a)
            else:
                yield from access(p, a, 0x100 + i if op == "st" else None)  # type: ignore[arg-type]

    run_simulation(p, [cpu(), port(p, 600, seen, b_lat)])
    return seen


def _ordering(stores: list[int], single: bool = False, read_bypass: bool = True, break_: str = "") -> Seen:
    """`stores` (one word each, in order), then one read of line L: a refill, or `single`."""
    return _run([*(("st", a) for a in stores), ("rd", L + 8) if single else ("rf", L)], B_LAT, read_bypass, break_)


SCENARIOS: dict[str, tuple[list[Op], int]] = {  # each mutant fails at least one; the bypass passes them all
    "same line, the only store": ([("st", L + 12), ("rf", L)], B_LAT),
    "same line, behind older unanswered stores": (
        [*(("st", M + 4 * i) for i in range(6)), ("st", L + 12), ("rf", L)],
        B_LAT,
    ),
    # The refill of M leaves a no-clash compare in the register; L's must not start on it.
    "same line, right after a refill of another line": ([("st", L + 12), ("rf", M), ("rf", L)], 4 * B_LAT),
    "other line, eight stores": ([*(("st", M + 4 * i) for i in range(8)), ("rf", L)], B_LAT),
}


def _clashes(break_: str = "") -> list[str]:
    """The scenarios in which an AR left for a line that still had an unanswered store."""
    return [name for name, (ops, b_lat) in SCENARIOS.items()
            if any(line in pending for _, line, _, pending in _run(ops, b_lat, break_=break_).reads)]  # fmt: skip


def test_no_read_goes_out_for_a_line_with_an_unanswered_store() -> None:
    assert _clashes() == []


def test_a_refill_of_another_line_goes_out_while_the_stores_are_unanswered() -> None:
    (cycle, line, n, pending), *_ = _run(SCENARIOS["other line, eight stores"][0]).reads
    assert n == 3 and line == (L >> 5) & 0xFFFFF and len(pending) >= 4, (cycle, pending)


def test_without_the_bypass_the_same_refill_waits_for_every_store() -> None:
    (_, _, _, pending), *_ = _ordering([M + 4 * i for i in range(8)], read_bypass=False).reads
    assert pending == ()


def test_a_single_read_still_waits_for_every_store() -> None:
    (_, _, n, pending), *_ = _ordering([M + 4 * i for i in range(8)], single=True).reads
    assert n == 0 and pending == ()


def _raw(break_: str = "") -> list[int]:
    """On the DDR model whose write channel backs up: stores to M, then one into L (still in the
    buffer), then a refill of L; returns the line's words."""
    b, got = Bench(read_bypass=True, break_=break_), []

    def cpu() -> Sim:
        for i in range(6):
            yield from access(b, M + 4 * i, 0xA0 + i)
        yield from access(b, L + 12, 0x5EED)
        got.extend((yield from refill(b, L))[0])

    run_simulation(b, [cpu()])
    return got


def test_a_refill_after_a_store_to_its_line_returns_the_stored_word() -> None:
    assert _raw()[3] == 0x5EED


def test_an_io_store_still_waits_for_the_posted_stores_with_the_bypass() -> None:
    stale, seen = test_io_fence._doorbell(test_io_fence.Bench(read_bypass=True))
    assert seen["rung"] == 1 and stale == []


def test_an_unknown_mutant_or_a_bypass_without_posted_stores_fails_the_build() -> None:
    with pytest.raises(ValueError, match="unknown break"):
        PortBench(True, "nope")
    with pytest.raises(ValueError, match="needs posted"):
        Bench(posted=0, read_bypass=True)


@BREAK
def test_break_nocompare_reads_the_word_before_the_store() -> None:
    assert _raw("nocompare")[3] != 0x5EED


@BREAK
@pytest.mark.parametrize("break_", ["nocompare", "headonly", "retire_on_issue", "nowait"])
def test_break_each_mutant_sends_a_read_ahead_of_a_same_line_store(break_: str) -> None:
    assert _clashes(break_) != []


@BREAK
def test_break_classic_too_sends_a_single_read_ahead_of_the_stores() -> None:
    (_, _, _, pending), *_ = _ordering([M + 4 * i for i in range(8)], single=True, break_="classic_too").reads
    assert pending != ()
