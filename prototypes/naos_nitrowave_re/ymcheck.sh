#!/bin/sh
# ymcheck.sh RIP.sndh SUB ARCHIVE.sndh SUB -- log both on the sealed YM for
# 1500 frames (ymlog.mjs, run from the repo root) and compare (ymcmp.py).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/../.."
node "$HERE/ymlog.mjs" "$1" "$2" 1500 /dev/shm/nw_a.ym
node "$HERE/ymlog.mjs" "$3" "$4" 1500 /dev/shm/nw_b.ym
python3 "$HERE/ymcmp.py" /dev/shm/nw_a.ym /dev/shm/nw_b.ym
