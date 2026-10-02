#!/usr/bin/env bash
# Sets up everything fpga/ needs that is not in git, pinned and checksummed:
#   - the third_party/ cores (git submodules, shallow)
#   - the Python env (uv: LiteX, Migen, VexRiscv netlists, Yosys-in-wasm, pytest)
#   - sv2v (SystemVerilog -> Verilog, for fx68k and hdl-util/hdmi) and wabt
#     (wasm2c, for the cart translation of plan step 0) into fpga/.tools/
# Then reports the optional system tools (Verilator, openXC7, Vivado).
# Idempotent: re-running skips whatever is already in place.
set -euo pipefail

FPGA="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$FPGA/.tools"
DL="$FPGA/build/dl"
mkdir -p "$TOOLS/bin" "$DL"

SV2V_VER=v0.0.13
SV2V_SHA=552799a1d76cd177b9b4cc63a3e77823a3d2a6eb4ec006569288abeff28e1ff8
WABT_VER=1.0.42
WABT_SHA=84895407a6bbb80e918f33b16b2fb2206021c150b6bc9ff6f761263a745ab131

fetch() {  # fetch <url> <file> <sha256>: download once, refuse on a checksum mismatch
    local url=$1 file=$DL/$2 sha=$3
    [ -f "$file" ] || curl -fsSL -o "$file" "$url"
    if ! echo "$sha  $file" | sha256sum -c --quiet -; then
        echo "setup: checksum mismatch for $file (deleted, re-run to retry)" >&2
        rm -f "$file"
        exit 1
    fi
}

echo "== cores (git submodules)"
git -C "$FPGA/.." submodule update --init --depth 1 fpga/third_party

echo "== python env (uv)"
(cd "$FPGA" && uv sync --quiet)

echo "== sv2v $SV2V_VER"
if [ ! -x "$TOOLS/bin/sv2v" ]; then
    fetch "https://github.com/zachjs/sv2v/releases/download/$SV2V_VER/sv2v-Linux.zip" sv2v-Linux.zip "$SV2V_SHA"
    unzip -o -q -j "$DL/sv2v-Linux.zip" 'sv2v-Linux/sv2v' -d "$TOOLS/bin"
fi

echo "== wabt $WABT_VER (wasm2c)"
if [ ! -x "$TOOLS/wabt/bin/wasm2c" ]; then
    fetch "https://github.com/WebAssembly/wabt/releases/download/$WABT_VER/wabt-$WABT_VER-linux-x64.tar.gz" \
        "wabt-$WABT_VER.tar.gz" "$WABT_SHA"
    rm -rf "$TOOLS/wabt" && mkdir -p "$TOOLS/wabt"
    tar xzf "$DL/wabt-$WABT_VER.tar.gz" -C "$TOOLS/wabt" --strip-components=1
fi

echo "== optional system tools"
check() {  # check <binary> <what it is for> <how to get it>
    if command -v "$1" >/dev/null 2>&1; then printf '  %-16s ok      %s\n' "$1" "$2"
    else printf '  %-16s missing %s -> %s\n' "$1" "$2" "$3"; fi
}
check verilator "full-SoC simulation (LiteX sim)" "sudo apt install verilator"
check iverilog "cocotb runs" "sudo apt install iverilog"
check docker "openXC7 bitstreams (container)" "https://github.com/openXC7"
check vivado "fallback bitstream flow" "Vivado ML Standard (free licence)"
check clang "cart translation (rv32 target)" "sudo apt install clang"
echo "setup: done. Add $TOOLS/bin and $TOOLS/wabt/bin to PATH, or use the Makefile (it does)."
