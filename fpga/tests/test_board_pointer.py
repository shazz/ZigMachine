"""The board firmware's mouse path (cycles/binput.c -> host/input_bridge.c -> glass_pointer() ->
the cart's pointer()), through the native host on the GEM desktop: ZM_GLASS_POINTER plays the
ARM's REG_POINTER writes into the same poll, and the frame hashes say what GEM did with them.
The reference is the browser's own call (--call F:pointer:x,y,buttons, docs/sealed-loader.js),
and a mutant router must be caught."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
CART = "gem"  # the desktop boots in LOW res: pointer() halves x (gem_desktop.zig)
HOST = FPGA / f"build/host/{CART}/host"
X, Y = 40, 30  # physical-visible coords (PTR_*): the FLOPPY DISK icon


def word(x: int, y: int, buttons: int) -> str:
    """What the ARM writes to REG_POINTER (fpga/glass/src/map.zig PTR_*), as the script's hex."""
    return f"{x | y << 10 | buttons << 20:x}"


# Move onto the floppy, click it (selects), then the browser's double-click pulse (opens: no disk,
# so GEM's "Drive A: is empty" alert, the board's state until it has a disk).
SCRIPT = [(5, 0), (10, 1), (11, 0), (20, 2), (21, 0)]
ROUTED = ",".join(f"{f}:{word(X, Y, b)}" for f, b in SCRIPT)
CALLS = [f"{f}:pointer:{X},{Y},{b}" for f, b in SCRIPT]


@pytest.fixture(scope="module", autouse=True)
def host() -> None:
    subprocess.run(["make", "-s", "memmap", f"build/host/{CART}/host"], cwd=FPGA, check=True, capture_output=True)


def run(binary: Path = HOST, pointer: str = "", calls: list[str] | None = None) -> subprocess.CompletedProcess[str]:
    env = {k: v for k, v in os.environ.items() if k not in ("ZM_GLASS_POINTER", "ZM_GLASS_KEYS")}
    if pointer:
        env["ZM_GLASS_POINTER"] = pointer
    args = [str(binary), CART, "40", "5"]
    for c in calls or []:
        args += ["--call", c]
    return subprocess.run(args, env=env, capture_output=True, text=True, check=False)


def hashes(binary: Path = HOST, pointer: str = "", calls: list[str] | None = None) -> list[str]:
    out = run(binary, pointer, calls)
    assert out.returncode == 0, out.stderr
    return [s["hash"] for s in json.loads(out.stdout)["samples"]]


def test_the_routed_mouse_is_the_browsers_pointer_calls() -> None:
    quiet = hashes()
    routed = hashes(pointer=ROUTED)
    assert routed == hashes(calls=CALLS)
    assert routed[0] == quiet[0]  # frame 5: a move alone draws nothing (the browser draws the cursor)
    assert routed[1] != quiet[1]  # frame 10: the click selected the icon
    assert routed[3] not in (quiet[3], routed[1])  # frame 20: the double-click opened the drive's alert


def test_a_move_alone_changes_nothing_and_a_bad_script_is_refused() -> None:
    assert hashes(pointer=f"5:{word(X, Y, 0)},30:{word(600, 150, 0)}") == hashes()
    bad = run(pointer="5:zz")
    assert bad.returncode == 2 and "bad ZM_GLASS_POINTER" in bad.stderr


def mutant(tmp_path: Path, src: str, old: str, new: str) -> Path:
    """The host with one router source mutated: `src` is input_bridge.c or glass_input.c."""
    path = FPGA / ("host" if src == "input_bridge.c" else "glass/firmware") / src
    text = path.read_text()
    assert text.count(old) == 1, old
    (tmp_path / src).write_text(text.replace(old, new))
    # glass_router.c #includes glass_input.c: from tmp_path, its quoted include finds the mutant.
    unit = tmp_path / ("input_bridge.c" if src == "input_bridge.c" else "glass_router.c")
    if src != "input_bridge.c":
        shutil.copy(FPGA / "host/glass_router.c", unit)
    obj = FPGA / f"build/host/{CART}"
    wabt = FPGA / ".tools/wabt"
    dirs = (wabt / "include", wabt / "share/wabt/wasm2c", FPGA / "host", FPGA / "build/host/common", obj,
            FPGA / "glass/firmware", FPGA / "gen")  # fmt: skip
    cflags = ["-std=c11", "-D_POSIX_C_SOURCE=200809L", "-O2", "-w", "-DWASM_RT_USE_MMAP=0"]
    subprocess.run(["clang", *cflags, *(f"-I{d}" for d in dirs), "-c", str(unit), "-o", str(tmp_path / "m.o")],
                   check=True)  # fmt: skip
    keep = "in_glass_router.o" if src == "input_bridge.c" else "in_input_bridge.o"
    objs = [obj / n for n in ("host.o", "env.o", "boot.o", "host_io.o", keep, "cart.o")]
    objs += sorted(obj.glob("bs_*.o"))  # host/main.c's --bootsec and --kos (Makefile HOST_BOOTSEC)
    common = [FPGA / f"build/host/common/{n}.o" for n in ("machine", "rom", "rt", "rt-mem", "rt-exc", "sha256")]
    exe = tmp_path / "host"
    subprocess.run(["clang", *map(str, objs), str(tmp_path / "m.o"), *map(str, common), "-lm", "-lpthread",
                    "-o", str(exe)], check=True)  # fmt: skip
    return exe


def test_a_router_that_drops_the_pointer_is_caught(tmp_path: Path) -> None:
    old = "host_input.pointer((w2c_cart*)ctx, (uint32_t)x, (uint32_t)y, buttons);"
    exe = mutant(tmp_path, "input_bridge.c", old, "(void)ctx, (void)x, (void)y, (void)buttons;")
    assert hashes(exe, pointer=ROUTED) == hashes()  # the clicks never reached GEM: caught


def test_a_router_that_swaps_x_and_y_is_caught(tmp_path: Path) -> None:
    old = "pointer(ctx, x, y, (ptr >> PTR_BTN_SHIFT) & PTR_BTN_MASK);"
    exe = mutant(tmp_path, "glass_input.c", old, "pointer(ctx, y, x, (ptr >> PTR_BTN_SHIFT) & PTR_BTN_MASK);")
    assert hashes(exe, pointer=ROUTED) != hashes(pointer=ROUTED)  # the click lands off the icon: caught
