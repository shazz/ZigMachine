"""List the primitive cells and modes in a Yosys JSON netlist, and fail on any not proven on silicon.

openXC7 has twice written a wrong bitstream for a primitive mode that simulates right (the
OSERDESE2 10:1 cascade, the RAMB36E1 in 72-bit SDP mode: docs/FPGA_STEPS.md "2026-10-04"). So
every cell type, and for the block RAMs and DSPs every mode, has an entry in fpga/silicon_prims.json:
  proven   checked on the board (by `make prim-test`, or a design that works there)
  pending  a `make prim-test` lane covers it, no board result yet: a warning (an error with --strict)
  suspect  board evidence against it, not settled yet: a warning (an error with --strict)
  bad      wrong on silicon: an error
A key with no entry has never been on silicon: an error.

    uv run python tools/prim_allowlist.py NETLIST.json            # check: exit 1 on bad/unknown
    uv run python tools/prim_allowlist.py NETLIST.json --strict   # pending and suspect fail too
    uv run python tools/prim_allowlist.py NETLIST.json --list     # every cell key, its count and status
"""

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ALLOWLIST = FPGA / "silicon_prims.json"
# Yosys bookkeeping, not cells that reach the bitstream.
IGNORED = {"$scopeinfo"}
STATUSES = ("proven", "pending", "suspect", "bad")
WRITE_MODES = {"READ_FIRST": "RF", "WRITE_FIRST": "WF", "NO_CHANGE": "NC"}
RAM_WIDTHS = ("READ_WIDTH_A", "READ_WIDTH_B", "WRITE_WIDTH_A", "WRITE_WIDTH_B")
DSP_REGS = (
    ("A", "AREG"),
    ("B", "BREG"),
    ("C", "CREG"),
    ("D", "DREG"),
    ("AD", "ADREG"),
    ("M", "MREG"),
    ("P", "PREG"),
    ("AC", "ACASCREG"),
    ("BC", "BCASCREG"),
    ("OP", "OPMODEREG"),
    ("ALU", "ALUMODEREG"),
    ("IN", "INMODEREG"),
    ("CI", "CARRYINREG"),
    ("CIS", "CARRYINSELREG"),
)


def _param(cell: dict, name: str) -> str:
    """A parameter as text: Yosys writes integers as binary strings, strings as themselves."""
    value = str(cell["parameters"].get(name, ""))
    if value and set(value) <= {"0", "1"}:
        return str(int(value, 2))
    return value.strip()


def _port(cell: dict, name: str) -> str:
    """A control port as hex when it is tied to constants, else "dyn"."""
    bits = cell["connections"].get(name, [])
    if not bits or not all(b in ("0", "1") for b in bits):
        return "dyn"
    return hex(int("".join(reversed(bits)), 2))


def _write_enables(cell: dict) -> int:
    """How many independent write enables drive the RAM: 1 = whole words, more = byte enables, 0 = a ROM."""
    bits = cell["connections"].get("WEA", []) + cell["connections"].get("WEBWE", [])
    return len({b for b in bits if b not in ("0", "1", "x", "z")})


def _ram_key(kind: str, cell: dict) -> str:
    """RAMB18E1 SDP r36/0 w0/36 RF/RF reg0/0 we1: mode, read A/B, write A/B, write modes (RF, WF, NC),
    output registers, independent write enables."""
    w = [_param(cell, p) or "0" for p in RAM_WIDTHS]
    modes = "/".join(WRITE_MODES.get(_param(cell, f"WRITE_MODE_{p}"), "WF") for p in "AB")
    regs = "/".join(_param(cell, f"DO{p}_REG") or "0" for p in "AB")
    mode = _param(cell, "RAM_MODE") or "TDP"
    return f"{kind} {mode} r{w[0]}/{w[1]} w{w[2]}/{w[3]} {modes} reg{regs} we{_write_enables(cell)}"


