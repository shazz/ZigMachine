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
# LiteX's Verilator harness needs libevent + json-c headers. The runtime .so's are
# on the box but the -dev packages are not, so their Ubuntu (noble) .debs, the
# SAME versions as the installed runtimes, are unpacked into .tools/simdeps, no
# sudo. Their lib*.so symlinks are re-pointed at the installed runtimes: Vsim
# must link them dynamically, because the sim modules it dlopen()s (the UART
# console) call libevent through the executable's symbols.
UBUNTU_POOL=http://archive.ubuntu.com/ubuntu/pool/main
EVENT_DEB=libevent-dev_2.1.12-stable-9ubuntu2.2_amd64.deb
EVENT_SHA=4b57b127058ba4b97384605090ccf8cf099093c165d7a28923d8f2e5bdb05c0a
JSONC_DEB=libjson-c-dev_0.17-1build1_amd64.deb
JSONC_SHA=868dfc743f14612d676b801314eb0c296627ab6cb5e7c3271308f6b97a7b6507

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

echo "== Verilator sim headers (libevent, json-c)"
if [ ! -d "$TOOLS/simdeps/usr/include/event2" ]; then
    fetch "$UBUNTU_POOL/libe/libevent/$EVENT_DEB" "$EVENT_DEB" "$EVENT_SHA"
    fetch "$UBUNTU_POOL/j/json-c/$JSONC_DEB" "$JSONC_DEB" "$JSONC_SHA"
    rm -rf "$TOOLS/simdeps"
    for deb in "$EVENT_DEB" "$JSONC_DEB"; do dpkg-deb -x "$DL/$deb" "$TOOLS/simdeps"; done
    lib="$TOOLS/simdeps/usr/lib/x86_64-linux-gnu"
    ln -sf /lib/x86_64-linux-gnu/libevent-2.1.so.7 "$lib/libevent.so"
    ln -sf /lib/x86_64-linux-gnu/libjson-c.so.5 "$lib/libjson-c.so"
fi

# Only for custom VexRiscv netlists (vexgen/, CYCLES.md "Memory path"): SpinalHDL
# needs sbt and a JDK the pinned Scala 2.12 / sbt accept (the box's 21 is too new
# for VexRiscv's sbt 1.6). Opt in with ZM_VEXGEN=1; nothing else needs a JVM.
JDK_VER=11.0.32.1_1
JDK_SHA=5c3f68887c325d36d852ba534303e1f5f1f5cae7d6cc1e951d73e0d8e98a058d
SBT_VER=1.11.7
SBT_SHA=1232818f91c39639a93bbe1108e12d94c7044a646a7847f1a3977b9e46716cd6
if [ "${ZM_VEXGEN:-0}" = 1 ]; then
    echo "== JDK $JDK_VER + sbt $SBT_VER (custom VexRiscv cores)"
    if [ ! -x "$TOOLS/jdk/bin/java" ]; then
        fetch "https://github.com/adoptium/temurin11-binaries/releases/download/jdk-${JDK_VER%_*}%2B${JDK_VER##*_}/OpenJDK11U-jdk_x64_linux_hotspot_$JDK_VER.tar.gz" \
            "jdk-$JDK_VER.tar.gz" "$JDK_SHA"
        rm -rf "$TOOLS/jdk" && mkdir -p "$TOOLS/jdk"
        tar xzf "$DL/jdk-$JDK_VER.tar.gz" -C "$TOOLS/jdk" --strip-components=1
    fi
    if [ ! -x "$TOOLS/sbt/bin/sbt" ]; then
        fetch "https://github.com/sbt/sbt/releases/download/v$SBT_VER/sbt-$SBT_VER.tgz" "sbt-$SBT_VER.tgz" "$SBT_SHA"
        rm -rf "$TOOLS/sbt" && mkdir -p "$TOOLS/sbt"
        tar xzf "$DL/sbt-$SBT_VER.tgz" -C "$TOOLS/sbt" --strip-components=1
    fi
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
check riscv64-unknown-elf-gcc "cycles sim firmware (rv32im + picolibc)" "sudo apt install gcc-riscv64-unknown-elf picolibc-riscv64-unknown-elf"
echo "setup: done. Add $TOOLS/bin and $TOOLS/wabt/bin to PATH, or use the Makefile (it does)."
