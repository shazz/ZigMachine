"""The memory-path configurations of CYCLES.md "Memory path", as parameters of
soc/zm_memtiming.py, and the runs that measure them.

Every latency is in cycles of the cart CPU at 150 MHz (6.7 ns), EXTRA over the
sim's own cost of 2 cycles a word. Sources (CYCLES.md has the derivation):
- UG585 v1.8.1 (Zynq-7000 TRM) 5.3 and 22.4.4: the HP ports' FIFOs and
  arbitration give "higher minimum latency than other interfaces"; the ACP has
  "the lowest memory latency to memory of the PL interfaces"; HP write
  acceptance is 8 to 32 commands (5.3.1).
- UG1145 (SDK System Performance Analysis), ch. 8, ZC702: average HP read
  latency from DDR "40-44 cycles" of the 100 MHz PL clock under four saturating
  HP masters, i.e. 400-440 ns: the LOADED figure.
- JBLopen's Zynq-7000 bare-metal benchmarks: a Cortex-A9 load that misses to
  DDR3-1066 takes about 88 CPU cycles (110 ns at 800 MHz); an L2 hit about 31 ns.
"""

from __future__ import annotations

from dataclasses import dataclass, field

HP = 24  # unloaded HP read, first word: ~110 ns DDR + ~40 ns PL<->PS FIFOs/CDC + bridge
HP_LOADED = 62  # UG1145: 400-440 ns under saturating HP traffic
ACP_MISS, ACP_HIT = 20, 10  # ACP through the SCU: DDR (~150 ns) or the PS L2 (~80 ns)
SB = {"sb_depth": 8, "sb_drain": 2}  # one single-beat AXI write per store, 8 outstanding
WC = {"sb_depth": 8, "sb_drain": 4, "sb_combine": 1, "wc_timeout": 16}  # one 32-byte burst per entry

MEM: dict[str, dict[str, int]] = {
    "sram": {},  # the sim as it was: one-cycle RAM
    "hp": {"rd_lat": HP, "wr_lat": HP},  # blocking writes: wait for the B response
    "hp_sb": {"rd_lat": HP, **SB},
    "hp_wc": {"rd_lat": HP, **WC},
    "hp_wc_rdwait": {"rd_lat": HP, **WC, "rd_waits_sb": 1},
    "hp_free": {"rd_lat": HP, "sb_depth": 0xFFFF, "sb_drain": 1},  # stores cost nothing: the bound
    "hp_load": {"rd_lat": HP_LOADED, "wr_lat": HP_LOADED},
    "hp_load_wc": {"rd_lat": HP_LOADED, **WC},
    "acp_wc": {"rd_lat": ACP_MISS, "l2_on": 1, "l2_hit_lat": ACP_HIT, **WC},
}

# Frames per cart image (hashed at the last one): enough to reach each cart's
# heavy phase (union_beatdis's effects after frame 30, skystrike's after 30).
FRAMES = {"union_beatdis": 120, "skystrike": 48, "ulm_dsots": 30, "tutorial": 30, "polkadots": 12}
CARTS = ["union_beatdis", "ulm_dsots", "skystrike", "tutorial"]
CORES = ["std", "I4D4", "I16D4", "I16w2D4", "I32w2D4", "I16w2D16w2", "I4D16w2"]


@dataclass(frozen=True)
class Plan:
    """One block of runs: every cart x memory config x build variant, on one core."""

    core: str
    mems: list[str]
    carts: list[str] = field(default_factory=lambda: list(CARTS))
    variants: list[str] = field(default_factory=lambda: ["aligned"])


PLANS = {
    "memory": [  # the memory path, on LiteX's own `standard` core
        Plan("std", ["sram", "hp", "hp_sb", "hp_wc", "hp_free", "hp_load", "hp_load_wc", "acp_wc"]),
        Plan("std", ["hp_wc_rdwait"], carts=["union_beatdis"]),
        Plan("std", ["sram", "hp", "hp_wc"], variants=["nobounds"]),
    ],
    # The cache geometry, on the memory path chosen above. The four carts above
    # refill 1-5 K lines a frame (std, hp_wc): only skystrike (the most D$ misses)
    # and polkadots (770 K I$ refills) can move.
    "caches": [Plan(core, ["hp_wc"], carts=["skystrike", "polkadots"]) for core in CORES]
    + [Plan("std", ["sram"], carts=["polkadots"])],
}


def memcfg_text(name: str) -> str:
    """zm_memcfg.init: one hex word per line, in zm_memtiming.CFG order."""
    from soc.zm_memtiming import CFG

    params = MEM[name]
    unknown = set(params) - set(CFG)
    if unknown:
        raise ValueError(f"memory config {name}: unknown parameter(s) {sorted(unknown)}")
    return "".join(f"{params.get(k, 0):x}\n" for k in CFG)
