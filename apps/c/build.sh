#!/usr/bin/env bash
# Build the C "hello world" app against the sealed ZigMachine ABI.
# Output: docs/demo-c.wasm  ·  Run: docs/sealed.html?demo=demo-c.wasm
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

"$ZIG" cc -target wasm32-freestanding -O2 -ffreestanding -fno-builtin -mbulk-memory \
    -nostdlib "${LDFLAGS[@]}" -o "$OUT/demo-c.wasm" hello.c
ls -l "$OUT/demo-c.wasm"
echo "OK — run docs/sealed.html?demo=demo-c.wasm  (verify: node apps/verify.mjs docs/demo-c.wasm)"
