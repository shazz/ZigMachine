#!/usr/bin/env bash
# Pack every built cart wasm into a .zmd floppy image (docs/demo.zmd + demo-*.zmd).
# Run after `zig build -Dwasm -Drelease=true`. See docs/FLOPPY_DISK.md.
set -euo pipefail
cd "$(dirname "$0")/.."

n=0
for w in docs/demo.wasm docs/demo-*.wasm; do
    case "$w" in
        docs/demo-audio.wasm | docs/demo-c.wasm | docs/demo-rust.wasm) continue ;;
    esac
    [ -f "$w" ] || continue
    base=$(basename "$w" .wasm)                 # demo | demo-<tag>
    title=$([ "$base" = demo ] && echo "ZigMachine Menu" || echo "${base#demo-}")
    # ST Replay is a multi-file disk: its FAT carries a sample it plays/displays.
    extra=""
    [ "$base" = "demo-st_replay" ] && extra="--file SAMPLE.RAW=docs/music/smp1.raw"
    python3 tools/mkdisk.py "$w" -o "docs/$base.zmd" \
        --title "$title" --author "ZigMachine" --date 20260906 $extra >/dev/null
    n=$((n + 1))
done
echo "packed $n floppies -> docs/*.zmd"
