#!/bin/sh
# ZX0-pack every cart asset and report what packing would save, per screen.
#
# Packed copies go to zig-out/packed/ (gitignored) and are only repacked when
# their source is newer, so after the first run this costs a stat per file.
# Carts do NOT use these copies: a scene adopts packing through build.zig's
# packed_assets module (docs/DEPACK.md). This is the measurement that says which
# scenes are worth it.
#
#   tools/pack_stats.sh                     summary per screen/group + total
#   PACK_STATS_VERBOSE=1 tools/pack_stats.sh   every file as well
#
# Exits non-zero if any file fails to pack or fails its depack verification.
set -e
cd "$(dirname "$0")/.."

PACKER=zig-out/bin/zx0pack
ASSETS=apps/zig/assets
OUT=zig-out/packed
[ -x "$PACKER" ] || { echo "pack_stats: $PACKER missing — run zig build -Drelease=true -Dwasm first" >&2; exit 1; }

mkdir -p "$OUT"
MANIFEST="$OUT/manifest.tsv"
LOG="$OUT/stats.log"
TAB=$(printf '\t')

# Binary assets only: PNGs and scripts are sources of the .raw/.dat files, not
# what a cart embeds. Names may contain spaces (the .ymraw tunes), hence -print0-free
# line reading with IFS set to newline only.
: > "$MANIFEST"
find "$ASSETS" -type f \
    ! -name '*.png' ! -name '*.jpg' ! -name '*.gif' ! -name '*.bmp' \
    ! -name '*.py' ! -name '*.js' ! -name '*.md' ! -name '*.txt' ! -name '*.zx0' \
    | LC_ALL=C sort | while IFS= read -r f; do
        rel=${f#"$ASSETS"/}
        dst="$OUT/$rel.zx0"
        mkdir -p "$(dirname "$dst")"
        printf '%s%s%s\n' "$f" "$TAB" "$dst" >> "$MANIFEST"
    done

status=0
"$PACKER" --stats --manifest "$MANIFEST" 2> "$LOG" || status=$?

[ -n "$PACK_STATS_VERBOSE" ] && grep -v '^TOTAL' "$LOG"

# Group by screen (assets/screens/<name>) or top-level folder (ym, mod, smp...).
# Fields are read from the END of each line: a packed line ends
# "raw packed ratio% N ms", an up-to-date line "raw packed ratio%  up to date".
echo "--- ZX0 pack statistics (apps/zig/assets) ---"
awk '
    /^TOTAL/ { total = $0; next }
    /^zx0pack:/ { errors = errors $0 "\n"; next }
    NF < 5 { next }
    {
        if ($NF == "date") { raw = $(NF-5); pk = $(NF-4) } else { raw = $(NF-4); pk = $(NF-3) }
        n = split($1, p, "/")
        key = (p[4] == "screens" && n > 5) ? "screens/" p[5] : p[4]
        R[key] += raw; P[key] += pk; F[key]++
        if (raw > 0 && pk >= raw) incompressible = incompressible "  " $1 "\n"
    }
    END {
        printf "%-34s %5s %10s %10s %7s %10s\n", "group", "files", "raw", "packed", "ratio", "saved"
        for (k in R) printf "%-34s %5d %10d %10d %6.1f%% %10d\n", k, F[k], R[k], P[k], (R[k] ? 100 * P[k] / R[k] : 100), R[k] - P[k] | "sort -k3,3nr"
        close("sort -k3,3nr")
        if (incompressible != "") printf "incompressible (keep unpacked):\n%s", incompressible
        if (errors != "") printf "FAILED:\n%s", errors
        print total
    }
' "$LOG"

exit $status
