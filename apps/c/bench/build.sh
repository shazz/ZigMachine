#!/usr/bin/env bash
# The BENCH cart's multi-file build, called by apps/c/build.sh:  bash bench/build.sh <out.wasm> <linker flags...>
#
# Not the one-file path the other C carts use: Dhrystone must be two separately compiled units (no cross-unit
# inlining), CoreMark's files must stay unmodified, and the K&R-style Dhrystone needs -std=gnu89, which is a
# per-file flag. Each source is compiled alone, then linked. Same reproducibility rules as build.sh: -g0 and
# --strip-debug, and the generated sources live in a temp dir whose name never reaches the output.
# No -nostdlib: the toolchain's compiler_rt is what supplies memcpy, sin, cos, exp and log (libm.a has no atan,
# kestrel/fmath.c has it, and the single-precision functions).
set -euo pipefail
cd "$(dirname "$0")"
ZIG="${ZIG:-$HOME/.local/zig/0.16.0/zig}"
OUT=$1; shift
BASE="$(pwd)/.."
GEN="$(mktemp -d "${TMPDIR:-/var/tmp}/benchgen.XXXXXX")"
trap 'rm -rf "$GEN"' EXIT
python3 -I kestrel/gen.py "$GEN"

CC=("$ZIG" cc -target wasm32-freestanding -O2 -g0 -ffreestanding -fno-builtin -mbulk-memory -Wno-everything -Werror=implicit-function-declaration
    -Ikestrel/shim -Ikestrel -Ikestrel/cm_port -Ithird_party/coremark -Idhry)
OBJ="$GEN/obj"; mkdir -p "$OBJ"
n=0
cc1() { n=$((n + 1)); "${CC[@]}" "$@" -c -o "$OBJ/$n.o" "${SRC}"; }

compile() { SRC=$1; shift; cc1 "$@"; }
for f in kestrel/rt.c kestrel/fmath.c kestrel/k_common.c kestrel/k_coremark.c kestrel/k_dhry.c kestrel/k_whet_d.c \
         kestrel/k_whet_f.c kestrel/k_lin_d.c kestrel/k_lin_f.c kestrel/k_mem.c kestrel/cm_main.c kestrel/cm_port/core_portme.c \
         third_party/coremark/core_list_join.c third_party/coremark/core_matrix.c third_party/coremark/core_state.c \
         third_party/coremark/core_util.c ../scenes/bench.c; do
    compile "$f"
done
compile "$GEN/dhry_1.c" -std=gnu89 -Wno-implicit-function-declaration -DHZ=1000000
compile "$GEN/dhry_2.c" -std=gnu89 -Wno-implicit-function-declaration -DHZ=1000000
for f in whet_d whet_f lin_d lin_f; do compile "$GEN/$f.c" -I"$GEN"; done

"$ZIG" cc -target wasm32-freestanding -O2 -g0 "$@" -Wl,--strip-debug -o "$OUT" "$OBJ"/*.o
