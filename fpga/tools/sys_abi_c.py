"""C for the KESTREL system table, from fpga/cycles/sys_abi.txt (tools/sys_abi.py):

    uv run python tools/sys_abi_c.py header gen/zm_sys_abi.h      # both images: indices, the table, the cart header
    uv run python tools/sys_abi_c.py cart-rt gen/zm_cart_rt.c     # the cart image's runtime: every call to the table

Refuses a sys_abi.txt that is not today's layout (sys_abi.py --check), so no image is
built against a stale table. The system's half (the table's initialiser, the wrappers it
points at) is tools/host_split.py's, next to the env it resolves.
"""

from __future__ import annotations

import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
from sys_abi import MANIFEST, current  # after the path insert
from sys_abi_layout import HEADER, NORETURN, RUNTIME, TYPES
from sys_abi_manifest import Manifest, check, parse

FORWARD = ["w2c_env", "w2c_cart", "host_song_bridge", "host_input_bridge", "host_disk_app_bridge", "host_export",
           "zm_song"]  # fmt: skip


def checked(path: Path = MANIFEST) -> Manifest:
    m = parse(path.read_text())
    if errs := check(m, current(m)):
        raise SystemExit("sys_abi_c: " + "; ".join(errs))
    return m


def env_rows(m: Manifest) -> list[tuple[str, str, str, list[str]]]:
    """(name, owner, ret, params) per env entry, in table order."""
    out = []
    for ln in m.body:
        if ln.startswith("env "):
            _, name, owner, sig = ln.split()
            ret, params = sig[: sig.index("(")], sig[sig.index("(") + 1 : -1]
            out.append((name, owner, ret, [p for p in params.split(",") if p]))
    return out


def consts(m: Manifest) -> dict[str, int]:
    return {ln.split()[1]: int(ln.split()[2], 0) for ln in m.body if ln.startswith("const ")}


def header(m: Manifest) -> str:
    major, minor = m.version
    c = consts(m)
    idx = [f"ZM_RT_{s}" for s, *_ in RUNTIME] + [f"ZM_ENV_{n}" for n, *_ in env_rows(m)]
    fields = "\n".join(f"    {t.format(n)};" for n, t in HEADER)
    table = TYPES[0][1].strip("{}").replace("; ", ";\n    ")
    return (
        f"""/* GENERATED from fpga/cycles/sys_abi.txt by fpga/tools/sys_abi_c.py. Do not edit.
 * The KESTREL system table (decisions.md 2026-10-15): the system image hands zm_sys_table to
 * the cart image's bind(); the cart image starts with zm_cart_hdr at ZM_CART_IMG_AT. */
#ifndef ZM_SYS_ABI_H
#define ZM_SYS_ABI_H

#include <stddef.h>
#include <stdint.h>

#define ZM_SYS_ABI_MAJOR {major}u
#define ZM_SYS_ABI_MINOR {minor}u
#define ZM_SYS_ABI_VERSION ((ZM_SYS_ABI_MAJOR << 16) | ZM_SYS_ABI_MINOR)
"""
        + "".join(f"#define ZM_{k} {v:#x}u\n" for k, v in c.items())
        + "\n"
        + "".join(f"struct {f};\n" for f in FORWARD)
        + f"""typedef void (*zm_fn)(void);

enum {{
    {",\n    ".join(idx)},
    ZM_SYS_COUNT
}};

typedef struct zm_sys_table {{
    {table}
}} zm_sys_table;

typedef struct zm_cart_hdr {{
{fields}
}} zm_cart_hdr;

_Static_assert(offsetof(zm_cart_hdr, version) == ZM_CART_HDR_VERSION_AT, "glass reads the version there");
_Static_assert(offsetof(zm_cart_hdr, bss_end) == ZM_CART_HDR_BSS_END_AT, "glass reads the .bss end there");

extern const zm_cart_hdr* zm_cart;  /* the system's: the cart image's header (cycles/bsys.c) */
extern const zm_sys_table* zm_sys;  /* the cart's: the system's table, from bind() (zm_cart_rt.c) */

#endif
"""
    )


def forwarder(name: str, ret: str, params: list[str], index: str, noreturn: bool = False) -> str:
    """`ret name(params)` calling table entry `index` with the same arguments."""
    args = ", ".join(f"{t} a{i}" for i, t in enumerate(params)) or "void"
    call = f"(({ret} (*)({', '.join(params) or 'void'}))zm_sys->fn[{index}])({', '.join(f'a{i}' for i in range(len(params)))})"
    if noreturn:
        return f"{ret} {name}({args}) {{ {call}; __builtin_unreachable(); }}\n"
    return f"{ret} {name}({args}) {{ {'' if ret == 'void' else 'return '}{call}; }}\n"


def cart_rt(m: Manifest) -> str:
    rows = [forwarder(s, r, p, f"ZM_RT_{s}", s in NORETURN) for s, r, p, cart in RUNTIME if cart]
    return (
        "/* GENERATED from fpga/cycles/sys_abi.txt by fpga/tools/sys_abi_c.py. Do not edit.\n"
        " * The cart image's runtime (decisions.md 2026-10-15): it links no libc, so wasm2c's runtime,\n"
        " * libc and libm calls go to the system's own through the table bind() received. */\n"
        '#include <math.h>\n#include <string.h>\n#include "wasm-rt.h"\n#include "zm_sys_abi.h"\n\n'
        f"/* version {m.version[0]}.{m.version[1]} */\n"
        "const zm_sys_table* zm_sys;\n"
        "/* The cart's own depth counter: the system's is TLS (built with -D_Thread_local=, ADR). */\n"
        "uint32_t wasm_rt_call_stack_depth;\n\n" + "".join(rows)
    )


def main() -> None:
    kind, out = sys.argv[1], Path(sys.argv[2])
    m = checked()
    text = {"header": header, "cart-rt": cart_rt}[kind](m)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text)


if __name__ == "__main__":
    main()
