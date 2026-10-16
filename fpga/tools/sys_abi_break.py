"""sys_abi.py --break: the check must fail on every way a layout can change without its
version, and pass once --update's bump is applied. Each case mutates today's layout (never
the file) and states which bump makes it honest again."""

from __future__ import annotations

from collections.abc import Callable

from sys_abi_manifest import Manifest, bumped, check, digest


def _retype(lines: list[str]) -> list[str]:
    i = next(k for k, ln in enumerate(lines) if ln.startswith("env "))
    name, owner, sig = lines[i].split()[1:]
    return [*lines[:i], f"env {name} {owner} f64{sig[sig.index('('):]}", *lines[i + 1 :]]


CASES: list[tuple[str, Callable[[list[str]], list[str]], tuple[int, int]]] = [
    ("a new ROM export", lambda ls: [*ls, "env romBreakNew rom u32(u32)"], (0, 1)),
    ("a ROM export retyped", _retype, (1, 0)),
    ("a ROM export removed", lambda ls: [ln for ln in ls if ln != next(x for x in ls if x.startswith("env "))], (1, 0)),
    ("the cart header grows", lambda ls: [*ls[:1], "hdr break uint32_t {}", *ls[1:]], (1, 0)),
    ("CART_IMG_AT moves", lambda ls: ["const CART_IMG_AT 0x400000", *ls[1:]], (1, 0)),
]


def run_breaks(m: Manifest, want: list[str]) -> int:
    bad = 0
    if check(m, want):
        print("sys_abi --break: today's sys_abi.txt does not pass --check; fix that first")
        return 1
    for what, mutate, bump in CASES:
        changed = mutate(list(want))
        caught = bool(check(m, changed))
        fixed = bumped(m, changed)
        expect = (m.version[0], m.version[1] + 1) if bump == (0, 1) else (m.version[0] + 1, 0)
        honest = not check(fixed, fixed.body) and fixed.version == expect
        ok = caught and honest
        bad += not ok
        print(f"sys_abi --break: {'ok ' if ok else 'FAIL'} {what}: caught={caught}, after the bump {fixed.version}")
    forged = Manifest(m.version, _retype(m.body), m.history)  # the layout edited under the same version
    caught = bool(check(forged, forged.body)) and forged.history[-1][1] != digest(forged.body)
    bad += not caught
    print(f"sys_abi --break: {'ok ' if caught else 'FAIL'} a layout edited under the same version: caught={caught}")
    return 1 if bad else 0
