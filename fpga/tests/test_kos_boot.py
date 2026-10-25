"""KOS's power-on (docs/ZIGTOS_BOOT.md: KOS, the KESTREL Operating System, is its "ZigTOS"): the
native host's --kos (host/kos_host.c) equals scene_hash.mjs --kos (apps/scene_hash_kos.mjs, the
browser's steps) frame for frame, for every kind of drive A:

- empty: the ROM's POST (rom/kos/kos.zig), then the desktop, whose FLOPPY says the drive is empty;
- a data disk (ST Replay's): the POST, then the desktop over it: the floppy opens on its listing,
  and BOOT.WSM double-clicked is request 3 in both;
- an executable boot sector handing over to the OS (sysinfo's "No virus"), then the desktop;
- an executable boot sector chainloading its cart (replicants_emlyn's crew note);
- a bootable disk (the tutorial's): its own cart, after the POST.

Every run is checked to differ where the drive differs (the POST alone, the floppy's window), so
a host that ignored the drive would fail. The bootable case also checks scene_hash.mjs refuses a
cart that is not the disk's.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
DOCS = ROOT / "docs"
POST = 180  # rom/kos/kos.zig POST_FRAMES
# GEM's floppy (40,30) clicked and double-clicked, then BOOT.WSM (75,65) double-clicked, after the POST.
SCRIPT = [(5, 40, 30, 0), (10, 40, 30, 1), (11, 40, 30, 0), (20, 40, 30, 2), (21, 40, 30, 0),
          (30, 75, 65, 0), (32, 75, 65, 2), (33, 75, 65, 0)]  # fmt: skip


def calls(after: int) -> list[str]:
    return [a for f, x, y, b in SCRIPT for a in ("--call", f"{after + f}:pointer:{x},{y},{b}")]


def host(cart: str) -> Path:
    subprocess.run(["make", "-s", "memmap", f"build/host/{cart}/host"], cwd=FPGA, check=True, capture_output=True)
    return FPGA / f"build/host/{cart}/host"


def both(cart: str, frames: int, every: int, *args: str) -> tuple[list[str], str, str]:
    """The native host's and scene_hash.mjs's samples (equal, or the test fails), and both stderrs."""
    nat = subprocess.run([str(host(cart)), cart, str(frames), str(every), *args], cwd=ROOT, capture_output=True, text=True)
    js = subprocess.run(["node", "apps/scene_hash.mjs", f"docs/demo-{cart}.wasm", str(frames), str(every), *args],
                        cwd=ROOT, capture_output=True, text=True)  # fmt: skip
    assert nat.returncode == 0 and js.returncode == 0, nat.stderr + js.stderr
    hn = [s["hash"] for s in json.loads(nat.stdout)["samples"]]
    hj = [s["hash"] for s in json.loads(js.stdout)["samples"]]
    assert hn == hj, f"first difference at sample {next(i for i, (a, b) in enumerate(zip(hn, hj)) if a != b)}"
    return hn, nat.stderr, js.stderr


def test_empty_drive_and_data_disk_boot_the_desktop_after_the_post() -> None:
    n, every = POST + 40, 5
    empty, _, _ = both("gem", n, every, "--kos", "none", *calls(POST))
    data, nerr, jerr = both("gem", n, every, "--kos", str(DOCS / "demo-st_replay.zmd"), *calls(POST))
    post = POST // every
    assert len(set(empty[: post - 1])) > 1  # the POST animates (its memory test counts)
    assert empty[:post] == data[:post]  # the same POST whatever the drive holds
    assert empty[post] == data[post]  # the same desktop until the floppy opens
    assert empty[-1] != data[-1]  # "Drive A: is empty" against ST Replay's listing
    assert f'cart request 3 "BOOT.WSM" (on the disk) at frame {POST + 32}' in nerr
    assert 'cart request 3 "BOOT.WSM" (on the disk)' in jerr


def test_post_frames_zero_boots_drive_a_at_once() -> None:
    none, _, _ = both("gem", 10, 1, "--kos", "none", "--post-frames", "0")
    post, _, _ = both("gem", 10, 1, "--kos", "none", "--post-frames", "3")
    assert none[:7] == post[3:]  # the desktop, three frames later


def test_a_boot_sector_runs_after_the_post_then_the_desktop_or_its_cart() -> None:
    sysinfo, _, _ = both("gem", 150, 10, "--kos", str(DOCS / "demo-sysinfo.zmd"), "--post-frames", "4")
    plain, _, _ = both("gem", 150, 10, "--kos", "none", "--post-frames", "4")
    assert sysinfo[1] != plain[1] and sysinfo[-1] == plain[-1]  # "No virus", then the same desktop
    emlyn, _, _ = both("replicants_emlyn", 300, 10, "--kos", str(DOCS / "demo-replicants_emlyn.zmd"), "--post-frames", "4")
    assert len(set(emlyn[:23])) == 1 and emlyn[-1] != emlyn[0]  # the crew note held, then the screen


def test_a_bootable_disk_boots_its_own_cart_and_no_other() -> None:
    tut, _, _ = both("tutorial", 40, 2, "--kos", str(DOCS / "demo-tutorial.zmd"), "--post-frames", "6")
    assert tut[2] != tut[3]  # the POST's last frame, then the cart's first
    wrong = subprocess.run(["node", "apps/scene_hash.mjs", "docs/demo-gem.wasm", "5", "1", "--kos",
                            str(DOCS / "demo-tutorial.zmd"), "--post-frames", "1"], cwd=ROOT, capture_output=True, text=True)  # fmt: skip
    assert wrong.returncode != 0 and "the cart given is not the disk's" in wrong.stderr


@pytest.mark.parametrize("args", [["--post-frames", "3"], ["--kos", str(DOCS / "nope.zmd")]])
def test_bad_kos_arguments_are_refused(args: list[str]) -> None:
    js = subprocess.run(["node", "apps/scene_hash.mjs", "docs/demo-gem.wasm", "5", "1", *args], cwd=ROOT,
                        capture_output=True, text=True)  # fmt: skip
    assert js.returncode != 0
