"""Who draws the mouse pointer on the board: the firmware lays GEM's arrow over a cart that takes
the mouse (cycles/bcursor.c), unless the cart draws its own (`pub const drawsOwnPointer = true;`,
which exports drawsOwnPointer: apps/zig/demo_main.zig). The tracker (union_textracker) draws its
own mice, so it gets no arrow; GEM, ST Replay and SysInfo take the mouse and keep the arrow; a cart
without pointer() gets none. The question is host/input_bridge.c input_arrow over each cart's
generated tables (tools/host_gen.py), asked natively; a mutant that ignores the declaration is
caught."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
WABT = FPGA / ".tools/wabt"
CARTS = {"union_textracker": 0, "gem": 1, "st_replay": 1, "sysinfo": 1, "tutorial": 0}
CFLAGS = ["-std=c11", "-D_POSIX_C_SOURCE=200809L", "-O1", "-w", "-DWASM_RT_USE_MMAP=0"]


@pytest.fixture(scope="module", autouse=True)
def built() -> None:
    targets = [f"build/host/{c}/host" for c in CARTS]
    subprocess.run(["make", "-s", "memmap", *targets], cwd=FPGA, check=True, capture_output=True)


def arrow(tmp: Path, cart: str, bridge: Path | None = None) -> int:
    """input_arrow() over `cart`'s tables; `bridge` replaces host/input_bridge.c (a mutant)."""
    obj = FPGA / f"build/host/{cart}"
    dirs = (WABT / "include", WABT / "share/wabt/wasm2c", FPGA / "host", FPGA / "build/host/common", obj,
            FPGA / "glass/firmware", FPGA / "gen")  # fmt: skip
    inc = [f"-I{d}" for d in dirs]
    objs = [obj / n for n in ("env.o", "boot.o", "host_io.o", "in_glass_router.o", "cart.o")]
    objs.append(obj / "in_input_bridge.o")
    if bridge:
        objs[-1] = tmp / "bridge.o"
        subprocess.run(["clang", *CFLAGS, *inc, "-c", str(bridge), "-o", str(objs[-1])], check=True)
    common = [FPGA / f"build/host/common/{n}.o" for n in ("machine", "rom", "rt", "rt-mem", "rt-exc", "sha256")]
    exe = tmp / f"arrow_{cart}"
    subprocess.run(["clang", *CFLAGS, *inc, str(FPGA / "tests/arrow_main.c"), *map(str, objs + common),
                    "-lm", "-lpthread", "-o", str(exe)], check=True)  # fmt: skip
    out = subprocess.run([str(exe)], capture_output=True, text=True, check=True).stdout
    return int(out.split()[1])


@pytest.mark.parametrize("cart", list(CARTS))
def test_the_arrow_goes_over_a_mouse_cart_that_draws_no_pointer_of_its_own(tmp_path: Path, cart: str) -> None:
    assert arrow(tmp_path, cart) == CARTS[cart]


def test_a_firmware_that_ignores_the_declaration_is_caught(tmp_path: Path) -> None:
    src = (FPGA / "host/input_bridge.c").read_text()
    old = 'own |= !strcmp(x->name, "drawsOwnPointer");'
    assert src.count(old) == 1
    (tmp_path / "input_bridge.c").write_text(src.replace(old, "(void)x;"))
    assert arrow(tmp_path, "union_textracker", tmp_path / "input_bridge.c") == 1  # two pointers again: caught
