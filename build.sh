#!/bin/sh
# Build the wasm, GATE on the cart RAM window, then repack the disks.
#
# The gate: a cart whose static data + stack runs past CART_RAM_TOP does not trap
# — it writes into the video region and the machine dies later, somewhere
# unrelated (a 1 MB sample buffer cost a whole debugging session that way). The
# linker only catches an overflow past the WHOLE shared memory, so the check has
# to happen here, on every build.
#
# The disks: .zmd images used to be build output with no recipe, so they drifted a
# week behind the wasm and froze an import list the host no longer had — every
# disk on the shelf failed to instantiate. mkdisks.sh only repacks what is
# actually stale, so a no-op build does not churn 29 binaries.
set -e
clear
zig build -Drelease=true -Dwasm
node apps/check_fits.mjs docs/demo-*.wasm
node apps/ram_check.mjs
tools/mkdisks.sh
node apps/disk_check.mjs
# The GEM/ROM regression scenarios. Shots go to a scratch dir so a build does
# not litter the repo; each scenario guards a specific fixed bug and the run
# exits non-zero if one regresses.
node apps/gem_headless.mjs "$(mktemp -d)"
