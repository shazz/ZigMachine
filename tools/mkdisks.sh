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
# A disk is rewritten only when its CONTENT changes. Every image is packed again
# with the date the existing disk already carries; if that reproduces the disk
# byte for byte, it is left alone, so an unchanged disk keeps its bytes and date.
# Only a disk whose cart or files really changed is stamped with today's date.
# (This used to compare file timestamps, which a fresh checkout or worktree
# resets, so every build re-stamped all of them and dirtied every commit.)
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
SKIP="machine-video machine-audio demo-audio bootloader audio boot-novirus demo-c demo-rust"

packed=0; skipped=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# repack <out.zmd> <mkdisk args...>: write out only if its content changed.
repack() {
    out=$1; shift
    if [ -z "$FORCE" ] && [ -f "$out" ]; then
        trial="$TMP/$(basename "$out")"
        python3 "$MK" "$@" -o "$trial" --date "$DATE" --date-from "$out" > /dev/null
        if cmp -s "$trial" "$out"; then skipped=$((skipped+1)); return; fi
    fi
    python3 "$MK" "$@" -o "$out" --date "$DATE"
    packed=$((packed+1))
}

# Every cart goes on its disk ZX0-PACKED (about a tenth of the size; ST Replay's
# 1.6 MB of zero-filled RAM becomes 9 KB). The machine unpacks it when it loads
# the disk: sealed-loader.js hands the bytes to the ROM chip's romDepack. Packing
# is deterministic, so an unchanged cart still reproduces its disk byte for byte.
ZX0PACK=zig-out/bin/zx0pack
[ -x "$ZX0PACK" ] || { echo "mkdisks: $ZX0PACK is missing: run zig build first"; exit 1; }
packcart() { # packcart <cart.wasm> -> prints the packed copy's path
    dst="$TMP/$(basename "$1").zx0"
    "$ZX0PACK" "$1" "$dst" > /dev/null
    echo "$dst"
}

pack() { # pack <out.zmd> <title> <cart.wasm> [extra mkdisk args...]
    out=$1 title=$2 cart=$3; shift 3
    if [ ! -f "$cart" ]; then echo "  -- $out: no $cart, skipped"; skipped=$((skipped+1)); return; fi
    repack "$out" "$(packcart "$cart")" --title "$title" --author "$AUTHOR" "$@"
}

# --- the menu ------------------------------------------------------------
pack "$OUT/demo.zmd" "ZigMachine Menu" "$OUT/demo.wasm"

# --- scene disks: one per demo-<tag>.wasm, title = tag ------------------
# A new scene gets a disk automatically — that is the point of deriving the list
# from the build output rather than hardcoding it here.
for w in "$OUT"/demo-*.wasm; do
    tag=$(basename "$w" .wasm); tag=${tag#demo-}
    case " $SKIP " in *" demo-$tag "*|*" $tag "*) continue;; esac
    # Polyglot carts (demo-c-*, demo-rust-*) run via ?demo=, not from a
    # floppy, and there is one per scene — so skip the whole family rather
    # than naming each new one in SKIP and finding out by a failed pack.
    # EXCEPT a polyglot cart the menu lists (its tag is in catalog.zig): the
    # menu and the +/- channels boot scenes from demo-<tag>.zmd, so it needs one.
    case "$tag" in
        c-*|rust-*) grep -q "\.tag = \"$tag\"" apps/zig/scenes/catalog.zig || continue ;;
    esac
    case "$tag" in
        # ST Replay ships as a DATA disk: not executable, so the machine boots
        # GEM, which opens the app and reads its sample off the same disk.
        st_replay) pack "$OUT/demo-$tag.zmd" "$tag" "$w" --no-boot \
                        --file "SAMPLE.RAW=$OUT/music/smp1.raw" ;;
        # STNICCC 2000 streams its polygon data off the disk, 64 KB at a time.
        stniccc)   pack "$OUT/demo-$tag.zmd" "$tag" "$w" \
                        --file "SCENE1.BIN=apps/zig/assets/screens/stniccc/scene1.bin" ;;
        # The streaming demo carries the track it block-streams.
        stream)    pack "$OUT/demo-$tag.zmd" "$tag" "$w" \
                        --file "MICROMIX.RAW=$OUT/music/micromix30.raw" ;;
        *)         pack "$OUT/demo-$tag.zmd" "$tag" "$w" ;;
    esac
done

# --- format v2: an EXECUTABLE wasm boot sector that chainloads the cart ---
if [ -f "$OUT/boot-novirus.wasm" ] && [ -f "$OUT/demo-fullscreen.wasm" ]; then
    repack "$OUT/test-v2.zmd" "$(packcart "$OUT/demo-fullscreen.wasm")" \
        --title "No Virus Test" --boot-wasm "$OUT/boot-novirus.wasm"
fi

echo "disks: $packed packed, $skipped up to date"
