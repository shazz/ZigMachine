"""The RTL video compositor (rtl/video/zm_video_comp.v) against the wasm machine.

Frames are recorded from real carts by tools/video_dump.py (vdump: the native
host plus a recorder) and from synthetic scenarios rendered by the real
machine-video (vsynth), then replayed through the RTL under CXXRTL in the
machine's own order (plane-major); the PFB row every pass leaves in memory must
match the machine's pixel for pixel, and the picture each frame builds must
match the browser's (tools/video_rtl.py, tools/video_mix.py; that model is
checked against Chrome in test_video_mix.py). Whole frames then go through the
double-buffered picture and the scanout and are checked on the wire.

Each corpus frame also states what it is there to exercise, checked from its
records (tools/video_cover.py), so a frame that stops exercising it fails here
instead of silently proving less. The break tests mutate one rule of the RTL
and require the replay to fail (opt-in: ZM_RTL_BREAK=1, about 7 minutes).
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import video_cover
import video_dump
import video_rtl

# (cart, frames, what those frames must exercise)
CARTS = [
    ("tutorial", [300], {"mode_normal", "palette_per_line"}),
    ("union_intro", [100], {"mode_normal"}),
    ("union_main", [300], {"layered", "mode_overscan", "flicker_hit", "palette_per_line", "alpha_partial"}),
    ("replicants_emlyn", [300], {"mode_overscan", "flicker_hit", "palette_per_line"}),
    ("gen4_3615", [300], {"mode_overscan", "palette_per_line", "alpha_zero"}),
    ("maxi", [300], {"mode_overscan", "flicker_hit"}),
    ("badflicker", [300], {"mode_overscan", "flicker_miss"}),
    ("res_switch", [300], {"mode_medium", "resolution_per_line"}),
    ("medium_overscan", [300], {"mode_medium_overscan"}),
    ("scroll", [300], {"mode_scroll"}),
    ("dhs_0pxl0reg", [300, 900], {"beam", "no_plane"}),
    ("tcb_colorshock", [300], {"layered", "mode_overscan", "palette_per_line"}),
    ("union_l16", [300], {"layered", "mode_overscan"}),
]
# (vsynth scenario, frames, what they must exercise)
SYNTH = [
    ("fullscreen", [1, 2], {"mode_fullscreen", "layered", "palette_per_line"}),
    ("scroll", [1, 2], {"mode_scroll", "hscroll_per_line", "palette_per_line"}),
    ("medium", [1, 2], {"mode_medium", "mode_medium_overscan", "resolution_per_line"}),
    ("overscan", [1, 2, 3], {"mode_overscan", "flicker_hit", "flicker_miss"}),
    ("beam", [1, 2], {"beam", "background_per_line"}),
    ("layers", [1, 2], {"mode_normal", "mode_scroll", "mode_medium", "mode_fullscreen", "background_per_line"}),
    ("alpha", [1, 2], {"layered", "alpha_partial", "alpha_zero", "mode_medium", "mode_overscan"}),
    ("bgalpha", [1, 2], {"no_plane", "alpha_partial", "background_per_line"}),
    ("worst", [1, 2], {"layered", "mode_medium_overscan", "beam", "alpha_partial"}),
]
# Multi-plane frames replayed again against a memory with the HP port's first-beat
# latency (CYCLES.md "Memory path": +24 clocks) and no stalls: the clock figures
# of rtl/video/README.md "Throughput", and the picture must still match.
TIMING = ["union_main", "tcb_colorshock", "s:layers", "s:alpha", "s:overscan", "s:medium", "s:worst"]
HP_LATENCY = 24
# One rule of the RTL broken at a time, and the dump that must catch it.
MUTANTS = json.loads((FPGA / "tests" / "tb" / "video_mutants.json").read_text())


def _source(key: str) -> tuple[Path, list[int], set[str]]:
    """A corpus entry's frames directory (recorded on first use), frames and coverage."""
    if key.startswith("s:"):
        name, frames, cover = next(s for s in SYNTH if s[0] == key[2:])
        d = video_dump.OUT / "_synth" / name
        return (d if (d / f"f{frames[-1]}.pfb").exists() else video_dump.synth(name)), frames, cover
    tag, frames, cover = next(c for c in CARTS if c[0] == key)
    d = video_dump.OUT / tag / "frames"
    if not all((d / f"f{f}.pfb").exists() for f in frames):
        d = video_dump.dump(tag, frames)
    return d, frames, cover


@pytest.fixture(scope="session")
def tb() -> Path:
    assert (FPGA / "gen" / "memmap.vh").exists(), "run `make memmap` first"
    video_dump.memmap_header()
    return video_rtl.build_tb()


