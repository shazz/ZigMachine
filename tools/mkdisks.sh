#!/bin/sh
# Repack every ZigMachine .zmd disk image from the built wasm carts.
#
# WHY THIS EXISTS: the disks used to be build output with no recipe. They drifted
# a week behind the wasm and froze an import list that no longer matched the host,
# so every disk on the shelf failed to instantiate (4c00b19) — the metadata was
# only recoverable by reading the images back. Packing is now a command.
#
# Every disk below was verified against the descriptor of the image it replaces
# (title / author / date / bootability / FAT), so a repack is byte-faithful apart
# from the cart itself and the build date.
#
# Usage:  tools/mkdisks.sh [-f]     -f / --force: repack even if up to date
#         ZMD_DATE=YYYYMMDD tools/mkdisks.sh      pin the stamped date
#
# Disks are repacked only when a source is NEWER than the image, so a no-op build
# leaves the committed binaries alone instead of churning 29 files every time.
set -e
cd "$(dirname "$0")/.."

OUT=docs
MK=tools/mkdisk.py
AUTHOR=ZigMachine
DATE=${ZMD_DATE:-$(date +%Y%m%d)}
FORCE=""
[ "$1" = "-f" ] || [ "$1" = "--force" ] && FORCE=1

# Wasm in docs/ that are NOT bootable carts and get no disk:
#   machine-*  sealed hardware      demo-audio  worklet module, not a cart
#   boot-*     v2 boot sectors      demo-c/rust polyglot demos (run via ?demo=)
#   *bootloader/audio  retired legacy monolith
#   medium_overscan  EXCLUDED from the build (build.zig: it still calls the
#                    removed setMediumFullscreen()), so docs/demo-medium_overscan.wasm
#                    is a stale artifact. Packing it ships a disk that cannot
#                    instantiate; re-add here when the scene builds again.
SKIP="machine-video machine-audio demo-audio bootloader audio boot-novirus demo-c demo-rust medium_overscan"

packed=0; skipped=0

# stale <out> <src>... -> 0 (true) if out is missing or older than any src
stale() {
    out=$1; shift
    [ -n "$FORCE" ] && return 0
    [ -f "$out" ] || return 0
    [ "$MK" -nt "$out" ] && return 0
    for s in "$@"; do [ "$s" -nt "$out" ] && return 0; done
    return 1
}

pack() { # pack <out.zmd> <title> <cart.wasm> [extra mkdisk args...]
    out=$1 title=$2 cart=$3; shift 3
    if [ ! -f "$cart" ]; then echo "  -- $out: no $cart, skipped"; skipped=$((skipped+1)); return; fi
    # Asset paths appear as NAME=PATH; feed their PATH halves to the staleness check.
    srcs="$cart"
    for a in "$@"; do case "$a" in *=*) srcs="$srcs ${a#*=}";; esac; done
    # shellcheck disable=SC2086  # srcs is a deliberate word-split list of paths
    if ! stale "$out" $srcs; then skipped=$((skipped+1)); return; fi
    python3 "$MK" "$cart" -o "$out" --title "$title" --author "$AUTHOR" --date "$DATE" "$@"
    packed=$((packed+1))
}

# --- the menu ------------------------------------------------------------
pack "$OUT/demo.zmd" "ZigMachine Menu" "$OUT/demo.wasm"

# --- scene disks: one per demo-<tag>.wasm, title = tag ------------------
# A new scene gets a disk automatically — that is the point of deriving the list
# from the build output rather than hardcoding it here.
for w in "$OUT"/demo-*.wasm; do
    tag=$(basename "$w" .wasm); tag=${tag#demo-}
    case " $SKIP " in *" demo-$tag "*|*" $tag "*) continue;; esac
    case "$tag" in
        # ST Replay ships as a DATA disk: not executable, so the machine boots
        # GEM, which opens the app and reads its sample off the same disk.
        st_replay) pack "$OUT/demo-$tag.zmd" "$tag" "$w" --no-boot \
                        --file "SAMPLE.RAW=$OUT/music/smp1.raw" ;;
        # The streaming demo carries the track it block-streams.
        stream)    pack "$OUT/demo-$tag.zmd" "$tag" "$w" \
                        --file "MICROMIX.RAW=$OUT/music/micromix30.raw" ;;
        *)         pack "$OUT/demo-$tag.zmd" "$tag" "$w" ;;
    esac
done

# --- format v2: an EXECUTABLE wasm boot sector that chainloads the cart ---
if [ -f "$OUT/boot-novirus.wasm" ] && [ -f "$OUT/demo-fullscreen.wasm" ]; then
    if stale "$OUT/test-v2.zmd" "$OUT/boot-novirus.wasm" "$OUT/demo-fullscreen.wasm"; then
        python3 "$MK" "$OUT/demo-fullscreen.wasm" -o "$OUT/test-v2.zmd" \
            --title "No Virus Test" --date "$DATE" \
            --boot-wasm "$OUT/boot-novirus.wasm"
        packed=$((packed+1))
    else
        skipped=$((skipped+1))
    fi
fi

echo "disks: $packed packed, $skipped up to date"
