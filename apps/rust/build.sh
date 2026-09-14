#!/usr/bin/env bash
# Build the Rust (no_std) carts against the sealed ZigMachine ABI.
#
#   bash apps/rust/build.sh                # hello + every scene in scenes/
#   bash apps/rust/build.sh v8_populous    # just that scene
#
# Layout mirrors apps/c/: one crate root per scene in scenes/ (its private
# submodules in scenes/<name>/), its generated data under assets/screens/<name>/.
# Each scene builds to its OWN cart, the way each Zig scene is its own cartridge.
#
#   hello.rs              -> docs/demo-rust.wasm         (the name verify.mjs uses)
#   scenes/<name>.rs      -> docs/demo-rust-<name>.wasm
#
# Uses rustc's bundled rust-lld, so no system wasm-ld is needed. Requires the
# wasm32-unknown-unknown target: rustup target add wasm32-unknown-unknown
set -euo pipefail
cd "$(dirname "$0")"
OUT=../../docs

# Layout MUST match build.zig's demo module (see apps/c/build.sh for the why).
MEM=7340032; GLOBAL_BASE=1048576                 # 112*65536 (memmap.SHARED_PAGES) ; 0x100000
EXPORTS=(boot frame isPlaneEnabled hblDispatch skipBoot setShadeMode pointer input)
LDFLAGS=(-C link-arg=--no-entry -C link-arg=--import-memory
         -C link-arg=--initial-memory=$MEM -C link-arg=--max-memory=$MEM
         -C link-arg=--global-base=$GLOBAL_BASE)
for e in "${EXPORTS[@]}"; do LDFLAGS+=(-C link-arg=--export=$e); done
LDFLAGS+=(-C link-arg=--export-if-defined=tuneIn) # zigmachine_tvnoise.rs, where declared (see apps/c/build.sh)

build() { # <crate root .rs> <out .wasm>
    # strip=debuginfo: a scene with bounds checks links libcore's panic formatting,
    # and the prebuilt libcore brings ~600 KB of DWARF with it into the 2 MB window.
    rustc --target wasm32-unknown-unknown --edition 2021 -C opt-level=2 -C strip=debuginfo \
        --crate-type cdylib "${LDFLAGS[@]}" -o "$2" "$1"
    printf '%-34s %8d bytes   ?demo=%s\n' "$1" "$(stat -c%s "$2")" "$(basename "$2")"
}

if [ $# -gt 0 ]; then
    for s in "$@"; do
        [ -f "scenes/$s.rs" ] || { echo "no such scene: scenes/$s.rs" >&2; exit 1; }
        build "scenes/$s.rs" "$OUT/demo-rust-$s.wasm"
    done
else
    build hello.rs "$OUT/demo-rust.wasm"
    for src in scenes/*.rs; do build "$src" "$OUT/demo-rust-$(basename "$src" .rs).wasm"; done
fi
echo "OK — verify the ABI with: node apps/verify.mjs docs/demo-rust.wasm"
