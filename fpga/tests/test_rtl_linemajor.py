"""Line-major groups in the RTL compositor (rtl/video/zm_video_pass.v `hold` / `keep` / `nopfb`)
against the wasm machine, on the replay corpus of tests/test_rtl_video.py plus leonard (three
planes, no handler: a group the board's rule forms whole, cycles/bplanes.h).

The replay runs every enabled plane as one group (tests/tb/video_replay.h): each pass still gets
the state the machine consumed for it, so every multi-plane frame tests the RTL's side, whatever
its handlers; which planes may form a group on the board is tools/video_order.py's question
(tests/test_video_order_group.py). The PFB row after the group's last pass and the browser's
picture must match the machine's exactly, and a group must cost fewer clocks than plane-major.
The protocol mutants (a wrong bit on a held pass) always run; the RTL mutants are opt-in
(ZM_RTL_BREAK=1), one testbench build each.
"""

import json
import os
import re
import shutil
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_rtl_video as rv  # the corpus and its recording
import video_dump
import video_rtl

LEONARD = ("leonard", [300])
MULTI = ["leonard", "union_main", "tcb_colorshock", "union_l16"]
MULTI += ["s:" + s for s in ("alpha", "fullscreen", "layers", "medium", "overscan", "scroll", "worst")]
KEYS = rv.KEYS + ["leonard"]
MUTANTS = json.loads((FPGA / "tests" / "tb" / "video_lm_mutants.json").read_text())


def _source(key: str) -> tuple[Path, list[int]]:
    if key != LEONARD[0]:
        d, frames, _ = rv._source(key)
        return d, frames
    d = video_dump.OUT / key / "frames"
    if not all((d / f"f{f}.pfb").exists() for f in LEONARD[1]):
        d = video_dump.dump(key, LEONARD[1])
    return d, LEONARD[1]


@pytest.fixture(scope="session")
def tb() -> Path:
    assert (FPGA / "gen" / "memmap.vh").exists(), "run `make memmap` first"
    video_dump.memmap_header()
    return video_rtl.build_tb()


def _replay(exe: Path, key: str, args: tuple[str, ...], fuse: bool = False, timing: int | None = None):
    d, frames = _source(key)
    return video_rtl.replay(exe, d, frames, timing=timing, fuse=fuse, extra=args), frames


@pytest.mark.parametrize("fuse", [False, True], ids=["bg", "fused"])
@pytest.mark.parametrize("key", KEYS)
def test_a_line_major_group_matches_the_machine(tb: Path, key: str, fuse: bool) -> None:
    r, frames = _replay(tb, key, ("--line-major",), fuse)
    assert r.returncode == 0, r.stdout + r.stderr
    assert r.stdout.count("-> MATCH") == len(frames)


@pytest.mark.parametrize("key", MULTI)
def test_no_pfb_store_leaves_the_picture_exact(tb: Path, key: str) -> None:
    r, frames = _replay(tb, key, ("--line-major", "--nopfb"), True)
    assert r.returncode == 0, r.stdout + r.stderr
    assert r.stdout.count("-> MATCH") == len(frames)


def test_groups_of_several_planes_are_exercised(tb: Path) -> None:
    """Most of MULTI must really stack planes, and leonard's clear must fuse (the group fills)."""
    stacked = sum(bin(int((_source(k)[0] / f"f{_source(k)[1][0]}.meta").read_text().split()[1])).count("1") >= 2 for k in MULTI)
    assert stacked == len(MULTI)
    r, _ = _replay(tb, "leonard", ("--line-major",), True)
    assert "fused 1 ->" in r.stdout


def _frame_clocks(out: str) -> int:
    return sum(int(c) for c in re.findall(r"(\d+) clocks/frame", out))


@pytest.mark.parametrize("key", ["leonard", "union_main", "s:worst"])
def test_a_group_moves_fewer_rows(tb: Path, key: str) -> None:
    """Against a port with the HP's first-beat latency: the group loads and stores a line once."""
    pm, _ = _replay(tb, key, (), True, rv.HP_LATENCY)
    lm, _ = _replay(tb, key, ("--line-major",), True, rv.HP_LATENCY)
    nopfb, _ = _replay(tb, key, ("--line-major", "--nopfb"), True, rv.HP_LATENCY)
    for r in (pm, lm, nopfb):
        assert r.returncode == 0, r.stdout + r.stderr
    assert _frame_clocks(lm.stdout) < 0.8 * _frame_clocks(pm.stdout)
    assert _frame_clocks(nopfb.stdout) < _frame_clocks(lm.stdout)


@pytest.mark.parametrize(
    "args,fuse", [(("1",), True), (("2",), False), (("3",), True)], ids=["fill_on_held", "first_on_held", "nopfb_hashed"]
)
def test_a_wrong_bit_on_a_held_pass_is_caught(tb: Path, args: tuple[str, ...], fuse: bool) -> None:
    extra = ("--line-major", *(("--nopfb",) if args[0] == "3" else ()), "--lm-break", args[0])
    r, _ = _replay(tb, "union_main", extra, fuse)
    assert r.returncode != 0, r.stdout


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize("mutant", MUTANTS, ids=[m["id"] for m in MUTANTS])
def test_a_broken_line_major_rule_is_caught(tb: Path, mutant: dict) -> None:
    name, file, old, new, key = (mutant[k] for k in ("id", "file", "old", "new", "catch"))
    work = FPGA / "build" / "tests" / "mutants" / name
    shutil.rmtree(work, ignore_errors=True)
    shutil.copytree(video_rtl.RTL, work / "rtl")
    text = (work / "rtl" / file).read_text()
    assert text.count(old) == 1, f"{name}: the text to break is not unique in {file}"
    (work / "rtl" / file).write_text(text.replace(old, new))
    exe = video_rtl.build_tb(work / "rtl", work)
    args, fuse = tuple(mutant["args"]), bool(mutant.get("fuse"))
    if mutant.get("timing"):  # a mutant only the clocks can see: rows stored that need not be
        good, _ = _replay(tb, key, args, fuse, rv.HP_LATENCY)
        bad, _ = _replay(exe, key, args, fuse, rv.HP_LATENCY)
        assert _frame_clocks(bad.stdout) > _frame_clocks(good.stdout), f"{name} went unnoticed on {key}"
        return
    r, _ = _replay(exe, key, args, fuse)
    assert r.returncode != 0, f"{name} went unnoticed on {key}:\n{r.stdout}"
