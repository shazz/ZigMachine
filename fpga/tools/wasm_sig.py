"""The function signatures a wasm module exports and imports, in wasm2c's C types.

The system table (tools/sys_abi.py) is built from rom.wasm's and machine-video.wasm's
exports and checked against the carts' imports; reading the modules directly (not the
wasm2c headers) lets the gate check it without the fpga toolchain. A signature is
(return, [params]) with wasm2c's names: i32 -> u32, i64 -> u64, f32, f64, no result -> void.
"""

from __future__ import annotations

from wasm_info import _limits, _name, _sections, _skip_import_desc, _uleb

VALTYPE = {0x7F: "u32", 0x7E: "u64", 0x7D: "f32", 0x7C: "f64"}
Sig = tuple[str, list[str]]


def _valtypes(b: bytes, p: int) -> tuple[list[str], int]:
    n, p = _uleb(b, p)
    out = []
    for _ in range(n):
        if b[p] not in VALTYPE:
            raise ValueError(f"wasm_sig: value type {b[p]:#x} has no wasm2c scalar")
        out.append(VALTYPE[b[p]])
        p += 1
    return out, p


def _types(b: bytes, p: int) -> list[Sig]:
    n, p = _uleb(b, p)
    out = []
    for _ in range(n):
        if b[p] != 0x60:
            raise ValueError("wasm_sig: a type that is not a function type")
        params, p = _valtypes(b, p + 1)
        results, p = _valtypes(b, p)
        if len(results) > 1:
            raise ValueError("wasm_sig: a multi-value result")
        out.append((results[0] if results else "void", params))
    return out


def _imports(b: bytes, p: int, types: list[Sig]) -> tuple[dict[str, Sig], int]:
    """env.* function imports by name, and how many functions are imported in all."""
    n, p = _uleb(b, p)
    env, funcs = {}, 0
    for _ in range(n):
        mod, p = _name(b, p)
        field, p = _name(b, p)
        kind = b[p]
        if kind == 0:
            t, p = _uleb(b, p + 1)
            funcs += 1
            if mod == "env":
                env[field] = types[t]
        elif kind == 2:
            p = _limits(b, p + 1)[2]
        else:
            p = _skip_import_desc(b, kind, p + 1)
    return env, funcs


def signatures(b: bytes) -> tuple[dict[str, Sig], dict[str, Sig]]:
    """(function exports, env function imports), each name -> (return, params)."""
    types: list[Sig] = []
    imports: dict[str, Sig] = {}
    nimp, funcs, exports = 0, [], {}
    for sid, p in _sections(b):
        if sid == 1:
            types = _types(b, p)
        elif sid == 2:
            imports, nimp = _imports(b, p, types)
        elif sid == 3:
            n, p = _uleb(b, p)
            for _ in range(n):
                t, p = _uleb(b, p)
                funcs.append(types[t])
        elif sid == 7:
            n, p = _uleb(b, p)
            for _ in range(n):
                name, p = _name(b, p)
                kind, (idx, p) = b[p], _uleb(b, p + 1)
                if kind == 0 and idx >= nimp:
                    exports[name] = funcs[idx - nimp]
    return exports, imports
