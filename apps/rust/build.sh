#!/usr/bin/env bash
# Build the Rust (no_std) "hello world" app against the sealed ZigMachine ABI.
# Output: docs/demo-rust.wasm  ·  Run: docs/sealed.html?demo=demo-rust.wasm
# Uses rustc's bundled rust-lld, so no system wasm-ld is needed. Requires the
# wasm32-unknown-unknown target: rustup target add wasm32-unknown-unknown
set -euo pipefail
cd "$(dirname "$0")"
OUT=../../docs

# Layout MUST match build.zig's demo module (see apps/c/build.sh for the why).
MEM=5177344; GLOBAL_BASE=1048576                 # 79*65536 ; 0x100000
EXPORTS=(boot frame isPlaneEnabled hblDispatch skipBoot setShadeMode pointer input)
LDFLAGS=(-C link-arg=--no-entry -C link-arg=--import-memory
         -C link-arg=--initial-memory=$MEM -C link-arg=--max-memory=$MEM
         -C link-arg=--global-base=$GLOBAL_BASE)
for e in "${EXPORTS[@]}"; do LDFLAGS+=(-C link-arg=--export=$e); done

rustc --target wasm32-unknown-unknown --edition 2021 -C opt-level=2 \
    --crate-type cdylib "${LDFLAGS[@]}" -o "$OUT/demo-rust.wasm" hello.rs
ls -l "$OUT/demo-rust.wasm"
echo "OK — run docs/sealed.html?demo=demo-rust.wasm  (verify: node apps/verify.mjs docs/demo-rust.wasm)"
