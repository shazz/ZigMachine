#!/usr/bin/env python3
"""freeze_placement.py PLACEMENT.json OUT.tsv [--base-netlist A.json --netlist B.json] [--match PREFIX ...]
[--types T,T] [--drop-types T,T]

Turn nextpnr-xilinx's `-o placement=` dump of a reference build into the file its
`-o preplaced=` replays: one line per cell, "<cell name>\\t<nextpnr bel name>".

Why this and not NEXTPNR_BEL from the routed JSON: the routed JSON's NEXTPNR_BEL is the
Vivado-style "SITE/BEL" (SLICE_X0Y50/D6LUT); `apply_preplaced` resolves its second column
with `getBelByName`, whose first component must be a himbaechel TILE name (X44Y44), and
that lookup is a `dict::at()` that throws on a miss (fpga/TIMING_FABLE.md "Pass 3"). The
placement dump's "nextpnr_bel" field is the tile-qualified name.

**Replaying onto an EDITED netlist** (soc/openxc7_fast.py, REUSE): give the reference
build's Yosys netlist (A) and the new one (B). A cell is pinned only if it exists in both
with the same type and the same connections, net by net name: Yosys re-maps logic far from
an edit, so a name can survive on a different cell, and pinning that one to the old bel
breaks the packer's clusters (a carry chain's member finds its bel taken). For the same reason
no cell of a cluster is pinned (MUXF7/8, CARRY4, LUTRAM, SRL, the LUTs feeding a mux or carry,
the flops it drives), nor a cell the packer made (in the dump, in neither netlist), and a
slice is pinned whole or not at all.
Hierarchical netlists (a module kept with keep_hierarchy) are walked
the way nextpnr names their cells: "<instance>.<cell>".

Filters pick the subsystem to freeze (every cell by default):
  --match VexRiscv.      keep cells whose name starts with any PREFIX
  --types RAMB36E1,...   keep only these nextpnr cell types (as in the dump's "type")
  --drop-types ...       drop these types (e.g. the global buffers the packer pins itself)
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

Signature = tuple[object, ...]


def _bit_names(module: dict) -> dict[int, str]:
    """Each net bit's name: a public one when there is one, the smallest for determinism."""
    names: dict[int, str] = {}
    for name, net in sorted(module["netnames"].items(), key=lambda kv: (kv[0].startswith("$"), kv[0])):
        for i, bit in enumerate(net["bits"]):
            if isinstance(bit, int) and bit not in names:
                names[bit] = f"{name}[{i}]"
    return names


def _is_box(module: dict) -> bool:
    """A primitive's model (BUFG, PS7, ...): a leaf cell, not hierarchy to walk."""
    attrs = module.get("attributes", {})
    return any(int(str(attrs.get(k, "0")), 2) for k in ("blackbox", "whitebox"))


CLUSTER_ROOTS = {"MUXF7", "MUXF8", "CARRY4"}  # the packer builds a fixed-shape cluster around each
CLUSTER_TYPES = CLUSTER_ROOTS | {"RAM32M", "RAM64M", "RAM32X1D", "RAM64X1D", "RAM128X1D", "SRL16E", "SRLC32E"}


def _module_cells(mod: dict, prefix: str, sigs: dict[str, Signature], clustered: set[str]) -> None:
    """One module's leaf cells into `sigs`; those in a packer cluster (a mux/carry/DRAM cell, the
    LUTs feeding a mux or carry, the flops it drives) into `clustered`."""
    bits = _bit_names(mod)
    drivers: dict[int, str] = {}
    sinks: dict[int, list[str]] = {}
    for cell, info in mod["cells"].items():
        dirs = info.get("port_directions", {})
        for port, conn in info["connections"].items():
            for b in (b for b in conn if isinstance(b, int)):
                if dirs.get(port) == "output":
                    drivers[b] = cell
                else:
                    sinks.setdefault(b, []).append(cell)
        ports = tuple((p, tuple(bits.get(b, str(b)) for b in conn)) for p, conn in sorted(info["connections"].items()))
        sigs[prefix + cell] = (info["type"], ports)
    for cell, info in mod["cells"].items():
        if info["type"] not in CLUSTER_TYPES:
            continue
        clustered.add(prefix + cell)
        if info["type"] not in CLUSTER_ROOTS:
            continue
        dirs = info.get("port_directions", {})
        for port, conn in info["connections"].items():
            for b in (b for b in conn if isinstance(b, int)):
                near = sinks.get(b, []) if dirs.get(port) == "output" else [drivers.get(b, "")]
                clustered.update(prefix + c for c in near if c)


