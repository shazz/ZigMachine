#!/usr/bin/env bash
# The KESTREL SDK's doctor (docs/SDK.md): checks every tool a cart build needs, with its version,
# and says how to install what is missing, on Linux (Ubuntu / Arch) and macOS.
#
#   tools/sdk_doctor.sh                 check; exit 1 if something the browser build needs is missing
#   tools/sdk_doctor.sh --fetch-wabt    also download wabt 1.0.42 (Linux x64, sha256-pinned) into fpga/.tools/wabt
#
# Two levels: BROWSER (make, make floppy) needs zig 0.16.0 + python3; BOARD (make board) also
# needs wabt, clang, uv and a riscv gcc that compiles rv32imf/ilp32f. A missing BOARD tool is a
# warning unless --board is given.
set -u
SDK="$(cd "$(dirname "$0")/.." && pwd)"
OS="$(uname -s)"
FETCH=0; BOARD=0
for a in "$@"; do
    case "$a" in
        --fetch-wabt) FETCH=1 ;;
        --board) BOARD=1 ;;
        *) echo "usage: $0 [--fetch-wabt] [--board]"; exit 2 ;;
    esac
done
fail=0; warn=0
ok()   { printf '  ok    %-10s %s\n' "$1" "$2"; }
bad()  { printf '  MISS  %-10s %s\n' "$1" "$2"; fail=$((fail + 1)); }
soft() { if [ "$BOARD" = 1 ]; then bad "$@"; else printf '  warn  %-10s %s\n' "$1" "$2"; warn=$((warn + 1)); fi; }
hint() { if [ "$OS" = Darwin ]; then echo "$2"; else echo "$1"; fi; }

echo "== browser: make, make floppy"
if command -v zig >/dev/null; then
    v=$(zig version)
    if [ "$v" = 0.16.0 ]; then ok zig "$v"; else bad zig "$v, need 0.16.0 (https://ziglang.org/download/#release-0.16.0)"; fi
else bad zig "not on PATH: https://ziglang.org/download/#release-0.16.0"; fi
if command -v python3 >/dev/null && python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))'; then
    ok python3 "$(python3 --version 2>&1)"
else bad python3 "need 3.11+ ($(hint 'apt/pacman install python3' 'brew install python'))"; fi
if command -v make >/dev/null; then ok make "$(make --version | head -1)"; else bad make "$(hint 'install make' 'xcode-select --install')"; fi
nv="$(node --version 2>/dev/null || true)"  # only the SDK's own test (apps/sdk_check.mjs) needs node, and 24+
major="$(echo "${nv#v}" | cut -d. -f1)"
if [ -n "$nv" ] && [ "$major" -ge 24 ] 2>/dev/null; then ok node "$nv"
else printf '  warn  %-10s %s\n' node "${nv:-none}: optional, node 24+ runs the SDK's own test (apps/sdk_check.mjs)"; warn=$((warn + 1)); fi

echo "== board: make board"
WABT="$SDK/fpga/.tools/wabt"
if [ "$FETCH" = 1 ] && [ ! -x "$WABT/bin/wasm2c" ]; then
    if [ "$OS" = Linux ] && [ "$(uname -m)" = x86_64 ]; then
        tgz="$(mktemp -d)/wabt.tar.gz"
        curl -fsSL -o "$tgz" https://github.com/WebAssembly/wabt/releases/download/1.0.42/wabt-1.0.42-linux-x64.tar.gz
        if echo "84895407a6bbb80e918f33b16b2fb2206021c150b6bc9ff6f761263a745ab131  $tgz" | sha256sum -c --quiet -; then
            mkdir -p "$WABT" && tar xzf "$tgz" -C "$WABT" --strip-components=1
        else echo "  wabt: checksum mismatch, not installed"; fi
        rm -f "$tgz"
    else echo "  --fetch-wabt: Linux x64 only; $(hint 'install your distro wabt' 'brew install wabt')"; fi
fi
w2c=""
if [ -x "$WABT/bin/wasm2c" ]; then w2c="$WABT/bin/wasm2c"; elif command -v wasm2c >/dev/null; then w2c="$(command -v wasm2c)"; fi
if [ -n "$w2c" ]; then
    rt="$(dirname "$w2c")/../share/wabt/wasm2c/wasm-rt-impl.c"
    if [ -f "$rt" ]; then ok wasm2c "$("$w2c" --version) ($w2c)"
    else soft wasm2c "$w2c has no share/wabt/wasm2c runtime beside it: use $0 --fetch-wabt or a wabt release"; fi
else soft wasm2c "$(hint "$0 --fetch-wabt (or: pacman -S wabt / apt install wabt)" 'brew install wabt')"; fi
if command -v clang >/dev/null; then ok clang "$(clang --version | head -1)"; else soft clang "$(hint 'apt/pacman install clang' 'xcode-select --install')"; fi
if command -v uv >/dev/null; then ok uv "$(uv --version)"; else soft uv "https://docs.astral.sh/uv/ (curl -LsSf https://astral.sh/uv/install.sh | sh)"; fi

rv=""
for p in riscv64-unknown-elf- riscv64-elf- riscv-none-elf-; do
    if command -v "${p}gcc" >/dev/null; then rv="$p"; break; fi
done
if [ -z "$rv" ]; then
    soft riscv-gcc "$(hint 'Ubuntu: apt install gcc-riscv64-unknown-elf picolibc-riscv64-unknown-elf; Arch: pacman -S riscv64-elf-gcc riscv64-elf-newlib' 'xPack riscv-none-elf-gcc (https://xpack-dev-tools.github.io/riscv-none-elf-gcc-xpack/)')"
else
    probe="$(mktemp -d)"
    printf '#include <stdint.h>\n#include <string.h>\n#include <setjmp.h>\nfloat f(float a, int64_t b){ return a * (float)(b / 3); }\n' >"$probe/t.c"
    libc=newlib; spec=""
    if echo | "${rv}gcc" --specs=picolibc.specs -march=rv32im -mabi=ilp32 -E - >/dev/null 2>&1; then libc=picolibc; spec=--specs=picolibc.specs; fi
    if "${rv}gcc" $spec -march=rv32imf -mabi=ilp32f -O2 -c "$probe/t.c" -o "$probe/t.o" 2>"$probe/err"; then
        multi="$("${rv}gcc" -march=rv32imf -mabi=ilp32f -print-multi-directory)"
        if [ "$multi" = rv32imf/ilp32f ]; then rt="its libgcc (rv32imf/ilp32f multilib)"
        else rt="no rv32imf/ilp32f multilib: the cart links Zig's compiler_rt (zig-out/rt/libzrt.a)"; fi
        ok riscv-gcc "${rv}gcc $("${rv}gcc" -dumpversion), $libc headers, $rt"
    else soft riscv-gcc "${rv}gcc cannot compile rv32imf/ilp32f: $(head -1 "$probe/err")"; fi
    rm -rf "$probe"
fi

echo "== the SDK: $SDK"
for f in docs/machine-video.wasm docs/rom.wasm docs/sealed.html build.zig sdk/build_cart.zig; do
    if [ -f "$SDK/$f" ]; then ok sdk "$f"; else bad sdk "$f missing: a broken SDK unpack"; fi
done
if [ -f "$SDK/../RELEASE.txt" ]; then ok release "$(grep -m1 '^kestrel' "$SDK/../RELEASE.txt")"; fi

echo
if [ "$fail" -gt 0 ]; then echo "sdk_doctor: $fail missing, $warn warnings"; exit 1; fi
echo "sdk_doctor: ready ($warn warnings)"
