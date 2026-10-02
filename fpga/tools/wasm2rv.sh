#!/usr/bin/env bash
# Plan step 0a: translate every cart (docs/demo-*.wasm) to C with wasm2c and
# compile it for rv32imf, the cart CPU's ISA. Proves the wasm -> RISC-V route
# carries the whole shelf with no cart changes, and reports each cart's code size
# (what the cart CPU's I-cache and the DDR cart window have to hold).
#
#   tools/wasm2rv.sh                 # every cart
#   tools/wasm2rv.sh stniccc gem     # just these (by tag)
#
# Compile-only for now: linking needs the native ROM and the machine's host
# imports as rv32 symbols, which is plan step 3. Instruction counting per frame
# (step 0b) needs a simulator: Verilator + VexRiscv, or qemu-riscv32 -icount.
set -euo pipefail

FPGA="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$FPGA/.." && pwd)"
WABT="$FPGA/.tools/wabt"
ZIG="${ZIG:-$HOME/.local/zig/0.16.0/zig}"
OUT="$FPGA/build/rv"
# Zig's bundled musl supplies the libc headers wasm2c's output includes; nothing
# from libc is linked. rv32imf = the cart CPU with a single-precision FPU.
TARGET=(-target riscv32-linux-musl -mcpu=generic_rv32+m+f)

[ -x "$WABT/bin/wasm2c" ] || { echo "wasm2rv: no wasm2c, run tools/setup.sh" >&2; exit 1; }
mkdir -p "$OUT"

carts=()
if [ $# -gt 0 ]; then
    for tag in "$@"; do carts+=("$ROOT/docs/demo-$tag.wasm"); done
else
    carts=("$ROOT"/docs/demo-*.wasm)
fi

ok=0 failed=0
printf '%-28s %10s %10s  %s\n' cart wasm rv32_text status | tee "$OUT/report.txt"
for wasm in "${carts[@]}"; do
    tag=$(basename "$wasm" .wasm); tag=${tag#demo-}
    c="$OUT/$tag.c" o="$OUT/$tag.o" log="$OUT/$tag.log"
    status=ok text=-
    if [ ! -f "$wasm" ]; then
        status="missing $wasm"
    elif ! "$WABT/bin/wasm2c" "$wasm" -n "${tag//-/_}" -o "$c" 2>"$log"; then
        status="wasm2c failed (see $log)"
    elif ! "$ZIG" cc "${TARGET[@]}" -O2 -I"$WABT/include" -c "$c" -o "$o" 2>>"$log"; then
        status="compile failed (see $log)"
    else
        text=$(size "$o" | awk 'NR==2 {print $1}')
    fi
    [ "$status" = ok ] && ok=$((ok + 1)) || failed=$((failed + 1))
    printf '%-28s %10s %10s  %s\n' "$tag" "$(stat -c %s "$wasm" 2>/dev/null || echo -)" "$text" "$status" \
        | tee -a "$OUT/report.txt"
done
echo "wasm2rv: $ok translated, $failed failed (report: $OUT/report.txt)"
[ "$failed" -eq 0 ]
