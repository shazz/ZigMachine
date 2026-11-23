#!/usr/bin/env bash
# Pack every built cart wasm into a .zmd floppy image (site/carts/demo.zmd + demo-*.zmd).
# Run after `zig build -Dwasm -Drelease=true`. See docs/guide/FLOPPY_DISK.md.
set -euo pipefail
cd "$(dirname "$0")/.."

n=0
for w in site/carts/demo.wasm site/carts/demo-*.wasm; do
    case "$w" in
        site/demo-audio.wasm | site/carts/demo-c.wasm | site/carts/demo-rust.wasm) continue ;;
    esac
    [ -f "$w" ] || continue
    base=$(basename "$w" .wasm)                 # demo | demo-<tag>
    title=$([ "$base" = demo ] && echo "ZigMachine Menu" || echo "${base#demo-}")
    # ST Replay ships as a non-bootable DATA disk (a GEM app, not a boot cart):
    # inserting it brings up GEM, which opens ST Replay and reads its SAMPLE.RAW.
    extra=""
    [ "$base" = "demo-st_replay" ] && extra="--no-boot --file SAMPLE.RAW=site/music/smp1.raw"
    # STREAM block-streams a sample off its own disk — bundle MICROMIX.RAW as a FAT file.
    [ "$base" = "demo-stream" ] && extra="--file MICROMIX.RAW=site/music/micromix30.raw"
    python3 tools/mkdisk.py "$w" -o "site/carts/$base.zmd" \
        --title "$title" --author "ZigMachine" --date 20260906 $extra >/dev/null
    n=$((n + 1))
done
echo "packed $n floppies -> site/carts/*.zmd"