def signatures(netlist: Path) -> tuple[dict[str, Signature], set[str]]:
    """Cell (as nextpnr names it) -> (type, its ports' nets by name), the hierarchy walked from the
    top; and the cells the packer clusters (pinning one of those to an old bel breaks the cluster)."""
    modules = json.loads(netlist.read_text())["modules"]
    top = next(n for n, m in modules.items() if m.get("attributes", {}).get("top"))
    sigs: dict[str, Signature] = {}
    clustered: set[str] = set()

    def walk(name: str, prefix: str) -> None:
        mod = modules[name]
        leaf = {c: i for c, i in mod["cells"].items() if i["type"] not in modules or _is_box(modules[i["type"]])}
        _module_cells({**mod, "cells": leaf}, prefix, sigs, clustered)
        for cell, info in mod["cells"].items():
            if cell not in leaf:
                walk(info["type"], f"{prefix}{cell}.")

    walk(top, "")
    return sigs, clustered


def unchanged(base: Path, new: Path) -> set[str] | None:
    """The cells of `new` that are the same cell in `base`, and in a packer cluster in neither;
    None when the two netlists are the same (then every cell, the packer's too, can be pinned)."""
    (a, ca), (b, cb) = signatures(base), signatures(new)
    if a == b:
        return None
    return {c for c, sig in b.items() if a.get(c) == sig and c not in ca and c not in cb}


def whole_sites(cells: dict[str, dict[str, str]], same: set[str]) -> set[str]:
    """The cells of the sites (slices, block RAMs, ...) whose every cell is unchanged. A slice is legal
    only as a whole (its flops' 5FF/6FF use, control sets and LUT pairs depend on its other cells):
    pinning half of one is what nextpnr refuses ("Bel ... A5FF is not valid for cell ...")."""
    sites: dict[str, list[str]] = {}
    for name, info in cells.items():
        sites.setdefault(info.get("site", ""), []).append(name)
    return {c for site, members in sites.items() if site and all(m in same for m in members) for c in members}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("placement", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--base-netlist", type=Path, help="the reference build's Yosys JSON")
    ap.add_argument("--netlist", type=Path, help="this build's Yosys JSON: pin only the cells that did not change")
    ap.add_argument("--match", nargs="*", default=[], help="cell-name prefixes to keep (default: all)")
    ap.add_argument("--types", default="", help="comma-separated cell types to keep")
    ap.add_argument("--drop-types", default="", help="comma-separated cell types to drop")
    a = ap.parse_args()
    keep_types = {t for t in a.types.split(",") if t}
    drop_types = {t for t in a.drop_types.split(",") if t}
    cells: dict[str, dict[str, str]] = json.loads(a.placement.read_text())
    same = unchanged(a.base_netlist, a.netlist) if a.base_netlist and a.netlist else None
    same = None if same is None else whole_sites(cells, same)
    lines = []
    for name, info in cells.items():
        bel, ctype = info.get("nextpnr_bel", ""), info.get("type", "")
        if not bel or "/" not in bel or (same is not None and name not in same):
            continue
        if (a.match and not any(name.startswith(p) for p in a.match)) or (keep_types and ctype not in keep_types):
            continue
        if ctype not in drop_types:
            lines.append(f"{name}\t{bel}")
    a.out.write_text("\n".join(lines) + ("\n" if lines else ""))
    print(f"{a.out}: {len(lines)} of {len(cells)} cells pinned", file=sys.stderr)


if __name__ == "__main__":
    main()
