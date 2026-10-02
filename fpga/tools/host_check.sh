#!/usr/bin/env bash
# Plan step 0b-i: the native host (fpga/host/) must fingerprint every cart
# exactly as apps/scene_hash.mjs does on the wasm machine. Runs both, compares
# the JSON byte for byte, and writes a per-cart table.
#
#   tools/host_check.sh                  # every docs/demo-*.wasm, plus the --call runs
#   tools/host_check.sh stniccc gem      # just these (by tag), no --call runs
#   JOBS=8 FRAMES=600 tools/host_check.sh
#
# Verdicts: PASS (identical JSON and exit code), FAIL (they differ: a finding),
# SAME-ERR (identical JSON and the same non-zero exit, e.g. a refused zg.mem),
# BOTH-REFUSE (node refuses the cart too, so scene_hash.mjs does not cover it),
# BUILD (the native host did not build). Exit 1 on any FAIL or BUILD.
set -uo pipefail

FPGA="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$FPGA/.." && pwd)"
OUT="$FPGA/build/host/check"
JOBS="${JOBS:-4}" FRAMES="${FRAMES:-1200}" EVERY="${EVERY:-10}"
mkdir -p "$OUT"

# One job per line: tag|frames|every|--call spec (may be empty).
jobs_file="$OUT/jobs.txt"
: >"$jobs_file"
if [ $# -gt 0 ]; then
    for tag in "$@"; do echo "$tag|$FRAMES|$EVERY|" >>"$jobs_file"; done
else
    for w in "$ROOT"/docs/demo-*.wasm; do
        t=$(basename "$w" .wasm); echo "${t#demo-}|$FRAMES|$EVERY|" >>"$jobs_file"
    done
    # The --call path, as apps/tutorial_steps_check.mjs drives it.
    for t in tutorial_steps c-tutorial_steps rust-tutorial_steps; do
        for n in 1 4 7; do echo "$t|300|10|1:setShadeMode:$n" >>"$jobs_file"; done
    done
fi

# Build every distinct cart's host first (make -j; -k so one failure does not stop the rest).
tags=$(cut -d'|' -f1 "$jobs_file" | sort -u)
targets=$(for t in $tags; do echo "build/host/$t/host"; done)
# shellcheck disable=SC2086  # word splitting of the target list is intended
make -C "$FPGA" -k -j"$JOBS" memmap $targets >"$OUT/build.log" 2>&1

run_one() {  # tag frames every call -> one table row on stdout
    local tag=$1 frames=$2 every=$3 call=$4 id=$1${4:+@${4//:/_}}
    local args=("docs/demo-$tag.wasm" "$frames" "$every") js="$OUT/$id.js.json" nat="$OUT/$id.native.json"
    [ -n "$call" ] && args+=(--call "$call")
    (cd "$ROOT" && node apps/scene_hash.mjs "${args[@]}" >"$js" 2>"$OUT/$id.js.err"); local jrc=$?
    local verdict distinct
    distinct=$(grep -o '"hash":"[0-9a-f]*"' "$js" 2>/dev/null | sort -u | wc -l)
    if [ ! -x "$FPGA/build/host/$tag/host" ]; then
        [ $jrc -ne 0 ] && verdict=BOTH-REFUSE || verdict=BUILD
        printf '%-34s %-11s %4s %8s\n' "$id" "$verdict" "$jrc" "$distinct"; return
    fi
    (cd "$ROOT" && "$FPGA/build/host/$tag/host" "${args[@]}" >"$nat" 2>"$OUT/$id.native.err"); local nrc=$?
    if [ $jrc -eq $nrc ] && cmp -s "$js" "$nat"; then
        [ $jrc -eq 0 ] && verdict=PASS || verdict=SAME-ERR
    else
        verdict=FAIL
    fi
    printf '%-34s %-11s %4s %8s\n' "$id" "$verdict" "$jrc/$nrc" "$distinct"
}
export -f run_one
export FPGA ROOT OUT

report="$OUT/report.txt"
printf '%-34s %-11s %4s %8s\n' cart verdict rc distinct >"$report"
tr '|' '\n' <"$jobs_file" | xargs -d '\n' -n4 -P"$JOBS" bash -c 'run_one "$@"' _ | sort >>"$report"
cat "$report"
for v in PASS SAME-ERR FAIL BOTH-REFUSE BUILD; do printf '%s=%s ' "$v" "$(grep -c " $v " "$report")"; done; echo
echo "host_check: report $report, JSON and stderr in $OUT"
! grep -qE ' (FAIL|BUILD) ' "$report"
