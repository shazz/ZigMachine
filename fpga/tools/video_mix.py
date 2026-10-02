"""The browser's picture of a recorded frame: the oracle of the RTL plane mixer.

    uv run python tools/video_mix.py build/vdump/union_main/frames 300          # -> f300.mix
    uv run python tools/video_mix.py --chrome build/vdump/union_main/frames 300  # + check it against Chrome

`vmix` (tools/video_dump/vmix.c) stacks the plane canvases as docs/sealed-loader.js
fills them and composes them as Chrome does. `--chrome` proves that claim on the
spot: it hands the same canvases to headless Chrome (tools/mix_chrome.mjs) and
requires the screenshot to equal vmix's picture byte for byte.
"""

import os
import random
import subprocess
import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
SRC = FPGA / "tools" / "video_dump"
OUT = FPGA / "build" / "vdump"
CANVAS_BYTES = 800 * 280 * 4
# Where `npx playwright` left its package; PLAYWRIGHT_DIR overrides it.
NPX = Path.home() / ".npm" / "_npx"


def build_vmix() -> Path:
    """vmix, compiled against build/vdump/zm_memmap.h (tools/video_dump.py memmap_header)."""
    exe = OUT / "vmix"
    src = SRC / "vmix.c"
    if not exe.exists() or exe.stat().st_mtime < src.stat().st_mtime:
        cmd = ["clang", "-std=c11", "-O2", "-Wall", "-Werror", f"-I{OUT}", str(src), "-o", str(exe)]
        subprocess.run(cmd, check=True)
    return exe


def mix(frames_dir: Path, frames: list[int], layers: bool = False) -> None:
    """Write f<N>.mix (and f<N>.layers if asked) next to each recorded frame."""
    exe = build_vmix()
    for f in frames:
        extra = ["--layers"] if layers else []
        subprocess.run([str(exe), "frame", str(frames_dir), str(f), *extra], check=True)


def playwright_dir() -> str | None:
    if os.environ.get("PLAYWRIGHT_DIR"):
        return os.environ["PLAYWRIGHT_DIR"]
    found = sorted(NPX.glob("*/node_modules/playwright"))
    return str(found[-1].parent) if found else None


def chrome(layers: Path, mask: int, out: Path) -> None:
    """Chrome's own composite of `layers` (tools/mix_chrome.mjs)."""
    env = dict(os.environ)
    pw = playwright_dir()
    if pw:
        env["PLAYWRIGHT_DIR"] = pw
    args = ["node", str(FPGA / "tools" / "mix_chrome.mjs"), str(layers), str(mask), str(out)]
    subprocess.run(args, check=True, env=env, timeout=120)


def frame_mask(frames_dir: Path, frame: int) -> int:
    planes = int((frames_dir / f"f{frame}.meta").read_text().split()[1])
    return planes or 1


def chrome_check_frame(frames_dir: Path, frame: int) -> int:
    """Pixels where Chrome's picture of a recorded frame differs from vmix's."""
    mix(frames_dir, [frame], layers=True)
    shot = frames_dir / f"f{frame}.chrome"
    chrome(frames_dir / f"f{frame}.layers", frame_mask(frames_dir, frame), shot)
    return differing(shot.read_bytes(), (frames_dir / f"f{frame}.mix").read_bytes())


def chrome_check_random(work: Path, seed: int, mask: int) -> int:
    """The same, for 4 canvases of random RGBA: every alpha, every colour, any stack."""
    work.mkdir(parents=True, exist_ok=True)
    rng = random.Random(seed)
    layers = work / f"rand{seed}.layers"
    layers.write_bytes(rng.randbytes(4 * CANVAS_BYTES))
    ours, theirs = work / f"rand{seed}.mix", work / f"rand{seed}.chrome"
    subprocess.run([str(build_vmix()), "layers", str(layers), str(mask), str(ours)], check=True)
    chrome(layers, mask, theirs)
    return differing(theirs.read_bytes(), ours.read_bytes())


def differing(a: bytes, b: bytes) -> int:
    assert len(a) == len(b), "pictures of different sizes"
    return sum(a[i : i + 3] != b[i : i + 3] for i in range(0, len(a), 3))


if __name__ == "__main__":
    args = sys.argv[1:]
    check = bool(args) and args[0] == "--chrome"
    args = args[1:] if check else args
    if len(args) < 2:
        sys.exit("usage: video_mix.py [--chrome] <frames dir> <frame>...")
    d = Path(args[0])
    bad = 0
    for f in map(int, args[1:]):
        if check:
            n = chrome_check_frame(d, f)
            print(f"frame {f}: {n} pixels differ from Chrome")
            bad += n
        else:
            mix(d, [f])
    sys.exit(1 if bad else 0)