KEYS = [c[0] for c in CARTS] + ["s:" + s[0] for s in SYNTH]


@pytest.mark.parametrize("key", KEYS)
def test_compositor_matches_the_machine_pixel_for_pixel(tb: Path, key: str) -> None:
    frames_dir, frames, cover = _source(key)
    for f in frames:
        missing = cover - video_cover.cover(frames_dir, f)
        assert not missing, f"{key} frame {f} no longer exercises {sorted(missing)}"
    result = video_rtl.replay(tb, frames_dir, frames)
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.count("-> MATCH") == len(frames)


@pytest.mark.parametrize("tag", [c[0] for c in CARTS])
def test_recorded_frames_are_the_reference_hosts(tag: str) -> None:
    """vdump must not perturb the machine: its PFBs hash like fpga/host's samples."""
    frames_dir, frames, _ = _source(tag)
    for f in frames:
        meta = (frames_dir / f"f{f}.meta").read_text().split()
        planes, pfb = int(meta[1]), (frames_dir / f"f{f}.pfb").read_bytes()
        size, h, at = video_cover.mm.PFB_BYTES, hashlib.sha256(), 1
        for p in range(video_cover.mm.NB_PLANES):
            if planes >> p & 1:
                h.update(pfb[at * size : (at + 1) * size])
                at += 1
            else:
                h.update(f"off{p}".encode())
        host = FPGA / "build" / "host" / tag / "host"
        out = subprocess.run([str(host), tag, str(f), str(f)], capture_output=True, text=True, check=True)
        assert json.loads(out.stdout)["samples"][0]["hash"] == h.hexdigest()


@pytest.mark.parametrize("key", TIMING)
def test_frames_against_hp_latency(tb: Path, key: str) -> None:
    frames_dir, frames, _ = _source(key)
    result = video_rtl.replay(tb, frames_dir, frames, timing=HP_LATENCY)
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.count("-> MATCH") == len(frames)


# Whole frames on the wire (zm_video_out), the compositor at 100 MHz (the board's
# sys clock) against the 40 MHz pixel clock: 5:2. dhs_0pxl0reg's two frames and
# s:worst's two go through both pictures of the double buffer.
WIRE = (5, 2)
WIRE_KEYS = ["union_main", "dhs_0pxl0reg", "s:worst"]


@pytest.fixture(scope="session")
def out_tb() -> Path:
    video_dump.memmap_header()
    return video_rtl.build_tb(out=True)


@pytest.mark.parametrize("key", WIRE_KEYS)
def test_frames_on_the_wire_are_the_browsers_picture(out_tb: Path, key: str) -> None:
    frames_dir, frames, _ = _source(key)
    result = video_rtl.wire(out_tb, WIRE, frames_dir, frames)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "-> MATCH" in result.stdout


def test_a_starved_scanout_fetch_underruns(out_tb: Path) -> None:
    """The compositor has no deadline any more; the scanout fetch does (a raster
    line). Given a beat every 16 clocks, 400 beats miss a 5,280-clock line: the
    scanout must say so."""
    frames_dir, _, _ = _source("union_main")
    result = video_rtl.wire(out_tb, WIRE, frames_dir, [300], starve=16)
    assert result.returncode != 0
    assert "underrun 1" in result.stdout


# One testbench build per mutant: opt-in, so `make test` on a shared box stays light.
@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize("mutant", MUTANTS, ids=[m["id"] for m in MUTANTS])
def test_a_broken_rule_is_caught(mutant: dict[str, str]) -> None:
    name, file, old, new, key = (mutant[k] for k in ("id", "file", "old", "new", "catch"))
    # Under fpga/build, not tmp: yowasp's Yosys is wasm and sees only this tree.
    work = FPGA / "build" / "tests" / "mutants" / name
    shutil.rmtree(work, ignore_errors=True)
    rtl = work / "rtl"
    shutil.copytree(video_rtl.RTL, rtl)
    text = (rtl / file).read_text()
    assert text.count(old) == 1, f"{name}: the text to break is not unique in {file}"
    (rtl / file).write_text(text.replace(old, new))
    video_dump.memmap_header()
    on_wire = mutant.get("tb") == "out"
    exe = video_rtl.build_tb(rtl, work, out=on_wire)
    frames_dir, frames, _ = _source(key)
    if on_wire:
        result = video_rtl.wire(exe, WIRE, frames_dir, frames)
    else:
        result = video_rtl.replay(exe, frames_dir, frames, timing=HP_LATENCY if mutant.get("timing") else None)
    assert result.returncode != 0, f"{name} went unnoticed on {key}:\n{result.stdout}"
