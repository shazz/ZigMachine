"""The board firmware's input path (cycles/binput.c -> host/input_bridge.c -> glass_input.c ->
the cart's exports), through the native host: ZM_GLASS_KEYS plays a key-FIFO script into the
same router, and the frame hashes say what the cart did with it. The reference is the browser's
own call (--call F:export:arg, docs/sealed-loader.js), and a mutant router must be caught."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
CART = "union_beatdis"  # owns the keyboard: SPACE answers its loader's question (key(32))
HOST = FPGA / f"build/host/{CART}/host"
KEY_DOWN = 0x1000000  # gen/glass_map.py
SPACE_DOWN, SPACE_UP = f"{KEY_DOWN | 0x20:x}", "20"


@pytest.fixture(scope="module", autouse=True)
def host() -> None:
    subprocess.run(["make", "-s", "memmap", f"build/host/{CART}/host"], cwd=FPGA, check=True, capture_output=True)


def hashes(binary: Path = HOST, keys: str = "", call: str = "") -> list[str]:
    env = {k: v for k, v in os.environ.items() if k != "ZM_GLASS_KEYS"}
    if keys:
        env["ZM_GLASS_KEYS"] = keys
    args = [str(binary), CART, "400", "100", *(["--call", call] if call else [])]
    out = subprocess.run(args, env=env, check=True, capture_output=True, text=True).stdout
    return [s["hash"] for s in json.loads(out)["samples"]]


def test_a_key_through_the_router_is_the_browsers_call() -> None:
    quiet = hashes()
    routed = hashes(keys=f"200:{SPACE_DOWN},201:{SPACE_UP}")
    assert routed == hashes(call="200:key:32")  # SPACE down -> key(32), as the browser calls it
    assert routed[0] == quiet[0] and routed[1:] != quiet[1:]  # nothing before frame 200, the screen after


def test_a_key_up_alone_and_an_unbound_export_do_nothing() -> None:
    quiet = hashes()
    assert hashes(keys=f"200:{SPACE_UP}") == quiet  # keyUp: this cart has no such export (NULL)
    assert hashes(keys="200:1000007") == quiet  # a key the screen ignores (code 7)


def test_a_router_that_drops_key_is_caught(tmp_path: Path) -> None:
    src = (FPGA / "host/input_bridge.c").read_text()
    old = "if (b->key) b->key(c, v);"
    assert src.count(old) == 1
    (tmp_path / "input_bridge.c").write_text(src.replace(old, "(void)b;"))
    obj = FPGA / f"build/host/{CART}"
    wabt = FPGA / ".tools/wabt"
    inc = [
        f"-I{p}"
        for p in (
            wabt / "include",
            wabt / "share/wabt/wasm2c",
            FPGA / "host",
            FPGA / "build/host/common",
            obj,
            FPGA / "glass/firmware",
            FPGA / "gen",
        )
    ]
    cflags = ["-std=c11", "-D_POSIX_C_SOURCE=200809L", "-O2", "-w", "-DWASM_RT_USE_MMAP=0"]
    subprocess.run(
        ["clang", *cflags, *inc, "-c", str(tmp_path / "input_bridge.c"), "-o", str(tmp_path / "in.o")], check=True
    )
    common = [FPGA / f"build/host/common/{n}.o" for n in ("machine", "rom", "rt", "rt-mem", "rt-exc", "sha256")]
    objs = [obj / n for n in ("host.o", "env.o", "boot.o", "host_io.o", "in_glass_router.o", "cart.o")]
    objs += sorted(obj.glob("bs_*.o"))  # host/main.c's --bootsec and --kos (Makefile HOST_BOOTSEC)
    mutant = tmp_path / "host"
    subprocess.run(
        ["clang", *map(str, objs), str(tmp_path / "in.o"), *map(str, common), "-lm", "-lpthread", "-o", str(mutant)],
        check=True,
    )
    assert hashes(mutant, keys=f"200:{SPACE_DOWN}") == hashes()  # the key never reached the cart: caught
