#!/bin/sh
# Build the wasm, then GATE on the cart RAM window.
#
# A cart whose static data + stack runs past CART_RAM_TOP does not trap — it
# writes into the video region and the machine dies later, somewhere unrelated
# (a 1 MB sample buffer cost a whole debugging session that way). The linker
# only catches an overflow past the WHOLE shared memory, so the check has to
# happen here, on every build.
set -e
clear
zig build -Drelease=true -Dwasm
node apps/check_fits.mjs docs/demo-*.wasm
node apps/ram_check.mjs
