"""The KESTREL system table: what a lean cart image binds to in the system image, and
the version that says which carts a system runs (decisions.md 2026-10-15).

    python3 fpga/tools/sys_abi.py --check      # the gate: fpga/cycles/sys_abi.txt is the layout of today's modules
    python3 fpga/tools/sys_abi.py --break      # ...and a changed layout without a version bump is caught
    python3 fpga/tools/sys_abi.py --update     # rewrite it: minor + 1 for appended ROM exports, else major + 1

The layout is computed, never typed: the runtime the cart takes from the system (RUNTIME),
every env.* the browser would bind a cart to (each rom.wasm export, scene_hash.mjs's
MACHINE_ENV list of machine-video.wasm exports), the cart header (HEADER), the bridges
(tools/host_bridges.py) and the map_cart.zig constants both images and glass agree on.
sys_abi.txt holds it, the version, and per version the hash of the layout it named: a
layout that changed under the same version fails, so does one the modules no longer have.
Standard library only, so build.sh runs it without the fpga toolchain.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
MANIFEST = FPGA / "cycles/sys_abi.txt"
sys.path.insert(0, str(FPGA / "tools"))
from host_bridges import DISK_APP_BRIDGE, INPUT_BRIDGE, MIRROR, SONG_BRIDGE, STREAM  # after the path insert
from host_gen import MACHINE_ENV
from sys_abi_layout import CONSTS, HEADER, RUNTIME, TYPE_SOURCES, TYPES
from sys_abi_break import run_breaks
from sys_abi_manifest import Manifest, bumped, check, parse, vtext
from wasm_sig import signatures


def sig(ret: str, params: list[str]) -> str:
    return f"{ret}({','.join(params)})"


def env_entries(root: Path = ROOT) -> dict[str, str]:
    """name -> 'owner sig' for each env.* a cart can bind: rom.wasm's exports win, as `...rom` last;
    then the host's (STREAM), which no module exports."""
    rom, _ = signatures((root / "docs/rom.wasm").read_bytes())
    machine, _ = signatures((root / "docs/machine-video.wasm").read_bytes())
    out = {n: f"machine {sig(*machine[n])}" for n in MACHINE_ENV if n in machine and n not in rom}
    missing = [n for n in MACHINE_ENV if n not in machine and n not in rom]
    if missing:
        raise SystemExit(f"sys_abi: machine-video.wasm no longer exports {', '.join(missing)}")
    out.update({n: f"rom {sig(*s)}" for n, s in rom.items()})
    # The host's own: the stream ring's imports (host/hstream.h), served by the system image (1.1).
    out.update({n: f"host {sig(r, p)}" for n, (r, p, _) in STREAM.items()})
    # The audio-state mirror (cycles/aud_state.h), called by the lean cart's glue, not its wasm (1.2).
    out.update({n: f"host {sig(r, p)}" for n, (r, p, _) in MIRROR.items()})
    return out


def map_consts(path: Path = FPGA / "glass/src/map_cart.zig") -> dict[str, int]:
    found = dict(re.findall(r"pub const (\w+): u32 = (0x[0-9A-Fa-f_]+|\d+);", path.read_text()))
    if missing := [c for c in CONSTS if c not in found]:
        raise SystemExit(f"sys_abi: map_cart.zig has no {', '.join(missing)}")
    return {c: int(found[c].replace("_", ""), 0) for c in CONSTS}


def c_types(root: Path = FPGA) -> list[tuple[str, str]]:
    """Each struct of TYPE_SOURCES as its source defines it, comments and spacing dropped."""
    out = []
    for rel, names in TYPE_SOURCES:
        text = re.sub(r"/\*.*?\*/", "", (root / rel).read_text(), flags=re.S)
        for n in names:
            m = re.search(r"typedef struct " + n + r" (\{.*?\}) " + n + ";", text, re.S)
            if not m:
                raise SystemExit(f"sys_abi: {rel} has no `typedef struct {n} {{...}} {n};`")
            out.append((n, " ".join(m.group(1).split())))
    return out + TYPES


def fixed_lines(consts: dict[str, int]) -> list[str]:
    """Everything but the env entries: the constants, the runtime, the types, the header, the bridges."""
    lines = [f"const {k} {v:#x}" for k, v in consts.items()]
    lines += [f"rt {s} {sig(r, p)}" for s, r, p, _ in RUNTIME]
    lines += [f"type {t} {body}" for t, body in c_types()]
    lines += [f"hdr {n} {t}" for n, t in HEADER]
    lines += [f"bridge songs {n} {sig('u32', p)}" for n, p in SONG_BRIDGE]
    lines += [f"bridge input {n} {sig(r, p)}" for n, r, p in INPUT_BRIDGE]
    return lines + [f"bridge dapp {n} {sig(r, p)}" for n, r, p in DISK_APP_BRIDGE]


def body(env: dict[str, str], consts: dict[str, int], order: list[str]) -> list[str]:
    """The layout, env entries in `order` (the manifest's) with any new ones appended sorted."""
    names = [n for n in order if n in env] + sorted(n for n in env if n not in order)
    return fixed_lines(consts) + [f"env {n} {env[n]}" for n in names]


def current(m: Manifest, root: Path = ROOT) -> list[str]:
    return body(env_entries(root), map_consts(), m.env_order())


def update(m: Manifest, want: list[str], path: Path) -> int:
    if m.body == want and not check(m, want):
        print(f"sys_abi: version {vtext(m.version)}, unchanged")
        return 0
    new = bumped(m, want)
    path.write_text(new.text())
    print(f"sys_abi: {path.name} is now version {vtext(new.version)}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--check", action="store_true")
    g.add_argument("--update", action="store_true")
    g.add_argument("--break", dest="brk", action="store_true", help="prove a changed layout is caught")
    ap.add_argument("--manifest", type=Path, default=MANIFEST)
    a = ap.parse_args()
    m = parse(a.manifest.read_text()) if a.manifest.exists() else Manifest((0, 0), [], [])
    want = current(m)
    if a.update:
        return update(m, want, a.manifest)
    if a.brk:
        return run_breaks(m, want)
    errs = check(m, want)
    for e in errs:
        print(f"sys_abi: FAIL {e}")
    if not errs:
        print(f"sys_abi: ok, table version {vtext(m.version)} ({len(m.env_order())} env entries)")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
