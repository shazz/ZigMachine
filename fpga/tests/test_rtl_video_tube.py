"""The tube: what a picture pixel no plane covers shows, on the board and in the browser.

The browser stacks its plane canvases on the page's tube (docs/css/crt.css .container) and
the mixer folds every line's first canvas over the same tube (rtl/video/zm_video_mix.v).
machine/video.zig REPLACES PFB pixels with a plane's palette entry, so wherever every
enabled plane draws its transparent colour (alpha 0) the picture is the tube, not
BACKGROUND, even over an opaque background. It was #121010: black under the CSS veil, a
dark grey box inside black borders on the board's HDMI (ancool, Matt 2026-10-20). Since
then the tube is black on both machines, which must match pixel for pixel.

Here: the oracle shows the old grey and the black on ancool; the RTL built as the board
builds it (soc/zm_video_pipe.py TUBE_BOARD) matches the browser's model pass by pass and on
the wire; a grey-tube build is told apart (the replay does see the tube), and the break
tests (ZM_RTL_BREAK=1) drop the parameter on its way down to the mixer of a grey build.
"""

import os
import shutil
import subprocess
from pathlib import Path

import pytest
import test_rtl_video as rv  # the corpus and its recording

video_rtl, video_dump, video_mix = rv.video_rtl, rv.video_dump, rv.video_rtl.video_mix
BLACK_BGR = 0x000000  # TUBE_BOARD = TUBE_BROWSER
GREY_BGR, GREY_RGB = 0x101012, "121010"  # the old tube, {B, G, R} and RRGGBB
# Frames whose picture has pixels every canvas leaves at alpha 0.
KEYS = ["ancool", "gen4_3615"]
W, H = 800, 280
BYTES = W * H * 4


def _board_frames(key: str) -> tuple[Path, list[int]]:
    """The corpus frames, linked into a directory of their own: the black-tube .mix
    must not overwrite the browser's one beside the recording, which other tests replay."""
    src, frames, _ = rv._source(key)
    d = video_dump.OUT / "_board_tube" / key
    d.mkdir(parents=True, exist_ok=True)
    for f in frames:
        for ext in ("mem", "meta", "pfb", "rec"):
            link = d / f"f{f}.{ext}"
            if not link.exists():
                link.symlink_to(src / f"f{f}.{ext}")
    return d, frames


def _bare(frames_dir: Path, frame: int) -> list[int]:
    """Pixel indices where every drawn canvas is alpha 0 (vmix's canvases)."""
    planes = int((frames_dir / f"f{frame}.meta").read_text().split()[1])
    pfb = (frames_dir / f"f{frame}.pfb").read_bytes()
    layers = [pfb[(1 + k) * BYTES : (2 + k) * BYTES] for k in range(bin(planes).count("1"))]
    return [i for i in range(W * H) if all(c[i * 4 + 3] == 0 for c in layers)]


def test_ancool_shows_the_tube_where_no_plane_draws() -> None:
    """The bug, in the oracle: grey over the old tube inside black borders, black over
    today's (the default). The borders are the opaque BACKGROUND either way."""
    d, frames = _board_frames("ancool")
    f = frames[0]
    bare = _bare(d, f)
    assert len(bare) > 100_000, "ancool's content area should be mostly empty"
    for tube, want in ((GREY_RGB, (0x12, 0x10, 0x10)), (None, (0, 0, 0))):
        video_mix.mix(d, [f], tube=tube)
        pic = (d / f"f{f}.mix").read_bytes()
        assert all(tuple(pic[i * 3 : i * 3 + 3]) == want for i in bare), f"tube {tube}"
        assert tuple(pic[(10 * W + 10) * 3 : (10 * W + 10) * 3 + 3]) == (0, 0, 0)  # a border pixel


def test_vmix_refuses_a_malformed_tube() -> None:
    d, frames = _board_frames("ancool")
    exe = video_mix.build_vmix()
    out = subprocess.run([str(exe), "--tube", "12101", "frame", str(d), str(frames[0])], check=False)
    assert out.returncode == 2


@pytest.fixture(scope="module")
def board_tb() -> Path:
    video_dump.memmap_header()
    return video_rtl.build_tb(tube=BLACK_BGR)


@pytest.fixture(scope="module")
def grey_tb() -> Path:
    video_dump.memmap_header()
    return video_rtl.build_tb(tube=GREY_BGR)


@pytest.fixture(scope="module")
def board_out_tb() -> Path:
    video_dump.memmap_header()
    return video_rtl.build_tb(out=True, tube=BLACK_BGR)


@pytest.mark.parametrize("key", KEYS)
def test_the_board_compositor_is_the_browsers_picture(board_tb: Path, key: str) -> None:
    """The board's build against the browser's model (default tube): pixel for pixel."""
    d, frames = _board_frames(key)
    result = video_rtl.replay(board_tb, d, frames)
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.count("-> MATCH") == len(frames)


def test_a_grey_tube_build_is_told_apart(board_tb: Path, grey_tb: Path) -> None:
    """The control: the replay sees the tube. A grey build matches the grey picture and
    not the black one; the board's build does not match the grey picture."""
    d, frames = _board_frames("ancool")
    assert video_rtl.replay(grey_tb, d, frames, tube=GREY_RGB).returncode == 0
    assert video_rtl.replay(grey_tb, d, frames).returncode != 0
    assert video_rtl.replay(board_tb, d, frames, tube=GREY_RGB).returncode != 0


def test_the_board_picture_on_the_wire_is_black(board_out_tb: Path) -> None:
    d, frames = _board_frames("ancool")
    result = video_rtl.wire(board_out_tb, rv.WIRE, d, frames)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "-> MATCH" in result.stdout


# The parameter dropped on its way down (the board's SoC sets it on zm_video_out). With the
# defaults black too, only a grey build shows the drop: the mixer then folds over black.
MUTANTS = [
    ("tube_not_into_mix", "zm_video_comp.v", "zm_video_mix #(.TUBE(TUBE)) u_mix", "zm_video_mix u_mix", False),
    ("tube_not_into_comp", "zm_video_out.v", "zm_video_comp #(.TUBE(TUBE)) u_comp", "zm_video_comp u_comp", True),
]


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize("mutant", MUTANTS, ids=[m[0] for m in MUTANTS])
def test_a_dropped_tube_is_caught(mutant: tuple[str, str, str, str, bool]) -> None:
    name, file, old, new, on_wire = mutant
    work = video_rtl.FPGA / "build" / "tests" / "mutants" / name
    shutil.rmtree(work, ignore_errors=True)
    rtl = work / "rtl"
    shutil.copytree(video_rtl.RTL, rtl)
    text = (rtl / file).read_text()
    assert text.count(old) == 1, f"{name}: the text to break is not unique in {file}"
    (rtl / file).write_text(text.replace(old, new))
    video_dump.memmap_header()
    exe = video_rtl.build_tb(rtl, work, out=on_wire, tube=GREY_BGR)
    d, frames = _board_frames("ancool")
    if on_wire:
        result = video_rtl.wire(exe, rv.WIRE, d, frames, tube=GREY_RGB)
    else:
        result = video_rtl.replay(exe, d, frames, tube=GREY_RGB)
    assert result.returncode != 0, f"{name} went unnoticed:\n{result.stdout}"
