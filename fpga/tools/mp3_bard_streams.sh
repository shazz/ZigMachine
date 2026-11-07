#!/usr/bin/env bash
# The BARD MP3 study's test streams (fpga/review/MP3_BARD_STUDY.md), all synthesised here, so CC0:
# saw-wave chords + an arpeggio + noise hits ("music": a dense spectrum, like a mixed track), encoded by
# LAME (ffmpeg libmp3lame) without ID3 or Xing/LAME frames, then their first bytes as C arrays.
#   tools/mp3_bard_streams.sh [frames=8]   -> prototypes/mp3_bard_re/streams/{*.mp3,streams.c}
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/prototypes/mp3_bard_re/streams"
FRAMES=${1:-8}
mkdir -p "$OUT"
saw() { echo "(2*mod($1*t,1)-1)"; }
L="0.18*$(saw 110)+0.14*$(saw 138.59)+0.12*$(saw 164.81)+0.10*sin(2*PI*(440+220*floor(mod(8*t,4)))*t)+0.25*(random(0)-0.5)*exp(-18*mod(t,0.25))"
R="0.18*$(saw 110.5)+0.14*$(saw 146.83)+0.12*$(saw 174.61)+0.10*sin(2*PI*(660-110*floor(mod(8*t,4)))*t)+0.25*(random(1)-0.5)*exp(-18*mod(t+0.125,0.25))"
enc() { # <name> <rate> <channels> <kbps> [source]
    local src=${5:-"aevalsrc='$L|$R':s=$2:d=2"}
    ffmpeg -v error -y -f lavfi -i "$src" -ac "$3" -ar "$2" -c:a libmp3lame -b:a "$4k" \
        -write_xing 0 -id3v2_version 0 -write_id3v1 0 "$OUT/$1.mp3"
}
enc s44_128 44100 2 128
enc s32_128 32000 2 128
enc m44_64 44100 1 64
enc s44_320 44100 2 320 "anoisesrc=c=pink:r=44100:a=0.5:d=2"
python3 - "$OUT" "$FRAMES" <<'EOF'
import sys, pathlib
out, frames = pathlib.Path(sys.argv[1]), int(sys.argv[2])
names = ["s44_128", "s32_128", "m44_64", "s44_320"]
c = ['#include "mp3bench.h"']
for n in names:
    b = (out / f"{n}.mp3").read_bytes()
    # frame bytes = 144 * kbps*1000 / rate (+ padding): keep `frames` frames and a spare
    kbps, rate = int(n.split("_")[1]), int(n[1:3]) * 1000 + (100 if n[1:3] == "44" else 0)
    b = b[: (frames + 1) * (144 * kbps * 1000 // rate + 1)]
    c.append(f"static const uint8_t {n}[{len(b)}] = {{" + ",".join(str(x) for x in b) + "};")
c.append("const mp3_stream_t mp3_streams[] = {" + ",".join(f'{{"{n}", {n}, sizeof {n}}}' for n in names) + "};")
c.append(f"const int mp3_nstreams = {len(names)};")
(out / "streams.c").write_text("\n".join(c) + "\n")
EOF
ls -l "$OUT"
