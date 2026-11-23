"""The board firmware's input path (cycles/binput.c -> host/input_bridge.c -> glass_input.c ->
the cart's exports), through the native host: ZM_GLASS_KEYS plays a key-FIFO script into the
same router, and the frame hashes say what the cart did with it. The reference is the browser's
own call (--call F:export:arg, site/js/sealed-loader.js), and a mutant router must be caught."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest
from host_make import lock_argv  # noqa: E402

FPGA = Path(__file__).resolve().parent.parent
CART = "union_beatdis"  # owns the keyboard: SPACE answers its loader's question (key(32))
HOST = FPGA / f"build/host/{CART}/host"
KEY_DOWN = 0x1000000  # gen/glass_map.py
SPACE_DOWN, SPACE_UP = f"{KEY_DOWN | 0x20:x}", "20"
P2 = 0xE100  # gen/glass_map.py KEY_P2_STATE: player 2's pad as a level word (R83)
FIRE, RIGHT = 0x20, 0x08  # JOY_FIRE, JOY_RIGHT


@pytest.fixture(scope="module", autouse=True)
def host() -> None:
    subprocess.run([*lock_argv(), "make", "-s", "memmap", f"build/host/{CART}/host"], cwd=FPGA, check=True, capture_output=True)


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


def build_mutant(tmp_path: Path, mutated: str) -> None:
    """Link the host with `mutated` as host/input_bridge.c: tmp_path/host."""
    (tmp_path / "input_bridge.c").write_text(mutated)
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
    common.append(FPGA / "build/host/common/kfs.a")  # C:'s writer, pulled in by main.c (Makefile: last)
    objs = [obj / n for n in ("host.o", "env.o", "boot.o", "host_io.o", "in_glass_router.o", "cart.o")]
    objs += sorted(obj.glob("bs_*.o"))  # host/main.c's --bootsec and --kos (Makefile HOST_BOOTSEC)
    mutant = tmp_path / "host"
    subprocess.run(
        ["clang", *map(str, objs), str(tmp_path / "in.o"), *map(str, common), "-lm", "-lpthread", "-o", str(mutant)],
        check=True,
    )


def test_a_router_that_drops_key_is_caught(tmp_path: Path) -> None:
    src = (FPGA / "host/input_bridge.c").read_text()
    old = "if (b->key) b->key(c, v);"
    assert src.count(old) == 1
    build_mutant(tmp_path, src.replace(old, "(void)b;"))
    assert hashes(tmp_path / "host", keys=f"200:{SPACE_DOWN}") == hashes()  # the key never reached the cart: caught


def test_player_2_is_merged_into_input_for_a_cart_without_input2() -> None:
    """union_beatdis has no input2: the second pad's word is the browser's input()/inputRelease()."""
    quiet = hashes()
    pad2 = hashes(keys=f"200:{P2 | FIRE:x},230:{P2:x}")
    assert pad2 == hashes(call="200:input:5,230:inputRelease:5")  # as the browser with one stick
    assert pad2 != quiet  # and it is not nothing (the cart answers fire)


def test_player_2_is_a_level_not_an_edge() -> None:
    """The word is the pad's whole state (a full FIFO may drop one): all clear with nothing held is no call, and the
    same word again is no second press. (REG_JOY, player 1, is a CSR the native host does not script.)"""
    assert hashes(keys=f"200:{P2:x}") == hashes()  # released with nothing held: nothing
    assert hashes(keys=f"200:{P2 | FIRE:x},201:{P2 | FIRE:x},230:{P2:x}") == hashes(call="200:input:5,230:inputRelease:5")


def test_a_router_that_forgets_the_merge_is_caught(tmp_path: Path) -> None:
    src = (FPGA / "host/input_bridge.c").read_text()
    old = "else glass_joy(old[0] | old[1], held[0] | held[1], call, e);"
    assert src.count(old) == 1
    build_mutant(tmp_path, src.replace(old, "(void)old;"))
    assert hashes(tmp_path / "host", keys=f"200:{P2 | FIRE:x},230:{P2:x}") == hashes()  # player 2 never reached input()
