#!/bin/sh
# The KESTREL perf suite, one entry point: static bad-pattern detectors over each cart's
# wasm, cross-checked with a dynamic run of the cart (no Verilator sim), ranked by the
# ESTIMATED Mc/frame on ZIGGY (apps/perf/cost_model.mjs).
#
#   tools/perf_audit.sh <cart.wasm|tag> [options]   one cart: its ranked findings
#   tools/perf_audit.sh --all [--jobs 4]            the shelf, ranked; JSON to $PERF_AUDIT_JSON
#   tools/perf_audit.sh --report                    the gate's REPORT: --all, never fails the gate
#
# JSON goes to $PERF_AUDIT_JSON (default zig-out/perf_audit.json) for tracking over time.
# Names: tools/perf_names.sh builds the named twin (else functions show as f123).
cd "$(dirname "$0")/.." || exit 2
OUT=${PERF_AUDIT_JSON:-zig-out/perf_audit.json}
mkdir -p "$(dirname "$OUT")"
case "$1" in
--report)
    shift
    # A report, not a check: a crash of the tool is printed, never a gate failure.
    node apps/perf_audit.mjs --all --top-n 25 --out "$OUT" "$@" || echo "perf_audit: the report failed (exit $?), see above"
    echo "perf_audit: full ranking in $OUT"
    exit 0 ;;
--all) exec node apps/perf_audit.mjs "$@" --out "$OUT" ;;
"") echo "usage: tools/perf_audit.sh <cart.wasm|tag> [options] | --all | --report" >&2; exit 2 ;;
esac
cart=$1; shift
[ -f "$cart" ] || cart=docs/demo-$cart.wasm
exec node apps/perf_audit.mjs "$cart" "$@"
