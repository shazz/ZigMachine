"""The shelf's ZX0 tools and its program finder (tools/glass_shelf.py): the repo's own packer and
the machine's own depacker, each built once into build/glass/, and the cart a data disk's program is."""

from __future__ import annotations

import subprocess
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent


def zx0pack() -> Path:
    """The repo's own packer, built once into build/glass/."""
    exe = FPGA / "build/glass/zx0pack"
    if not exe.exists():
        exe.parent.mkdir(parents=True, exist_ok=True)
        zig = Path.home() / ".local/zig/0.16.0/zig"
        subprocess.run([zig, "build-exe", "-OReleaseFast", "--dep", "zx0_pack", f"-Mroot={ROOT}/tools/zx0pack/main.zig",
                        f"-Mzx0_pack={ROOT}/libs/zig/depackers/zx0_pack.zig", f"-femit-bin={exe}"],
                       check=True, cwd=exe.parent)  # fmt: skip
    return exe


def zx0unpack() -> Path:
    """The machine's own depacker as a tool (tools/zx0unpack.zig), built once into build/glass/."""
    exe = FPGA / "build/glass/zx0unpack"
    if not exe.exists():
        exe.parent.mkdir(parents=True, exist_ok=True)
        zig = Path.home() / ".local/zig/0.16.0/zig"
        subprocess.run([zig, "build-exe", "-OReleaseFast", "--dep", "zx0", f"-Mroot={FPGA}/tools/zx0unpack.zig",
                        f"-Mzx0={ROOT}/libs/zig/depackers/zx0.zig", f"-femit-bin={exe}"],
                       check=True, cwd=exe.parent)  # fmt: skip
    return exe


def program_cart(packed: bytes, work: Path) -> str | None:
    """The cart whose docs/demo-<cart>.wasm a disk's program is (ZX0-packed or raw), or None."""
    raw = packed
    if packed[:4] == b"ZX0!":
        (work / "prog.zx0").write_bytes(packed)
        try:
            subprocess.run([zx0unpack(), work / "prog.zx0", work / "prog.wasm"], check=True, capture_output=True)
            raw = (work / "prog.wasm").read_bytes()
        finally:  # `work` is the card's staging directory: leave nothing behind on it
            (work / "prog.zx0").unlink(missing_ok=True)
            (work / "prog.wasm").unlink(missing_ok=True)
    size = len(raw)
    hits = [
        w for w in sorted((ROOT / "docs").glob("demo-*.wasm")) if w.stat().st_size == size and w.read_bytes() == raw
    ]
    return hits[0].name.removeprefix("demo-").removesuffix(".wasm") if hits else None


def stage_by_hash(carts: list[str], image_path, problem, dest: Path) -> list[tuple[str, str]]:
    """zigmachine/progs/by-hash/<sha256 of docs/demo-<cart>.wasm>.rv32: each cart's board image,
    ZX0-packed, named by what its wasm IS, for a program GEM finds on a real floppy (KOS,
    docs/KOS_FAT.md; glass/src/app_floppy_prog.zig hashes the program the same way)."""
    import hashlib

    rows = []
    for cart in carts:
        wasm = ROOT / "docs" / f"demo-{cart}.wasm"
        if not wasm.exists() or problem(cart):
            continue
        name = hashlib.sha256(wasm.read_bytes()).hexdigest() + ".rv32"
        (dest / "progs" / "by-hash").mkdir(parents=True, exist_ok=True)
        subprocess.run([zx0pack(), image_path(cart), dest / "progs" / "by-hash" / name], check=True, capture_output=True)
        rows.append((f"zigmachine/progs/by-hash/{name}", f"{cart} (a program on a real floppy)"))
    return rows
