#!/bin/sh
# The integer AY core (libs/c/ayumi) = the cart's ayumi before it (apps/ports/chipnomad/kestrel_ayumi.cpp at
# 0de82761, perf/ports-synth's integer chip with its float set-up), sample for sample (check.cpp).
#   sh libs/c/ayumi/check/check.sh [--break]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git -C "$root" show 0de82761:apps/ports/chipnomad/kestrel_ayumi.cpp > "$tmp/old_ayumi.cpp"
cp "$here/old_ayumi.h" "$tmp/ayumi.h"
printf 'extern "C" float ayumi_filter_medium(float* x) { return *x; }\n' > "$tmp/filters.cpp"
CXX=${CXX:-c++} CC=${CC:-cc}
$CC -O2 -std=c99 -Wall -Werror -I"$here/.." -c "$here/../zm_ay.c" -o "$tmp/zm_ay.o"
$CC -O2 -std=c99 -Wall -Werror -I"$here/.." -c "$here/../zm_ay_cfg.c" -o "$tmp/zm_ay_cfg.o"
$CXX -O2 -w -I"$tmp" -c "$tmp/old_ayumi.cpp" -o "$tmp/old.o"
$CXX -O2 -w -c "$tmp/filters.cpp" -o "$tmp/filters.o"
$CXX -O2 -Wall -I"$tmp" -I"$here/.." "$here/check.cpp" "$tmp"/*.o -o "$tmp/check" -lm
"$tmp/check" "$@"
