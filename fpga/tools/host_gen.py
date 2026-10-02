"""Generate the per-cart half of the native host (fpga/host/): the env imports,
the --call export table and the RAM high-water constants, as one C file.

    uv run python tools/host_gen.py --build build/host/<tag> --cart ../docs/demo-<tag>.wasm

It reads the wasm2c headers (machine.h and rom.h in build/host/common, cart.h in
--build) rather than a hand-written list, so every cart gets exactly the imports
it declares, resolved by apps/scene_hash.mjs's rules:

  - machine's env.hblDispatch           -> cart.hblDispatch
  - every other env.X: rom.X if rom exports it (the JS spreads `...rom` last),
    else machine.X if X is in the JS's explicit list (MACHINE_ENV),
    else a no-op returning what `undefined` converts to (0, NaN; an i64 throws).
"""

import argparse
import re
import sys
from pathlib import Path

import wasm_info

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent

# scene_hash.mjs boot(): the machine exports handed to the cart's env, verbatim.
MACHINE_ENV = [
    "hwVideoBase",
    "hwBlit",
    "hwRamBase",
    "hwRamTop",
    "hwRamSize",
    "hwRamUsed",
    "hwRamFree",
    "hwRamAlloc",
    "hwRamMark",
    "hwRamRelease",
    "hwRamAllocFailures",
    "hwRomRamBase",
    "hwRomRamTop",
    "hwRomRamSize",
    "hwRomRamUsed",
    "hwRomRamFree",
]

DECL = re.compile(r"^(void|u32|u64|f32|f64) w2c_(env|machine|rom|cart)_(\w+)\(([^)]*)\);$", re.MULTILINE)
ZERO = {"u32": "0", "f32": "NAN", "f64": "NAN"}
FROM_NUMBER = {"u32": "host_to_i32(a[{i}])", "f32": "(f32)a[{i}]", "f64": "a[{i}]"}


def decls(header: Path, owner: str) -> dict[str, tuple[str, list[str]]]:
    """name -> (return type, parameter types after the instance) for one owner prefix."""
    out = {}
    for ret, who, name, params in DECL.findall(header.read_text()):
        if who == owner:
            out[name] = (ret, [p.strip() for p in params.split(",")[1:]])
    return out


def link_check(paths: dict[str, Path], pages: int) -> None:
    """Refuse what the JS host refuses: an env.memory import our memory cannot satisfy."""
    for who, path in paths.items():
        mem = wasm_info.memory_import(path.read_bytes())
        if mem and (mem[0] > pages or (mem[1] is not None and mem[1] < pages)):
            sys.exit(f"host_gen: LinkError: {who} wants env.memory {mem}, the host has {pages} pages")


def imports(headers: dict[str, Path]) -> dict[str, tuple[str, list[str], set[str]]]:
    """Every env.X any of the three modules imports, with one signature for all of them."""
    out: dict[str, tuple[str, list[str], set[str]]] = {}
    for who, h in headers.items():
        for name, (ret, params) in decls(h, "env").items():
            if name in out and out[name][:2] != (ret, params):
                sys.exit(f"host_gen: env.{name}: {who} and {out[name][2]} disagree on its type")
            out.setdefault(name, (ret, params, set()))[2].add(who)
    return out


def resolve(name: str, who: set[str], exports: dict[str, dict]) -> str | None:
    """Which instance serves env.<name>, or None for scene_hash.mjs's no-op stub."""
    if name == "hblDispatch":
        if who != {"machine"}:
            sys.exit(f"host_gen: env.hblDispatch imported by {who}; only the machine's resolves to the cart")
        return "cart"
    if name in exports["rom"]:
        return "rom"
    return "machine" if name in MACHINE_ENV else None


def forwarder(name: str, ret: str, params: list[str], target: str | None, exports: dict) -> str:
    args = "".join(f", {t} a{i}" for i, t in enumerate(params))
    head = f"{ret} w2c_env_{name}(struct w2c_env* e{args})"
    if target is None:
        unused = " ".join(f"(void)a{i};" for i in range(len(params)))
        if ret == "u64":  # BigInt(undefined) throws, so the JS host never returns from this
            body = "wasm_rt_trap(WASM_RT_TRAP_UNREACHABLE);"
        else:
            body = "return;" if ret == "void" else f"return {ZERO[ret]};"
        return f"/* env.{name}: scene_hash.mjs no-op stub */\n{head} {{ (void)e; {unused} {body} }}\n"
    if exports[target].get(name) != (ret, params):
        sys.exit(f"host_gen: env.{name} does not match {target}.{name}'s type")
    call = f"w2c_{target}_{name}(&e->{target}{''.join(f', a{i}' for i in range(len(params)))})"
    return f"{head} {{ {'' if ret == 'void' else 'return '}{call}; }}\n"


def export_table(cart: dict[str, tuple[str, list[str]]]) -> str:
    """--call wrappers for every cart export whose parameters a JS Number can feed."""
    out, rows = [], []
    for name, (_, params) in sorted(cart.items()):
        if any(t not in FROM_NUMBER for t in params):
            continue
        args = "".join(", " + FROM_NUMBER[t].format(i=i) for i, t in enumerate(params))
        out.append(
            f"static void x_{name}(struct w2c_env* e, const double* a) {{ (void)a; w2c_cart_{name}(&e->cart{args}); }}"
        )
        rows.append(f'    {{"{name.replace("__", "_")}", x_{name}}},')
    return "\n".join(out) + "\n\nconst host_export host_exports[] = {\n" + "\n".join(rows) + "\n    {0, 0},\n};\n"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--build", type=Path, required=True, help="build/host/<tag> (holds cart.h)")
    ap.add_argument("--cart", type=Path, required=True, help="the cart's .wasm")
    a = ap.parse_args()
    sys.path.insert(0, str(FPGA / "gen"))
    from memmap import SHARED_PAGES  # generated from machine/sdk/memmap.zig

    common = a.build.parent / "common"
    headers = {"machine": common / "machine.h", "rom": common / "rom.h", "cart": a.build / "cart.h"}
    wasms = {"machine": ROOT / "docs/machine-video.wasm", "rom": ROOT / "docs/rom.wasm", "cart": a.cart}
    link_check(wasms, SHARED_PAGES)
    exports = {who: decls(h, who) for who, h in headers.items()}
    rom_high = wasm_info.high_water(wasms["rom"].read_bytes()) or 0
    cart_high = wasm_info.high_water(a.cart.read_bytes()) or 0
    parts = [
        f"/* Generated by fpga/tools/host_gen.py for {a.cart.name}: do not edit. */",
        '#include <math.h>\n#include "host.h"\n',
        f"const uint32_t host_pages = {SHARED_PAGES}u;",
        f"const uint32_t host_rom_high = {rom_high:#x}u;",
        f"const uint32_t host_cart_high = {cart_high:#x}u;\n",
    ]
    for name, (ret, params, who) in sorted(imports(headers).items()):
        if name != "memory":
            parts.append(forwarder(name, ret, params, resolve(name, who, exports), exports))
    parts.append(export_table(exports["cart"]))
    (a.build / "env.c").write_text("\n".join(parts))


if __name__ == "__main__":
    main()
