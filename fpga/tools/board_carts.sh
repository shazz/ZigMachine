#!/usr/bin/env bash
# Browser carts -> board carts -> an SD card tree (fpga/CONVERT_WASM.md): builds the board image of
# each cart (`make board-fw`), one at a time under the box's build lock, and optionally stages only
# those carts with tools/glass_sd.py and writes the md5s.
#
#   tools/board_carts.sh rick_dangerous joust                       # build: FPU + BARD images
#   tools/board_carts.sh --stage /dev/shm/sd --bit X.bit rick_dangerous joust
#   FPU=0 AUDIO=1 tools/board_carts.sh tutorial                     # another bitstream's variant
#
# Prints one line a cart: `<tag> ok <bytes>` or `<tag> FAIL rc=<n> (<log>)`. Exit 1 if any failed.
# --stage stages only the carts built OK, and only those: glass_sd.py stages every fw.bin in its
# --fw-dir, so they are copied to a fresh one first.
set -uo pipefail

FPGA="$(cd "$(dirname "$0")/.." && pwd)"
# The box's one build lock lives in the MAIN checkout (a worktree's prototypes/ has no _gate_logs).
MAIN="$(cd "$(git -C "$FPGA" rev-parse --git-common-dir)/.." && pwd)"
LOCK="${LOCK:-$MAIN/prototypes/_gate_logs/build.lock}"
FPU="${FPU:-1}" AUDIO="${AUDIO:-snd}"
stage="" bit=""
while [ $# -gt 0 ]; do
    case "$1" in
        --stage) stage="$2"; shift 2 ;;
        --bit) bit="$2"; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        -*) echo "board_carts: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
[ $# -gt 0 ] || { echo "board_carts: name at least one cart tag (docs/demo-<tag>.wasm)" >&2; exit 2; }
[ -z "$stage" ] || [ -n "$bit" ] || { echo "board_carts: --stage needs --bit (the bitstream you boot)" >&2; exit 2; }
[ -f "$LOCK" ] || { echo "board_carts: no build lock at $LOCK" >&2; exit 2; }
[ -x "$FPGA/.tools/wabt/bin/wasm2c" ] || { echo "board_carts: no fpga/.tools/wabt (tools/setup.sh, or link the main checkout's)" >&2; exit 2; }
[ -f "$FPGA/build/soc_z7/csr.json" ] || { echo "board_carts: no build/soc_z7/csr.json: copy the CSR map of the bitstream you boot" >&2; exit 2; }
export PATH="$FPGA/.tools/wabt/bin:$PATH"

dir="board"
[ "$AUDIO" = snd ] && dir="${dir}_snd"
[ "$FPU" = 1 ] && dir="${dir}_fpu"
logs="$FPGA/build/board_carts"
mkdir -p "$logs"
good=() failed=0
for tag in "$@"; do
    if [ ! -f "$FPGA/../docs/demo-$tag.wasm" ]; then
        echo "$tag FAIL no docs/demo-$tag.wasm (build the browser cart first)"; failed=1; continue
    fi
    (cd "$FPGA" && flock "$LOCK" make board-fw CART="$tag" ZM_FPU="$FPU" ZM_AUDIO="$AUDIO") >"$logs/$tag.log" 2>&1
    rc=$?
    fw="$FPGA/build/hcycles/$dir/$tag/fw.bin"
    if [ $rc -eq 0 ] && [ -f "$fw" ]; then
        echo "$tag ok $(stat -c %s "$fw")"; good+=("$tag")
    else
        echo "$tag FAIL rc=$rc ($logs/$tag.log)"; failed=1
    fi
done

if [ -n "$stage" ] && [ ${#good[@]} -gt 0 ]; then
    fwdir="$stage.fw"
    rm -rf "$fwdir" && mkdir -p "$fwdir"
    for tag in "${good[@]}"; do mkdir -p "$fwdir/$tag" && cp "$FPGA/build/hcycles/$dir/$tag/fw.bin" "$fwdir/$tag/"; done
    (cd "$FPGA" && uv run python tools/glass_sd.py --out "$stage" --fw-dir "$fwdir" --bit "$bit") >"$logs/stage.log" 2>&1 \
        || { echo "stage FAIL ($logs/stage.log)"; exit 1; }
    (cd "$stage" && find zigmachine -type f | sort | xargs md5sum) >"$stage.md5"
    echo "staged $stage (md5s: $stage.md5); read $stage/MANIFEST.txt"
fi
exit $failed
