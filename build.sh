#!/bin/sh
# Build the wasm, then GATE: RAM windows, native tests, disks, headless harnesses.
#
# The gate exists because the failures it catches are SILENT. A cart whose data +
# stack runs past its window does not trap — it writes into the video region (or,
# on the audio thread, into song RAM) and the machine dies later, somewhere
# unrelated. A .zmd freezes its cart's imports at pack time, so a host change
# leaves every disk on the shelf failing to instantiate. Neither shows up as a
# build error; both show up as a black screen an hour later.
#
# Everything here is fast and offline. Run it instead of `zig build`.
set -e
if [ -t 1 ]; then clear; fi # not from a git hook or a log redirect
zig build -Drelease=true -Dwasm

# --- memory windows: every module measured against ITS OWN map -------------
node apps/check_fits.mjs docs/demo-*.wasm docs/rom.wasm
node apps/ram_check.mjs
node apps/rom_abi_check.mjs   # the ROM survives hostile arguments from any language
node apps/blitter_check.mjs   # blitter sources: plane offsets, cart RAM (SRC_ABS), refusals

# --- ZX0: pack every asset (stale only) and report the ratios per screen ------
tools/pack_stats.sh

# --- native tests ----------------------------------------------------------
# Zig has no `test` step in build.zig, so name the files that hold tests. Add
# yours here when you write them, or the gate will not run them.
for t in \
    libs/zig/disk.zig \
    libs/zig/players/sndh.zig \
    libs/zig/depackers/ice_test.zig \
    libs/zig/depackers/zx0_test.zig \
    libs/zig/depackers/depack_fx.zig \
    libs/zig/effects/charpanel_test.zig \
    libs/zig/effects/blit_test.zig \
    libs/zig/effects/copper_test.zig \
    libs/zig/effects/palette_test.zig \
    libs/zig/effects/scrollring_test.zig \
    libs/zig/effects/wave_test.zig \
    libs/zig/effects/spans_test.zig \
    libs/zig/shapes_test.zig \
    libs/zig/tvnoise/tvnoise.zig \
    apps/zig/scene_tests.zig \
    rom/gem/desktop/namefield.zig \
    rom/gem/desktop/stamp.zig \
    rom/gem/desktop/dirmodel_test.zig \
    rom/gem/desktop/deskinf.zig \
    rom/gem/gui/grid.zig \
    apps/zig/scenes/stniccc/stream.zig \
    apps/zig/scenes/stniccc/polyfill.zig \
    apps/zig/scenes/stniccc/player.zig
do
    printf '%-42s ' "$t"
    zig test "$t" 2>&1 | tail -1
done

# --- disks: repack what is stale, then mount and instantiate every image ----
tools/mkdisks.sh
python3 tools/channels.py     # the monitor's +/- channel list (needs the disks)
node apps/disk_check.mjs

# --- headless harnesses: each drives the real machine end to end -----------
# Shots go to a scratch dir so a build does not litter the repo. These cover
# BOTH halves of the machine — GEM/ROM and the audio/SNDH side — because a host
# or ABI change breaks whichever one you were not thinking about.
SHOTS=$(mktemp -d)
node apps/verify.mjs          # the C and Rust carts still talk to the ABI
node apps/gem_headless.mjs "$SHOTS"
node apps/sndh_headless.mjs
node apps/c_music_check.mjs   # a C cart's song request reaches the sealed YM
node apps/dbug_headless.mjs "$SHOTS"
echo "shots in $SHOTS"
