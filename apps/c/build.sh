#!/usr/bin/env bash
# Build C carts against the sealed ZigMachine ABI.
#
#   bash apps/c/build.sh             # every scene in scenes/
#   bash apps/c/build.sh screen34    # just that one
#
# Layout mirrors apps/zig/: one file per scene in scenes/, its generated data
# under assets/screens/<scene>/. Each scene builds to its OWN cart, the same way
# each Zig scene is its own cartridge.
#
#   scenes/hello.c     -> docs/demo-c.wasm            (the name verify.mjs and
#                                                      CLAUDE.md already use)
#   scenes/<name>.c    -> docs/demo-c-<name>.wasm
#
# Compiled with `zig cc` (bundled lld) so no system wasm-ld is needed.
set -euo pipefail
cd "$(dirname "$0")"
ZIG="${ZIG:-$HOME/.local/zig/0.16.0/zig}"
OUT=../../docs

# Layout MUST match build.zig's demo module: import the machine's ONE memory,
# keep data/stack in the 2 MiB demo window [0x100000..0x300000).
MEM=7340032; GLOBAL_BASE=1048576                 # 112*65536 (memmap.SHARED_PAGES) ; 0x100000
EXPORTS=(boot frame isPlaneEnabled hblDispatch skipBoot setShadeMode pointer input)
LDFLAGS=(-Wl,--no-entry -Wl,--import-memory
         -Wl,--initial-memory=$MEM -Wl,--max-memory=$MEM -Wl,--global-base=$GLOBAL_BASE)
for e in "${EXPORTS[@]}"; do LDFLAGS+=(-Wl,--export=$e); done

build_one() {
    scene=$1
    src="scenes/$scene.c"
    [ -f "$src" ] || { echo "no such scene: $src" >&2; return 1; }
    # hello keeps the historic cart name; everything else is demo-c-<scene>.
    if [ "$scene" = hello ]; then out="$OUT/demo-c.wasm"; else out="$OUT/demo-c-$scene.wasm"; fi

    # -g0 + --strip-debug: no DWARF. zig cc emits it by default, and its
    # .debug_str records the ABSOLUTE build directory, so the same source built
    # in another checkout or worktree gave different bytes. That made the cart
    # unreproducible and failed the pre-push "docs/ matches source" check. The
    # wasm `name` section stays, so stack traces still show function names.
    "$ZIG" cc -target wasm32-freestanding -O2 -g0 -ffreestanding -fno-builtin -mbulk-memory \
        -nostdlib "${LDFLAGS[@]}" -Wl,--strip-debug -o "$out" "$src"
    printf '%-34s %8d bytes   ?demo=%s\n' "$src" "$(stat -c%s "$out")" "$(basename "$out")"
}

if [ $# -gt 0 ]; then
    for s in "$@"; do build_one "$s"; done
else
    for src in scenes/*.c; do build_one "$(basename "$src" .c)"; done
fi
echo "OK — verify the ABI with: node apps/verify.mjs docs/demo-c.wasm"
