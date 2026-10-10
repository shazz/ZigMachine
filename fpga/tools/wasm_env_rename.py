"""Rename a wasm module's import module `env` to another three-letter name.

    uv run python tools/wasm_env_rename.py <in.wasm> <name> <out.wasm>

wasm2c names every import `w2c_<module>_<field>` and every host links one
definition of each. The native host (host/) and the board firmware (cycles/)
already serve `env.*` for machine-video, rom and the cart, with ONE `env.memory`.
The audio modules (demo-audio.wasm, machine-audio.wasm) import their own,
separate memory and the machine* audio calls from `env` too, so they are
translated after this rename (to `aud`): their imports become `w2c_aud_*`, served
by host/audio*.c, and the two memories never meet. Same length, so no size or
offset in the module changes; only the import section's module-name bytes do.
"""

import sys
from pathlib import Path

from wasm_info import _sections, _uleb

IMPORT_SECTION = 2


def _skip_desc(b: bytes, p: int) -> int:
    """Past one import's description (func / table / memory / global / tag)."""
    kind, p = b[p], p + 1
    if kind in (0, 4):  # func: type index; tag: attribute + type index
        if kind == 4:
            p += 1
        return _uleb(b, p)[1]
    if kind == 1:  # table: reftype then limits
        p += 1
    if kind in (1, 2):  # limits: flags, min [, max]
        flags, p = b[p], p + 1
        p = _uleb(b, p)[1]
        return _uleb(b, p)[1] if flags & 1 else p
    if kind == 3:  # global: valtype, mutability
        return p + 2
    raise ValueError(f"unknown import kind {kind}")


def rename(wasm: bytes, old: bytes, new: bytes) -> tuple[bytes, int]:
    """`wasm` with every import from module `old` re-homed to `new`, and how many."""
    if len(old) != len(new):
        raise ValueError("the names must have the same length")
    out, count = bytearray(wasm), 0
    for sid, p in _sections(wasm):
        if sid != IMPORT_SECTION:
            continue
        n, p = _uleb(wasm, p)
        for _ in range(n):
            mlen, p = _uleb(wasm, p)
            if wasm[p : p + mlen] == old:
                out[p : p + mlen], count = new, count + 1
            p += mlen
            flen, p = _uleb(wasm, p)
            p = _skip_desc(wasm, p + flen)
    return bytes(out), count


def main() -> None:
    src, name, dst = sys.argv[1:4]
    data, count = rename(Path(src).read_bytes(), b"env", name.encode())
    if count == 0:
        sys.exit(f"wasm_env_rename: {src} imports nothing from env")
    Path(dst).write_bytes(data)


if __name__ == "__main__":
    main()
