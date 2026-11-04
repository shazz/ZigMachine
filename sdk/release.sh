#!/usr/bin/env bash
# Assemble a KESTREL SDK release (docs/SDK.md, "The release"): ONE tarball an outside coder downloads.
#
#   sdk/release.sh --version v1.1 --hw 1.16.0 --out DIR [--card CARD_DIR] [--rev REV]
#
#   DIR/kestrel-sdk-<version>/
#       README.txt      where to start
#       RELEASE.txt     the KESTREL release it targets: version, HW, commit, the system table (sys_table)
#       zigmachine/     the repository at REV (git archive: nothing untracked, no prototypes/)
#       template/       sdk/template, its build.zig.zon pointing at ../zigmachine
#       card/           CARD_DIR (a staged SD card: tools/glass_sd.py --system ...) + card.md5
#   DIR/kestrel-sdk-<version>.tar.gz
#
# The card is the lead's: bitstream, boot files, system.rv32 and the shelf, staged by glass_sd.py.
# Its system.rv32 serves one system-table version (its MANIFEST.txt says "(table X.Y)"); a cart
# built from this SDK's fpga/cycles/sys_abi.txt must match it, so the release refuses a card whose
# table differs from REV's. Without --card the release carries no card, and RELEASE.txt says so.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=""; HW=""; OUT=""; CARD=""; REV=HEAD
while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION=$2; shift 2 ;;
        --hw) HW=$2; shift 2 ;;
        --out) OUT=$2; shift 2 ;;
        --card) CARD=$2; shift 2 ;;
        --rev) REV=$2; shift 2 ;;
        *) echo "usage: $0 --version v1.1 --hw 1.16.0 --out DIR [--card CARD_DIR] [--rev REV]"; exit 2 ;;
    esac
done
[ -n "$VERSION" ] && [ -n "$HW" ] && [ -n "$OUT" ] || { echo "release: --version, --hw and --out are required"; exit 2; }
NAME="kestrel-sdk-$VERSION"
DEST="$OUT/$NAME"
[ ! -e "$DEST" ] || { echo "release: $DEST exists; remove it first"; exit 1; }
SHA="$(git -C "$ROOT" rev-parse "$REV")"
git -C "$ROOT" diff --quiet "$REV" -- sdk build.zig fpga/cycles/sys_abi.txt ||
    echo "release: warning: the working tree differs from $REV; the release is $REV's files"

# The table REV's carts are built for (sys_abi.txt "version X.Y").
abi_version() { awk '$1 == "version" { split($2, v, "."); printf "0x%x\n", v[1] * 65536 + v[2]; exit }'; }
TABLE="$(git -C "$ROOT" show "$SHA:fpga/cycles/sys_abi.txt" | abi_version)"
if [ -n "$CARD" ]; then
    [ -f "$CARD/zigmachine/system.rv32" ] || { echo "release: $CARD has no zigmachine/system.rv32"; exit 1; }
    CARD_TABLE="$(sed -n 's/^zigmachine\/system.rv32 .*(table \([0-9]*\.[0-9]*\)).*/version \1/p' "$CARD/MANIFEST.txt" | abi_version)"
    [ "$CARD_TABLE" = "$TABLE" ] || { echo "release: the card's system serves table $CARD_TABLE, $REV's carts need $TABLE"; exit 1; }
fi

mkdir -p "$DEST/zigmachine"
git -C "$ROOT" archive --format=tar "$SHA" -- . ':(exclude)prototypes' | tar -x -C "$DEST/zigmachine"
cp -R "$ROOT/sdk/template" "$DEST/template"
rm -rf "$DEST/template/zig-out" "$DEST/template/.zig-cache"
sed -i.bak 's|\.path = "\.\./\.\."|.path = "../zigmachine"|' "$DEST/template/build.zig.zon" && rm "$DEST/template/build.zig.zon.bak"
grep -q '"../zigmachine"' "$DEST/template/build.zig.zon" || { echo "release: could not point the template at ../zigmachine"; exit 1; }

if [ -n "$CARD" ]; then
    mkdir -p "$DEST/card"
    cp -R "$CARD/." "$DEST/card/"
    (cd "$DEST/card" && find . -type f | sort | xargs md5sum) > "$DEST/card.md5"
    CARD_NOTE="card/ (from $(basename "$CARD"); md5s in card.md5)"
else
    CARD_NOTE="none: get the KESTREL $VERSION card from its release page"
fi
cat > "$DEST/RELEASE.txt" <<EOF
kestrel = $VERSION
hw = $HW
commit = $SHA
date = $(date +%Y-%m-%d)
sys_table = $TABLE
card = $CARD_NOTE
EOF
cat > "$DEST/README.txt" <<EOF
KESTREL SDK $VERSION (HW $HW): write carts for the ZigMachine and the KESTREL board.

  1. zigmachine/tools/sdk_doctor.sh      what to install (zig 0.16.0, python3; for the board: wabt, clang, uv, riscv gcc)
  2. cd template && make                 your cart in the browser emulator (http://localhost:3333/...)
  3. make floppy / make board            a disk image / the board image + an SD folder (template/zig-out/sd)

Start a new cart: copy template/ to a sibling directory (it finds the SDK at ../zigmachine).
The guide: zigmachine/docs/SDK.md
EOF
tar -C "$OUT" -czf "$OUT/$NAME.tar.gz" "$NAME"
echo "release: $OUT/$NAME.tar.gz ($(du -h "$OUT/$NAME.tar.gz" | cut -f1)), commit ${SHA:0:12}, table $TABLE"
