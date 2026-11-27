#!/usr/bin/env python3
"""Bad Apple tile (cart 167) and polygon (cart 168) stream encoder. ZX0 packing by zig-out/bin/zx0pack.

  gen_film.py tiles|poly --synth OUT [--check]   our own committed test film (synth.py); --check: OUT is what is written
  gen_film.py tiles|poly --film SPANS OUT        the real film from a LOCAL spans.bin (cart 166's stream), so all three
                                                 carts show the same pixels (LOCAL use only: never committed)
  gen_film.py tiles|poly --video IN OUT          straight from the video (ffmpeg, as gen_spans.py --video; LOCAL only)
  ref_decode.py STREAM OUT [frames]              the reference decoder (any of the three formats)
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from badapple import gen_spans, stream, synth, tiles  # noqa: E402


def frames(a: argparse.Namespace):  # noqa: ANN201 (an iterator of 0/1 pictures from whichever source was named)
    if a.synth:
        return synth.frames()
    if a.film:
        return stream.spans_film(a.film[0])
    return gen_spans.video_frames(a.video[0], a.duration)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("format", choices=("tiles",))
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--synth", type=Path, metavar="OUT")
    src.add_argument("--film", nargs=2, type=Path, metavar=("SPANS", "OUT"))
    src.add_argument("--video", nargs=2, type=Path, metavar=("IN", "OUT"))
    ap.add_argument("--check", action="store_true", help="with --synth: OUT must already hold exactly what is generated")
    ap.add_argument("--zx0pack", type=Path, default=Path("zig-out/bin/zx0pack"))
    ap.add_argument("--duration", type=float, default=0.0)
    ap.add_argument("--hold", type=int, default=0, help="tiles: leave a slot alone when at most this many pixels differ")
    a = ap.parse_args()
    data, stats = tiles.encode(frames(a), a.zx0pack, a.hold)
    out = a.synth or (a.film or a.video)[1]
    if a.check:
        ok = out.read_bytes() == data
        print(f"{out}: {'matches' if ok else 'DIFFERS from'} a fresh synthetic {a.format} stream")
        return 0 if ok else 1
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    print(f"{out}: {len(data)} bytes, {stats}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