def _dsp_key(cell: dict) -> str:
    """DSP48E1 MULTIPLY ONE48 nod op=0x5 alu=0x0 in=0x0 M P: function, control ports, the regs in use."""
    regs = " ".join(short for short, p in DSP_REGS if _param(cell, p) not in ("", "0"))
    dport = "d" if _param(cell, "USE_DPORT") == "TRUE" else "nod"
    ports = " ".join(
        f"{p.lower()}={_port(cell, n)}" for p, n in (("op", "OPMODE"), ("alu", "ALUMODE"), ("in", "INMODE"))
    )
    return f"DSP48E1 {_param(cell, 'USE_MULT')} {_param(cell, 'USE_SIMD')} {dport} {ports} {regs}".rstrip()


def cell_key(kind: str, cell: dict) -> str:
    """The allowlist key of one cell: the type, plus the mode for the primitives that have them."""
    if kind in ("RAMB18E1", "RAMB36E1"):
        return _ram_key(kind, cell)
    if kind == "DSP48E1":
        return _dsp_key(cell)
    return kind


def netlist_keys(netlist: Path, top: str | None = None) -> Counter[str]:
    """Every cell key in the netlist's top module (flattened, as the SoC build writes it), with counts."""
    modules = json.loads(netlist.read_text())["modules"]
    if top is None:
        tops = [n for n, m in modules.items() if str(m.get("attributes", {}).get("top", "0")) not in ("0", "")]
        if len(tops) != 1:
            raise ValueError(f"{netlist}: expected one top module, found {tops}; pass --top")
        top = tops[0]
    cells = modules[top]["cells"].values()
    return Counter(cell_key(c["type"], c) for c in cells if c["type"] not in IGNORED)


def load_allowlist(path: Path = ALLOWLIST) -> dict[str, dict]:
    """The allowlist: key -> {"status": one of STATUSES, "evidence": text}."""
    entries = json.loads(path.read_text())["cells"]
    for key, entry in entries.items():
        if entry.get("status") not in STATUSES:
            raise ValueError(f"{path}: {key}: status must be one of {STATUSES}, not {entry.get('status')!r}")
    return entries


def verdict(keys: Counter[str], allow: dict[str, dict]) -> tuple[list[str], list[str]]:
    """(errors, warnings): a line per key that is bad or has never been on silicon, and per pending or
    suspect key."""
    errors, warnings = [], []
    for key, count in sorted(keys.items()):
        entry = allow.get(key, {})
        status, why = entry.get("status"), entry.get("evidence", "")
        if status == "bad":
            errors.append(f"BAD on silicon: {key} (x{count}): {why}")
        elif status == "suspect":
            warnings.append(f"SUSPECT on silicon: {key} (x{count}): {why}")
        elif status == "pending":
            lanes = ", ".join(entry.get("prim_test", []))
            warnings.append(f"PENDING: {key} (x{count}): prim-test lane {lanes} covers it, run it on the board")
        elif status != "proven":
            errors.append(f"never on silicon: {key} (x{count}): add a lane to make prim-test, run it on the board")
    return errors, warnings


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("netlist", type=Path, help="Yosys JSON (write_json), e.g. build/soc_z7/gateware/platform_z7.json")
    ap.add_argument("--top", help="the top module (default: the one Yosys marked top)")
    ap.add_argument("--allowlist", type=Path, default=ALLOWLIST)
    ap.add_argument("--list", action="store_true", help="print every key, its count and status, then check")
    ap.add_argument("--strict", action="store_true", help="a suspect mode is an error too")
    args = ap.parse_args(argv)
    keys = netlist_keys(args.netlist, args.top)
    allow = load_allowlist(args.allowlist)
    if args.list:
        for key, count in sorted(keys.items()):
            print(f"{count:6d}  {allow.get(key, {}).get('status', '-'):7s} {key}")
    errors, warnings = verdict(keys, allow)
    for line in errors + warnings:
        print(line)
    print(f"prim_allowlist: {args.netlist}: {len(keys)} cell kinds, {len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors or (args.strict and warnings) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
