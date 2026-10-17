"""fpga/cycles/sys_abi.txt, the system table's record (tools/sys_abi.py): the layout's lines,
its version, and per version the hash of the layout it was given. Parsing, the check, and
the bump --update applies."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass

HEAD = """# fpga/cycles/sys_abi.txt: the KESTREL system table and cart header (decisions.md 2026-10-15).
# GENERATED and checked by fpga/tools/sys_abi.py (build.sh runs --check): never edit by hand;
# `python3 fpga/tools/sys_abi.py --update` rewrites it and bumps the version."""

Version = tuple[int, int]


def digest(lines: list[str]) -> str:
    return hashlib.sha256("\n".join(lines).encode()).hexdigest()[:16]


def vtext(v: Version) -> str:
    return f"{v[0]}.{v[1]}"


@dataclass
class Manifest:
    version: Version
    body: list[str]
    history: list[tuple[Version, str]]

    def env_order(self) -> list[str]:
        return [ln.split()[1] for ln in self.body if ln.startswith("env ")]

    def text(self) -> str:
        hist = [f"history {vtext(v)} {h}" for v, h in self.history]
        return "\n".join([HEAD, f"version {vtext(self.version)}", *self.body, *hist]) + "\n"


def _ver(text: str) -> Version:
    major, minor = text.split(".")
    return int(major), int(minor)


def parse(text: str) -> Manifest:
    version, lines, hist = None, [], []
    for ln in text.splitlines():
        if not ln.strip() or ln.startswith("#"):
            continue
        if ln.startswith("version "):
            version = _ver(ln.split()[1])
        elif ln.startswith("history "):
            _, v, h = ln.split()
            hist.append((_ver(v), h))
        else:
            lines.append(ln)
    if version is None:
        raise SystemExit("sys_abi: sys_abi.txt has no version line")
    return Manifest(version, lines, hist)


def check(m: Manifest, want: list[str]) -> list[str]:
    """Why `m` is not today's layout under an honest version, or []."""
    errs = []
    if m.body != want:
        gone = [ln for ln in m.body if ln not in want][:4]
        new = [ln for ln in want if ln not in m.body][:4]
        errs.append(f"the layout changed (gone: {gone}, new: {new}): run fpga/tools/sys_abi.py --update")
    if not m.history or m.history[-1] != (m.version, digest(m.body)):
        errs.append(f"the layout is not the one version {vtext(m.version)} was recorded with: bump the version")
    versions = [v for v, _ in m.history]
    if versions != sorted(set(versions)):
        errs.append("the history's versions must strictly increase")
    return errs


def bumped(m: Manifest, want: list[str]) -> Manifest:
    """`m` rewritten to `want`: minor + 1 if `want` only appends env entries, else major + 1, env sorted."""
    added = [ln for ln in want if ln not in m.body]
    if m.body and [ln for ln in want if ln not in added] == m.body and all(a.startswith("env ") for a in added):
        version = (m.version[0], m.version[1] + 1)
    else:
        version = (m.version[0] + 1, 0)
        fixed = [ln for ln in want if not ln.startswith("env ")]
        want = fixed + sorted(ln for ln in want if ln.startswith("env "))
    return Manifest(version, want, [*m.history, (version, digest(want))])
