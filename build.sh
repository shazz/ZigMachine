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
# The C and Rust carts have their own build scripts, which zig build does not run.
# Rebuilding them here (both are byte-for-byte deterministic) is what lets the
# pre-push hook's "docs/ matches the source" check catch a stale demo-c*.wasm or
# demo-rust.wasm; before this, only c_music_check crashing on one found it.
bash apps/c/build.sh > /dev/null
if command -v rustc > /dev/null 2>&1; then bash apps/rust/build.sh > /dev/null; fi

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
    libs/zig/depackers/tex_loader.zig \
    libs/zig/depackers/tex_loader_test.zig \
    libs/zig/effects/charpanel_test.zig \
    libs/zig/effects/blit_test.zig \
    libs/zig/effects/copper_test.zig \
    libs/zig/effects/palette_test.zig \
    libs/zig/effects/scrollring_test.zig \
    libs/zig/effects/wave_test.zig \
    libs/zig/effects/spans_test.zig \
    libs/zig/effects/tilegrid_test.zig \
    libs/zig/effects/codef3d_test.zig \
    libs/zig/effects/canvas_poly_test.zig \
    libs/zig/shapes_test.zig \
    libs/zig/wireframe_test.zig \
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
    # NOT `zig test | tail -1`: a pipeline's status is tail's, so a failing test
    # printed only its binary path and the gate went on green (tnt3's codef3d and
    # canvas_poly tests). Keep the output, test zig's own status, fail at the end.
    if out=$(zig test "$t" 2>&1); then
        printf '%s\n' "$out" | tail -1
    else
        echo "FAILED"
        printf '%s\n' "$out" | tail -20
        tests_failed="$tests_failed $t"
    fi
done
if [ -n "$tests_failed" ]; then
    echo "native tests: FAILED ❌$tests_failed"
    exit 1
fi

# --- disks: repack what is stale, then mount and instantiate every image ----
tools/mkdisks.sh
python3 tools/channels.py     # the monitor's +/- channel list (needs the disks)
python3 tools/cache_bust.py   # docs/*.html ?v= = content hash of each script/CSS (stale-cache guard)
python3 tools/gen_docs.py --check   # ZIGMACHINE_GUIDE.html regenerated from MUSIC.md, FLOPPY_DISK.md and the sources
node apps/disk_check.mjs
node apps/upload_check.mjs    # an uploaded disk mounts exactly like a URL one; bad uploads refused

# --- headless harnesses: each drives the real machine end to end -----------
# Shots go to a scratch dir so a build does not litter the repo. These cover
# BOTH halves of the machine — GEM/ROM and the audio/SNDH side — because a host
# or ABI change breaks whichever one you were not thinking about.
SHOTS=$(mktemp -d)
node apps/verify.mjs          # the C and Rust carts still talk to the ABI
node apps/gem_headless.mjs "$SHOTS"
node apps/sndh_headless.mjs
node apps/sndh_relocate_check.mjs   # a tune that installs its own MFP vectors (Alloy Run) plays: images load at $10002
timeout 180 node apps/c_music_check.mjs   # a C cart's song request reaches the sealed YM (timeout: it once hung a gate)
node apps/union_demo_music_check.mjs   # the Union Demo menu's and cracktro's SNDH tunes are requested by name and play
node apps/union_demo_music_check.mjs --fail-proof   # ...and a wrong tune name fails that check
node apps/union_intro_music_check.mjs   # the cracktro's music starts with the TRSI logo, and main doesn't restart it
node apps/union_intro_music_check.mjs --fail-proof   # ...and a wrong tune name fails that check
node apps/union_demo_doors_check.mjs   # the hub's doors launch the Union screens by tag (they are hub-only)
node apps/union_demo_headless.mjs "$SHOTS/union_demo"   # hub: street wraps, view eases, keys stop at 60/144 Hz and on key-up, door memory
node apps/union_demo_headless.mjs --break return "$SHOTS/union_demo"   # ...and a lost ROM note fails the door-memory check
node apps/union_multifake_headless.mjs "$SHOTS"   # TCB3: loader depack, then screen.js replayed pixel for pixel
node apps/dbug_headless.mjs "$SHOTS"
node apps/fallen_angels_headless.mjs "$SHOTS"   # per-plane rasters on all 200 lines
node apps/tex_loader_fx_headless.mjs "$SHOTS/tex_loader_fx"   # fx = tex_loader on a real asset, bytes checked
node apps/tex_headless.mjs "$SHOTS"             # the eleven sprites on screen.js's chain
node apps/equinox_headless.mjs "$SHOTS"   # the dragons morph egg -> dragon -> egg
node apps/mpp_truecolor_headless.mjs "$SHOTS"   # per-line palettes: colours on screen = captions
node apps/union_textracker_headless.mjs "$SHOTS"   # TEX loader depack, then screen.js replayed pixel for pixel
node apps/union_demo_intro_headless.mjs "$SHOTS"   # TEX loader depack, then every pixel on the screen.js replay
node apps/stream_pacing_check.mjs   # streamed audio tracks wall time at 18 fps, 144 Hz and across a 3 s stall
node apps/union_deltaforce_headless.mjs "$SHOTS"   # DELTA FORCE: TEX loader depack, screen.js replayed pixel for pixel, the SNDH plays
node apps/union_texcopier_headless.mjs "$SHOTS"   # COPIER TEX: loader depack, screen.js replay incl. Chrome's blends, Scoop plays
echo "shots in $SHOTS"
