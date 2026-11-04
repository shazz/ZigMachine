#!/usr/bin/env bash
# zrt_cart.sh <riscv prefix> <zrt.o> <out.o>: the board cart's libgcc from Zig's compiler_rt
# (docs/SDK.md, "The riscv toolchain"), for a gcc with no rv32imf/ilp32f multilib.
#
# Zig builds compiler_rt (rv32imf, ilp32f, no C extension) as ONE object: linked as it is, a cart
# would carry all ~290 KB of it, and its stack-protector guard is .data, which a lean cart may not
# have (fpga/cycles/cart.ld). So keep libgcc's share of it: a relocatable link rooted at libgcc's
# helpers (soft single/double float, 32/64-bit integer division, shifts, bit counts; not the
# 128-bit, x87 or half-float ones, nor memcpy/strlen/ssp, which a cart gets from the system),
# --gc-sections dropping the rest. The result must hold no .data and no compressed instruction.
set -euo pipefail
P=$1 LIB=$2 OUT=$3
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
"${P}nm" -g --defined-only "$LIB" | awk '{print $3}' |
    grep -E '^__[a-z]+(sf|df|di|si)[0-9]?$|^__(clz|ctz|popcount|ffs|parity|bswap)' |
    grep -v -E 'tf|xf|ti[0-9]?$|hf' | sed 's/^/-u /' > "$WORK/roots"
[ -s "$WORK/roots" ] || { echo "zrt_cart: no libgcc helper in $LIB"; exit 1; }
# shellcheck disable=SC2046 # [word-split] one -u argument per root, by design
"${P}ld" -m elf32lriscv -r --gc-sections $(cat "$WORK/roots") "$LIB" -o "$OUT"
if "${P}size" -A "$OUT" | awk '$1 ~ /^\.s?data/ && $2 > 0 { bad = 1 } END { exit !bad }'; then
    echo "zrt_cart: $OUT still has .data"; exit 1
fi
if "${P}objdump" -d "$OUT" | grep -qE '^ +[0-9a-f]+:'$'\t''[0-9a-f]{4} '; then
    echo "zrt_cart: $OUT has compressed (C) instructions, which ZIGGY lacks"; exit 1
fi
echo "zrt_cart: $OUT, $(wc -l < "$WORK/roots") helpers, $("${P}size" "$OUT" | awk 'NR == 2 { print $1 }') B of text"
