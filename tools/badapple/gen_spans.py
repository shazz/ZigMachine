#!/usr/bin/env python3
"""Bad Apple span-delta stream encoder (format: spans.py). ZX0 packing by zig-out/bin/zx0pack (zig build installs it).

  gen_spans.py --synth OUT            our own committed test film (synth.py); `--check` compares OUT with a fresh one
  gen_spans.py --video IN OUT         the real film: ffmpeg scales IN to 320x200 at 30 fps and thresholds it (LOCAL use only:
                                      the video is a copyrighted fan animation, its stream is never committed)
  ref_decode.py STREAM OUT [frames]   the reference decoder, 0/1 bytes a pixel (the harness's oracle)
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from collections.abc import Iterator
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from badapple import spans, synth  # noqa: E402

FPS = 30


def zx0_pack(zx0pack: Path, raw: bytes, tmp: Path) -> bytes:
    src, dst = tmp / "in.bin", tmp / "out.zx0"
    src.write_bytes(raw)
    subprocess.run([str(zx0pack), str(src), str(dst)], check=True, stdout=subprocess.DEVNULL)
    return dst.read_bytes()


def encode(frames: Iterator[bytes], zx0pack: Path) -> tuple[bytes, dict[str, int]]:
    """A whole stream from 0/1 frames; stats: frames, rows cut at MAX_TRANS, the largest raw and packed block."""
    blocks, group, total, clamped = [], [], 0, 0
    with tempfile.TemporaryDirectory() as td:
        def flush() -> None:
            raw = spans.encode_block(group)
            blocks.append((raw, len(group), zx0_pack(zx0pack, raw, Path(td))))
            group.clear()

        for px in frames:
            rows = spans.frame_rows(px)
            clamped += sum(_cut(px, y) for y in range(spans.HEIGHT))
            group.append(rows)
            total += 1
            if len(group) == spans.GOP:
                flush()
        if group:
            flush()
    stats = {"frames": total, "clamped_rows": clamped, "max_raw": max(len(b[0]) for b in blocks),
             "max_packed": max(len(b[2]) for b in blocks)}
    return spans.pack_stream(blocks, total, FPS), stats


def _cut(px: bytes, y: int) -> bool:
    row = px[y * spans.WIDTH:(y + 1) * spans.WIDTH]
    return sum(a != b for a, b in zip(row, row[1:])) + (row[0] != 0) > spans.MAX_TRANS


def video_frames(video: Path, seconds: float) -> Iterator[bytes]:
    cmd = ["ffmpeg", "-v", "quiet"] + (["-t", str(seconds)] if seconds > 0 else []) + [
        "-i", str(video), "-vf", f"fps={FPS},scale={spans.WIDTH}:{spans.HEIGHT},format=gray", "-f", "rawvideo", "-"]
    with subprocess.Popen(cmd, stdout=subprocess.PIPE) as p:
        assert p.stdout is not None
        n = spans.WIDTH * spans.HEIGHT
        while len(buf := p.stdout.read(n)) == n:
            yield bytes(1 if v >= 128 else 0 for v in buf)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--synth", type=Path, metavar="OUT")
    ap.add_argument("--video", nargs=2, type=Path, metavar=("IN", "OUT"))
    ap.add_argument("--check", action="store_true", help="with --synth: OUT must already hold exactly what is generated")
    ap.add_argument("--zx0pack", type=Path, default=Path("zig-out/bin/zx0pack"))
    ap.add_argument("--duration", type=float, default=0.0)
    a = ap.parse_args()
    if a.synth:
        data, stats = encode(synth.frames(), a.zx0pack)
        if a.check:
            ok = a.synth.read_bytes() == data
            print(f"{a.synth}: {'matches' if ok else 'DIFFERS from'} a fresh synthetic stream")
            return 0 if ok else 1
        out = a.synth
    elif a.video:
        data, stats = encode(video_frames(a.video[0], a.duration), a.zx0pack)
        out = a.video[1]
    else:
        ap.error("--synth or --video")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    print(f"{out}: {len(data)} bytes, {stats}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
