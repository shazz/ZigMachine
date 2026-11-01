"""Read bypass for WishboneHP's posted stores (soc/zm_hp.py `read_bypass`, 2026-10-19).

With `posted=N` every read waited for `idle`: the whole store buffer drained, every write
answered, before the bridge sent an AR. A memcpy pays that once a line (BENCH_REPORTS.md:
~20 of its ~86 cycles a 32-byte line). Here a cache-line refill goes out at once unless a
store to the SAME 32-byte line is still unanswered; then it waits for the drain, as before.

**What "unanswered" covers.** A store is in DDR only at its write response (AWCACHE 0000,
one AXI ID, in-order B: soc/zm_io_fence.py). PostedStores' ring forgets an entry's address
the cycle it is issued, so the tags here live from `push` to the store's B: up to `depth`
buffered plus INFLIGHT issued, one slot each, retired in order (same-ID B responses come in
issue order, and issue order is push order).

**Ordering on the HP port.** AR and AW/W are separate AXI channels with no order between
them; only a read and a write to DIFFERENT lines ever overlap, which AXI allows and no CPU
load can see. Same-line reads still wait for the B, so a load (or an I$ refill of code the
CPU has just stored: the loader) sees every earlier store. Only bursts bypass: a single
(classic) read keeps the full drain, and IO loads never reach this bridge (soc/zm_io_fence.py
holds IO stores until `idle`, which is unchanged).

`break_` mutants, each caught by tests/test_hp_bypass.py: "nocompare" (every burst bypasses),
"headonly" (only the oldest tag is compared), "retire_on_issue" (a tag dies when its store
leaves the ring, not at its B); in WishboneHP._bypass, "nowait" (a refill trusts the registered
compare of whatever was on the bus the cycle before) and "classic_too" (single reads bypass).
"""

from __future__ import annotations

from functools import reduce
from operator import or_
from typing import Any

from litex.gen import LiteXModule
from migen import Array, If, Mux, Signal

from soc.zm_hp_posted import INFLIGHT

LINE_TAG = 20  # the 32-byte line within the 32 MiB window: word address bits 3..22
BREAKS = ("", "nocompare", "headonly", "retire_on_issue", "nowait", "classic_too")


def _step(p: Signal, n: int) -> Any:  # Any: a Migen expression
    return Mux(p == n - 1, 0, p + 1)


class StoreTags(LiteXModule):
    """The line of every store from its `push` to its `retire` (its B), and `clash`: some
    pending store is on line `probe`. `issue`: a store left the buffer (the "retire_on_issue"
    mutant retires on it)."""

    def __init__(self, depth: int, push: Signal, line: Signal, retire: Signal, issue: Signal,
                 break_: str = "") -> None:  # fmt: skip
        if break_ not in BREAKS:
            raise ValueError(f"zm_hp_bypass: unknown break {break_!r}")
        slots = depth + INFLIGHT  # buffered + issued, the most stores ever unanswered
        self.probe, self.clash = Signal(LINE_TAG), Signal()
        tags = Array(Signal(LINE_TAG, name=f"st_tag{i}") for i in range(slots))
        live = Signal(slots)
        w, r = Signal(max=slots), Signal(max=slots)
        gone = issue if break_ == "retire_on_issue" else retire
        self.sync += [
            If(push, tags[w].eq(line[:LINE_TAG]), w.eq(_step(w, slots))),
            If(gone, r.eq(_step(r, slots))),
            # The pushed slot is free (at most `slots` stores unanswered), so it is never the retired one.
            *[live[i].eq((live[i] | (push & (w == i))) & ~(gone & (r == i))) for i in range(slots)],
        ]  # fmt: skip
        hits = [live[i] & (tags[i] == self.probe) for i in range(slots)]
        if break_ == "nocompare":
            self.comb += self.clash.eq(0)
        elif break_ == "headonly":
            self.comb += self.clash.eq((live >> r)[0] & (tags[r] == self.probe))
        else:
            self.comb += self.clash.eq(reduce(or_, hits))
