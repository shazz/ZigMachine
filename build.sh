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

# --- selective gate: --only <tags> / --changed [<rev>] ----------------------
# The DEFAULT is the full gate. --only is an inner-loop convenience; --changed
# is also what the pre-push hook runs, so its rules are conservative.
#
# Only the per-screen HARNESSES are ever narrowed. Every mode still rebuilds
# every cart and disk and runs every cross-cutting check (windows, ABI, disks,
# native tests), because the failures this gate catches are silent and
# CROSS-CUTTING: a change under libs/, rom/, machine/, docs/*.js or build.zig can
# break a screen whose own files never changed. tools/gate_scope.py decides which
# harnesses a diff can reach, and anything it cannot place is the full gate.
# See docs/BUILDING.md.
ONLY=""
FAST=""
CHANGED_BASE=""
case "${1:-}" in
    --fast)
        # Compile and repack the disks, then STOP: no windows, no tests, no
        # harnesses. For the edit-reload-look loop only -- it proves nothing.
        # It still runs mkdisks because the browser fetches demo-<tag>.zmd, not
        # the .wasm: skipping it would serve the PREVIOUS cart from a build that
        # looked successful, which is the exact silent staleness this gate is for.
        FAST=1
        ;;
    --only)
        # ALL remaining arguments are tags. Reading only $2 meant a second
        # --only was dropped on the floor and the gate still exited green.
        shift
        [ $# -gt 0 ] || { echo "--only needs a screen tag, e.g. --only stniccc" >&2; exit 2; }
        ONLY="$*"
        ;;
    --changed)
        # Everything changed since <rev> (default: the branch's merge-base with
        # origin/main, not HEAD: diffing HEAD alone means the first commit empties
        # the set exactly while you are iterating in small commits). Working tree
        # and untracked files included. The scope is computed AFTER the build (see
        # changed_scope below), so a shared scene file that changed another cart's
        # bytes shows up as that cart's docs/demo-<tag>.wasm and pulls it in too.
        CHANGED_BASE=${2:-$(git merge-base HEAD origin/main 2>/dev/null || echo HEAD)}
        git rev-parse -q --verify "$CHANGED_BASE^{commit}" > /dev/null \
            || { echo "--changed: unknown revision '$CHANGED_BASE'" >&2; exit 2; }
        ;;
    "") ;;
    *) echo "build.sh: unknown option '$1' (--fast | --only <tags> | --changed [<rev>])" >&2; exit 2 ;;
esac
if [ -n "$ONLY" ]; then
    # A tag matching no gate line would run ZERO screen harnesses and still exit
    # 0 -- a check that did not run and said it passed. Refuse instead.
    _tags=$(grep -oE '^gate(_timed)? [A-Za-z0-9_]+' "$0" | cut -d' ' -f2 | sort -u)
    for _s in $ONLY; do
        _hit=0
        for _t in $_tags; do case "$_t" in *"$_s"*) _hit=1 ;; esac; done
        [ "$_hit" = 1 ] || { echo "--only: no harness tag matches '$_s'" >&2; exit 2; }
    done
    echo "SELECTIVE GATE - screens: $ONLY"
    echo "  (cross-cutting checks still run; use a bare ./build.sh before pushing)"
    # Matching is substring and over-inclusive on purpose -- for a gate, running
    # more is the safe error. It CANNOT express a screen reached through another
    # screen: --only big_demo does NOT pull in digital_solution, which runs from
    # demo-big_demo.wasm. Name both, use --changed, or use the bare gate.
fi

# The green stamp (tools/gate_stamp.sh): a FULL gate that starts AND ends on a
# clean tree records that tree, and the pre-push hook will not gate it again.
STAMPABLE=""
if [ -z "$FAST$ONLY" ] && sh tools/gate_stamp.sh clean; then STAMPABLE=1; fi

# gate / gate_timed / always / run_gates: the harness queue (parallel, bounded)
. tools/gate_lib.sh

# Local-only art, not cleared to publish: TC TEST's pictures (tools/tc_art.py). A cart built
# with it must not be committed: look, then rebuild without the variable before committing docs/.
set --
if [ -n "${ZM_TC_ART:-}" ]; then
    echo "ZM_TC_ART=$ZM_TC_ART: docs/demo-tc_test.* carries LOCAL pictures, do not commit it"
    set -- "$@" -Dtc-art="$ZM_TC_ART"
fi
zig build -Drelease=true -Dwasm "$@"

# --fast stops here. The C and Rust carts are NOT rebuilt (slow, and irrelevant
# to a Zig scene edit), so a --fast build is never a pushable one.
if [ -n "$FAST" ]; then
    tools/mkdisks.sh
    # channels.py too: without it a BRAND-NEW screen is missing from
    # docs/channels.json, ?channel=<tag> silently falls back to another channel,
    # and you test the wrong cart believing it is yours. Exactly the silent
    # staleness --fast repacks the disks to avoid, so it belongs here as well.
    python3 tools/channels.py
    echo "FAST BUILD - wasm + disks + channels. NOTHING was checked."
    echo "  Run ./build.sh --only <screen>, and a bare ./build.sh before pushing."
    exit 0
fi

# The C and Rust carts have their own build scripts, which zig build does not run.
# Rebuilding them here (both are byte-for-byte deterministic) is what lets the
# pre-push hook's "docs/ matches the source" check catch a stale demo-c*.wasm or
# demo-rust.wasm; before this, only c_music_check crashing on one found it.
bash apps/c/build.sh > /dev/null
if command -v rustc > /dev/null 2>&1; then bash apps/rust/build.sh > /dev/null; fi

# --- memory windows: every module measured against ITS OWN map -------------
node apps/check_fits.mjs docs/demo-*.wasm docs/rom.wasm
node apps/zero_segments.mjs docs/demo-*.wasm   # no zero-filled static of 64 KB+ in a data section (use zg.mem / hwRamAlloc)
node apps/zero_segments.mjs --break            # ...and a synthetic cart with a 70 KB zero segment is caught
node apps/ram_check.mjs
early rom_abi node apps/rom_abi_check.mjs   # the ROM survives hostile arguments from any language (~40 s: started in the background, reported with the harnesses)
python3 fpga/tools/sys_abi.py --check   # the board's system table (fpga/cycles/sys_abi.txt) is today's ROM/machine exports, under the version that says so
python3 fpga/tools/sys_abi.py --break   # ...and a table changed without a version bump is caught (lean carts would bind to the wrong entries)
node apps/blitter_check.mjs   # blitter sources: plane offsets, cart RAM (SRC_ABS), refusals
node apps/blitter_queue_check.mjs   # QUEUE (1.8.0): a descriptor list draws what its ops draw one by one; the edges
node apps/beam_check.mjs      # BEAM (1.6.0): mid-line colour-0 cells across the whole line, persistence, no drops
node apps/beam_check.mjs --break   # ...and writes 4 px apart (faster than a move.w) are caught and counted as drops
node apps/linebase_check.mjs  # copper LBASE + overscan HSCROLL (1.10.0): line lists against a model, frame reset, the stop
node apps/linebase_check.mjs --break   # ...and a model missing any one rule is caught

# --- ZX0: pack every asset (stale only) and report the ratios per screen ------
tools/pack_stats.sh

# --- native tests ----------------------------------------------------------
# Zig has no `test` step in build.zig, so name the files that hold tests. Add
# yours here when you write them, or the gate will not run them.
NATIVE_TESTS="
    libs/zig/disk.zig
    libs/zig/players/sndh.zig
    libs/zig/players/mfp_test.zig
    libs/zig/players/digi_test.zig
    libs/zig/players/digi_monty_test.zig
    libs/zig/players/digi_wow_test.zig
    libs/zig/players/digi_big_test.zig
    libs/zig/players/digi_big_play_test.zig
    libs/zig/players/digi_mix4_test.zig
    libs/zig/players/digi_mix3_test.zig
    libs/zig/players/digi_mym_test.zig
    libs/zig/players/digi_tcb_test.zig
    libs/zig/players/digi_sync4_test.zig
    libs/zig/players/digi_quartet_test.zig
    machine/audio/pokey_test.zig
    libs/zig/players/cpu6502_test.zig
    libs/zig/players/sap_test.zig
    libs/zig/players/hip_format_test.zig
    libs/zig/players/amiga_beam_test.zig
    libs/zig/players/cart_paula_queue_test.zig
    libs/zig/players/sid_live_test.zig
    libs/zig/players/mod_format_test.zig
    libs/zig/players/xm_format_test.zig
    libs/zig/players/xm_instr_test.zig
    libs/zig/players/xm_mix_test.zig
    libs/zig/players/xm_ring_test.zig
    libs/zig/players/kt_core_test.zig
    libs/zig/sfx_queue_test.zig
    libs/zig/depackers/ice_test.zig
    libs/zig/depackers/zx0_test.zig
    libs/zig/depackers/depack_fx.zig
    libs/zig/depackers/tex_loader.zig
    libs/zig/depackers/tex_loader_test.zig
    libs/zig/effects/charpanel_test.zig
    libs/zig/effects/blit_test.zig
    libs/zig/effects/blit_rows_test.zig
    libs/zig/effects/chisel_clear_test.zig
    libs/zig/effects/chisel_copy_test.zig
    libs/zig/effects/blit_list_test.zig
    libs/zig/effects/sprite_draw_test.zig
    libs/zig/effects/scrolltext2_test.zig
    libs/zig/effects/parallax_test.zig
    libs/zig/effects/tilemap_test.zig
    libs/zig/effects/text_plot_test.zig
    libs/zig/effects/glyph_line_test.zig
    libs/zig/effects/copper_test.zig
    libs/zig/effects/linelist_test.zig
    libs/zig/effects/palette_test.zig
    libs/zig/effects/scrollring_test.zig
    libs/zig/effects/pathchain_test.zig
    libs/zig/effects/wave_test.zig
    libs/zig/effects/fixtrig_test.zig
    libs/zig/effects/spans_test.zig
    libs/zig/effects/ballfield_test.zig
    libs/zig/effects/chrome_draw_test.zig
    libs/zig/effects/linepal_test.zig
    libs/zig/effects/spanfont_test.zig
    libs/zig/effects/tilegrid_test.zig
    libs/zig/effects/zig3d_test.zig
    libs/zig/effects/zig3d_fixed_test.zig
    libs/zig/effects/zig3d_fixed_int_test.zig
    libs/zig/effects/zig3d_sparse_test.zig
    libs/zig/effects/canvas_poly_test.zig
    libs/zig/effects/canvas_poly_fixed_test.zig
    libs/zig/effects/canvas_poly_fixed_prev_test.zig
    libs/zig/effects/span_fill_test.zig
    libs/zig/effects/colour_bank_test.zig
    libs/zig/effects/beam_test.zig
    machine/beam_test.zig
    machine/copper_test.zig
    machine/copper_lbase_test.zig
    machine/video_tc_test.zig
    machine/video_tc_fade_test.zig
    machine/video_desk_test.zig
    libs/zig/vram_pool.zig
    apps/zig/scenes/desk_test/picture.zig
    machine/audio/ym_test.zig
    machine/audio/ym_env_test.zig
    machine/audio/ym_dac_test.zig
    machine/arena_test.zig
    libs/zig/mem_test.zig
    libs/zig/truecolor.zig
    libs/zig/libm_f32_test.zig
    libs/zig/sndh_call_test.zig
    libs/zig/shapes_test.zig
    libs/zig/wireframe_test.zig
    libs/zig/tvnoise/tvnoise.zig
    apps/zig/scene_tests.zig
    rom/gem/desktop/namefield.zig
    rom/gem/desktop/stamp.zig
    rom/gem/desktop/dirmodel_test.zig
    rom/kos/fat_test.zig
    rom/kos/gemdos_test.zig
    rom/kos/gemdos_wtest.zig
    rom/kos/kfs_path.zig
    rom/gem/desktop/deskinf.zig
    rom/gem/desktop/deskinf_read.zig
    rom/gem/gui/grid.zig
    rom/gem/gui/screen.zig
    rom/gem/gui/formalert.zig
    rom/gem/gui/saveunder.zig
    rom/gem/scrollpage_test.zig
    rom/gem/desktop/deskflip.zig
    rom/gem/desktop/deskarrow.zig
    rom/gem/engine/engine_test.zig
    apps/zig/scenes/stniccc/stream.zig
    apps/zig/scenes/stniccc/polyfill_test.zig
    apps/zig/scenes/mp3_player/id3_test.zig
    apps/zig/scenes/bard_sid/tune.zig
    libs/zig/players/mp3_frame_test.zig
    libs/zig/players/mp3_in_test.zig
    libs/zig/players/mp3_resample_test.zig
    apps/zig/scenes/stniccc/span.zig
    apps/zig/scenes/stniccc/player_test.zig
    apps/zig/scenes/union/wab_table_test.zig
    apps/zig/scenes/ancool/stars_test.zig
    apps/zig/scenes/union/dragonball_squash.zig
    apps/zig/scenes/union/dragonball_raster_test.zig
    apps/zig/scenes/union/wave_sin_test.zig
    apps/zig/scenes/union/fixsin.zig
    apps/zig/scenes/union/f32emu.zig
    apps/zig/scenes/blitter_demo/wobble.zig
    apps/zig/scenes/blitter_demo/soft.zig
    apps/zig/scenes/leonard_spirit/ball_test.zig
    apps/zig/scenes/gen4_3615/fate_test.zig
    apps/zig/scenes/mindwind/gen_test.zig
    apps/zig/scenes/c64_1988/tables_test.zig
    apps/zig/scenes/c64_1988/vic_test.zig
    apps/zig/scenes/c64_1988/show_test.zig
    apps/zig/scenes/c64_transmission64/vic_test.zig
    apps/zig/scenes/c64_transmission64/show_test.zig
"
# Compiled and run GATE_TEST_JOBS (default 4) at a time -- the zig cache is
# safe to share, and a zig test is CPU, not RAM, bound -- then
# printed in list order. NOT `zig test | tail -1`: a pipeline's status is
# tail's, so a failing test printed only its binary path and the gate went on
# green (tnt3's zig3d and canvas_poly tests). Keep the output, test zig's own
# status, fail at the end.
TESTQ=$(mktemp -d)
printf '%s\n' $NATIVE_TESTS | xargs -P "${GATE_TEST_JOBS:-4}" -I{} sh -c \
    'o="$2/$(printf %s "$1" | tr / _)"; zig test "$1" > "$o.out" 2>&1; echo $? > "$o.rc"' _ {} "$TESTQ"
for t in $NATIVE_TESTS; do
    o="$TESTQ/$(printf %s "$t" | tr / _)"
    printf '%-42s ' "$t"
    if [ "$(cat "$o.rc")" = 0 ]; then
        tail -1 "$o.out"
    else
        echo "FAILED"
        tail -20 "$o.out"
        tests_failed="$tests_failed $t"
    fi
done
[ -n "$tests_failed" ] || rm -rf "$TESTQ"
if [ -n "$tests_failed" ]; then
    echo "native tests: FAILED ❌$tests_failed"
    exit 1
fi

# --- disks: repack what is stale, then mount and instantiate every image ----
tools/mkdisks.sh
python3 tools/channels.py     # the monitor's +/- channel list (needs the disks)
python3 tools/cache_bust.py   # docs/*.html ?v= = content hash of each script/CSS (stale-cache guard)
python3 tools/kos_c_image.py --check   # docs/kos-c.img (KOS's C: on the page, ?c=kos-c.img) is what its generator writes
python3 tools/gemdos_c_image.py --check   # docs/gemdos-c.img (KOS GEMDOS's C: with pictures in folders, ?c=gemdos-c.img) is what its generator writes
uv run --quiet --with pillow python tools/gem_assets_conv_test.py   # -Dgem_assets's converter (GEM 5, decisions.md 2026-11-09): a made-up asset directory's arrow, glyphs, icons and tree land in the generated Zig where it says (nothing of the TOS sources)
for _b in arrow glyph tree; do ! uv run --quiet --with pillow python tools/gem_assets_conv_test.py --break $_b > /dev/null || { echo "gem_assets_conv_test --break $_b: not caught"; exit 1; }; done   # ...and a converter that loses the arrow, a glyph or a tree is caught
python3 tools/mp3_c_image.py --check   # docs/mp3-c.img (the MP3 PLAYER's C:, C:\MUSIC's CC0 test files, ?c=mp3-c.img) is what its generator writes
python3 tools/gen_docs.py --check   # ZIGMACHINE_GUIDE.html regenerated from MUSIC.md, FLOPPY_DISK.md and the sources
python3 tools/gen_tutorial.py --check   # TUTORIAL.html regenerated from TUTORIAL.md
python3 -m unittest discover -q -s tools/tests -t tools   # the doc generators' own tests
node apps/disk_check.mjs
node apps/upload_check.mjs    # an uploaded disk mounts exactly like a URL one; bad uploads refused
node apps/kos_boot_check.mjs  # KOS's power-on in the page = scene_hash.mjs --kos, every kind of drive A
node apps/kos_boot_check.mjs --break  # ...and a POST on the wrong planes is caught
node apps/kos_boot_check.mjs --break c  # ...and a C: drive that answers nothing (the page's kosDriveRead) is caught: KOS's C: (docs/KOS_FAT.md F5), with ?c=kos-c.img, shows its icon and opens = scene_hash.mjs --c-image
node apps/tutorial_steps_check.mjs   # docs/TUTORIAL.html's per-step carts have not drifted from the finished ones

# --- headless harnesses: each drives the real machine end to end -----------
# Shots go to a scratch dir so a build does not litter the repo. These cover
# BOTH halves of the machine — GEM/ROM and the audio/SNDH side — because a host
# or ABI change breaks whichever one you were not thinking about.
#
# Nothing runs on these lines: `gate` QUEUES a harness and run_gates, at the end,
# runs the queue GATE_JOBS at a time (tools/gate_lib.sh). `gate_timed` marks a
# harness that asserts wall-clock ms a frame: it runs ALONE after the pool.
# `always` is queued whatever --only/--changed selected.
SHOTS=$(mktemp -d)
if [ -n "$CHANGED_BASE" ]; then
    # After the build on purpose: docs/demo-*.wasm are now this tree's bytes, so
    # every cart the change reached is in the diff (tools/gate_scope.py).
    _scope=$( { git diff --name-status --no-renames "$CHANGED_BASE"
                git ls-files -o --exclude-standard | sed 's/^/A\t/'; } \
              | python3 tools/gate_scope.py . )
    if [ "$_scope" = FULL ]; then
        echo "--changed $CHANGED_BASE: FULL gate (the paths above are shared or unknown)"
    else
        SELECT_EXACT=$_scope
        STAMPABLE=""
        echo "SELECTIVE GATE (--changed $CHANGED_BASE) - harnesses: ${_scope:-none}"
        echo "  (every cart and disk was rebuilt and every cross-cutting check runs)"
    fi
fi
always verify node apps/verify.mjs          # the C and Rust carts still talk to the ABI
always tunein node apps/tunein_check.mjs    # C/Rust channels tune in through Zig's snow, byte for byte, then start as skipBoot
always tunein node apps/tunein_check.mjs --fail-proof docs/demo-c.wasm docs/demo-rust.wasm   # ...and a cart without tuneIn fails it
gate sdk node apps/sdk_check.mjs   # KESTREL SDK (docs/SDK.md): sdk/template copied OUT of the repo builds through its own build.zig (the repo as a Zig package) and `make floppy`, then runs strictly linked: plane on, picture moving, real per-line rasters, its song in docs/music/
gate sdk node apps/sdk_check.mjs --break still    # ...and an update() that moves nothing is caught
gate sdk node apps/sdk_check.mjs --break raster   # ...and a cart without its copper (one flat background) is caught
gate sdk node apps/sdk_check.mjs --break song     # ...and a song no file under docs/music/ is caught
gate gem node apps/gem_headless.mjs "$SHOTS"
gate gem node apps/gem_desk_check.mjs "$SHOTS"   # GEM in the desk mode (HW 1.17.0, docs/GEM_DESK_MODE.md §8): Set Preferences' Desk button puts plane 0 in the desk; the 640x480 picture is the page model of plane 0, the desktop's colour reaches row 479 (the blitter's 200-row clip banded, gui/bandfill.zig), the trash on the bottom row; a window dragged to y 330 lands there (the pointer 1:1); Save Desktop writes #E 02; Low leaves the desk and clamps the window into 320x200; a boot whose disk holds that DESKTOP.INF comes back in the desk, the window where it was; without the mode (hwDeskAvailable 0) it boots low, the window clamped, Desk greyed
gate gem node apps/gem_desk_check.mjs --break   # ...and the page's old y mapping, the INF's 02 read as 01, no Save Desktop and a ROM told the mode exists on a machine without it (Desk not greyed) are each caught
gate gem node apps/gem_desk_flip_check.mjs   # the desk's two buffers (Matt on the board 8 Nov: the screen blinked when the mouse moved): a clean frame flips nothing, a drawn one goes into the buffer not on screen (left untouched) and flips FB_BASE, a session over a poisoned back buffer = the single-buffered desk frame by frame; GEM's arrow at the pointer in the desk only
gate gem node apps/gem_desk_flip_check.mjs --break   # ...and buffers never handed, a host that never rests, a ROM told the wrong pointer and an arrow in the low plane are each caught
gate gem node apps/gem_engine_check.mjs   # GEM 5 step 1 (docs/GEM5_ENGINE.md): the desk painted by the engine in both looks, A:\ open: frames with no input paint nothing (a poisoned back buffer kept), a pointer move <= 512 px, a window drag its old and new places, damage = a whole repaint after every gesture; frame_cost with the pointer moving every frame: the engine < 1.75 Mc and below the old path
gate gem node apps/gem_engine_check.mjs --break   # ...and an engine that repaints everything, paints unclipped, keeps one snapshot for two buffers, loses a damage box, or never switches on is each caught
gate gem node apps/gem_desk_bugs_check.mjs   # Matt's five desktop bugs (board, 9 Nov), in low, medium, the desk's old path and the engine's two looks: a resized window re-flows its icons (= opened at that size), a track click pages (= that many arrow clicks), text view scrolls sideways whole (folder rows too; damage = a whole repaint), a text row drags as its row's outline; Save Desktop writes C:\DESKTOP.INF and both the returning shell and a fresh boot read it (the desk, C:\ where it was)
gate gem node apps/gem_desk_bugs_check.mjs --break   # ...and a grid frozen at open, no track paging, folder rows that stay put, damage blind to a clipped row that moved, the icon ghost in text view and a host that drops C:'s writes are each caught
gate gem node apps/kos_desk_check.mjs   # KOS's desktop on the board (4 Nov): repainting only what changed is pixel-exact (a session hashed every frame = the every-frame repaint's pin) and a C: window costs < 1.7 Mc (the old repaint: 2.5, caught); A:\ with C: mounted lists the floppy, not the card; a folder opens INSIDE its drive's window as on TOS 1.00 (its close box and File > Close go up a level, Close Window leaves an empty desktop: main 0e47697e's window-per-folder ROM fails that)
gate sndh node apps/sndh_headless.mjs
gate sndh node apps/ste_dma_check.mjs   # the STE DMA chip as DMA replays drive it: start/end latched at the FRAME END (a double buffer written from play), the frame end clocking Timer A's event count (TACR 8), the LMC1992 master volume; each hand-assembled tune starts silent
gate sndh node apps/ste_dma_check.mjs --break latch    # ...and a tune that never writes its next frame fails the latch check
gate sndh node apps/ste_dma_check.mjs --break event    # ...and Timer A on the clock instead of the frame end fails the event check
gate sndh node apps/ste_dma_check.mjs --break volume   # ...and no Microwire command fails the volume check
gate sndh_relocate node apps/sndh_relocate_check.mjs   # a tune that installs its own MFP vectors (Alloy Run) plays: images load at $10002
gate sndh_call node apps/sndh_call_check.mjs   # zg.sndhCall: INIT on the RUNNING tune leaves the untouched channel, Timer A's phase and the position exactly as an untouched run's
gate sndh_call node apps/sndh_call_check.mjs --break   # ...and a reload in its place is caught
gate sap node apps/sap_check.mjs   # a SAP's 6502 on the browser's POKEY: a PAL tone at its pitch to 0.2 %, unknown hardware writes counted, STEREO refused
gate sap node apps/sap_check.mjs --break ntsc   # ...and a POKEY clocked NTSC for a PAL tune is caught
gate sap_test node apps/sap_test_headless.mjs   # SAP TEST: the cart requests Warhawk.sap song 1 at start and, per key, the right file and song (Down/Fire, Right/Left through BMX Simulator's 3 songs with wrap, nothing on a one-song tune, key 3); every request is in docs/music/, loads in the browser's SAP player with the song count the screen shows and is not silent on the POKEY; list drawn, scroller moving; Escape and Back leave
gate sap_test node apps/sap_test_headless.mjs --break tune   # ...and a request read as song 0 (DEFSONG, what requestSong sends) is caught
gate sap_test node apps/sap_test_headless.mjs --break silent   # ...and a POKEY that renders nothing is caught
gate fuji_hobbytronic node apps/fuji_hobbytronic_headless.mjs "$SHOTS/fuji_hobbytronic"   # FUJI HOBBYTRONIC: Hobbytronic_92_1.sap song 1 requested at start, ASMA's file in docs/music/ and not silent on the POKEY; the Fuji's front cap and shaded sides drawn, turning frame to frame, its back cap showing half a turn on; the front cap's colour register read after the HBL on every line: 8+ colours, changing most lines, ST-legal, <= 2 registers a line, every front pixel displayed in its line's colour, the bars rolling; scroller moving; Escape leaves
gate fuji_hobbytronic node apps/fuji_hobbytronic_headless.mjs --break raster   # ...and an HBL never dispatched (one flat colour) is caught
gate fuji_hobbytronic node apps/fuji_hobbytronic_headless.mjs --break still    # ...and a picture that does not move is caught
gate fuji_hobbytronic node apps/fuji_hobbytronic_headless.mjs --break song     # ...and a request read as song 0 (DEFSONG) is caught
gate supplex_fs2 node apps/supplex_fs2_headless.mjs   # SUPPLEX FS2: shaolin_title.hip song 1 requested at start, modland's file (md5) in docs/music/; Hippel's own 68000 replay on the emulated Paula for 20 s: never runs away, both sides loud, 3+ voices started by DMACON, 100+ pointers re-latched at a voice's wrap, no bad pointer, no audio IRQ, no unanswered hardware write
gate supplex_fs2 node apps/supplex_fs2_headless.mjs --break silent   # ...and a Paula that ignores DMACON's switch-on (silence) is caught
gate supplex_fs2 node apps/supplex_fs2_headless.mjs --break latch    # ...and a pointer taken at once instead of at the voice's wrap is caught
gate supplex_fs2 node apps/supplex_fs2_headless.mjs --break song     # ...and the request's old spaced name is caught
gate hip node apps/hip_check.mjs   # .hip: every Hippel module in docs/music/ (shaolin_title, rings_of_medusa songs 1-2) on its own 68000 replay for 10 s: no runaway, loud, a Paula voice started, no bad pointer, no unanswered write; Rings of Medusa's replay waits on the beam (VHPOSR)
gate hip node apps/hip_check.mjs --break beam   # ...and a beam counter stuck at 0 (the RoM replay hangs) is caught
gate mod_sfx node apps/mod_sfx_check.mjs   # zg.sfxPlay over a MOD: the effect takes the song's fewest-notes channel on exactly its bytes at full volume and that channel's pan, the song writes nothing there and goes on elsewhere, gets it back at the effect's end; a loop holds it until a loop-only stop (4 s timeout); YM writes mixed under a MOD, refused under an SNDH; SNDH -> MOD leaves the MOD alone; no MOD, no effect (counted); 6CHN/8CHN/32CH/untagged/short MODs refused and counted, the four ProTracker tags load; zg.requestModVolume scales the song's channels at once (the output exactly x gain), never the effect's, 1.0 again on a new MOD, over 1.0 / no MOD refused
gate mod_sfx node apps/mod_sfx_check.mjs --break bytes     # ...and the effect compared with another sample fails
gate mod_sfx node apps/mod_sfx_check.mjs --break release   # ...and the channel expected held after the effect's end fails
gate mod_sfx node apps/mod_sfx_check.mjs --break loop      # ...and the loop expected free before its stop fails
gate mod_sfx node apps/mod_sfx_check.mjs --break reject    # ...and an 8CHN file expected to load fails
gate mod_sfx node apps/mod_sfx_check.mjs --break gain      # ...and the effect's channel expected scaled with the song by zg.requestModVolume fails
gate xm node apps/xm_check.mjs   # FastTracker 2 (.XM) player: the generated 8-channel test song (apps/xm_song.mjs) loads and plays as mode 1 through the sealed Paula channels, never over full scale, not silent; the 12-channel song (three voices a channel) loads, plays and renders twice identically; 13-channel / non-XM / truncated files refused with their reasons and counted; rendering it twice is byte-identical and matches the pinned sha256
gate xm node apps/xm_check.mjs --break refuse   # ...and a 13-channel file expected to load fails
gate xm node apps/xm_check.mjs --break pin      # ...and a wrong pin fails
gate music node apps/music_debug_check.mjs   # MUSIC DEBUG: keys 1..6 (setShadeMode, as the loader and the board's glass send them) ask for MOD / YM / sample / SNDH / XM / local XM by name; every committed name is a git-tracked file in docs/music/ (the board's song table is built from them), local.xm never is; key 5's XM plays as mode 1
gate music node apps/music_debug_check.mjs --break name   # ...and key 5 expected to ask for another file fails
gate music node apps/music_debug_pin.mjs   # ...and its composited picture (borders, rasters, HBL), every 60 frames to 1200, silent and with a YM tune's registers mirrored in (scope on), equals the pin apps/music_debug_pin.json (re-blessed 2026-10-24 when the screen went fixed point); the picture moves and the scope changes it
gate xm_test node apps/xm_test_check.mjs   # XM TEST: keys 1..4 (setShadeMode) ask for keygen_9000.xm / poppy_flower_girls.xm / local.xm / "none" by name; the bundled XMs are The Mod Archive's Public Domain files byte for byte (md5), 8 and 12 channels, and play (mode 1, not silent); local.xm never committed
gate xm_test node apps/xm_test_check.mjs --break name   # ...and key 2 expected to ask for another file fails
gate kt_test node apps/kt_test_check.mjs   # KT TEST: keys 1..5 (setShadeMode) ask for starport2.kt / castlevania.kt / oceanloader3.kt / dpintro.kt / "none" by name; the bundled songs are upstream klystrack's examples byte for byte (md5); each loads and plays in the audio modules (mode 1, not silent)
gate kt_test node apps/kt_test_check.mjs --break name   # ...and key 2 expected to ask for another file fails
gate mp3 node apps/mp3_check.mjs   # MP3 player (libs/zig/players/mp3.zig, pvmp3) fed as a cart feeds it: 44.1 kHz stereo and mono out = the reference decode >> 1 sample for sample (the 15-bit Paula path), no underrun, nothing dropped, ended then silence; 32 / 48 kHz converted to 44.1 (rate code, length, output pinned); half a file then end = the reference's first frames; fed at half speed: underruns counted, every frame decoded, ended
gate mp3 node apps/mp3_check.mjs --break lowbyte   # ...and the low-byte channels silenced fail the exact check
gate mp3 node apps/mp3_check.mjs --break overfeed   # ...and feeding past the ring (no flow control) fails (bytes dropped)
gate mp3 node apps/mp3_check.mjs --break noend   # ...and never telling the player the input ended fails (it never ends)
gate mp3_player node apps/mp3_player_check.mjs   # MP3 PLAYER cart over the machine + ROM, C: = docs/mp3-c.img through KOS GEMDOS: Down Down Return plays TONES44.MP3; the bytes it fed are the file's in order, never past the ring, the end told; the audio out = the reference >> 1; the next file starts at the end, N past the last stops, Esc again asks for request 4
gate notepad node apps/notepad_check.mjs   # NOTEPAD (docs/NOTEPAD.md) on GEM 5's program API over the machine + ROM, C: = a copy of docs/gemdos-c.img: launched from GEM off its data disk; typed, ^S to C:\NOTE.TXT (mtools: the bytes, CR LF; fsck clean), reopened in a new session pixel for pixel; "Save changes?" Cancel / Yes; the menu by the pointer; 60 lines, PgUp, a held arrow; the sizer; in low, medium and the desk; the screen as drawn = a whole repaint after every step
gate notepad node apps/notepad_check.mjs --break write   # ...and a host that refuses every write is caught
gate notepad node apps/notepad_check.mjs --break bytes   # ...and a byte changed on its way to C: is caught
gate notepad node apps/notepad_check.mjs --break ctrl   # ...and Control never sent (^S types an s) is caught
gate mp3_player node apps/mp3_player_check.mjs --break byte   # ...and one fed byte changed fails both the bytes and the audio check
gate mp3_player uv run --project fpga python -m pytest -q fpga/tests/test_mp3_native.py   # ...and on the native host (host_audio, --c-image docs/mp3-c.img, the glass's key router): Down Down Return plays TONES44.MP3, the machine's 16-bit out = the reference >> 1; no key, no sound
gate sid node apps/sid_check.mjs   # .sid player (libs/zig/players/sid.zig, cRSID libs/c/crsid): the engine in machine-audio.wasm renders hermini.sid's first 10 s to the same samples, 0.1 s block for block, as the same C built natively by the host's cc (fpga/tools/sid_render.c on patch.sh's tree: what BARD runs, host/crsid.c), local study tunes too when present; the player's 44.1 kHz output a side = the engine upsampled (midpoints) >> 1, mode 1, heard; an RSID refused (status 2) and garbage (1), silent
gate sid node apps/sid_check.mjs --break seed   # ...and the native build's dither seed one off fails parity
gate sid node apps/sid_check.mjs --break rsid   # ...and an RSID let through as a PSID fails the refusal check
gate sid_test node apps/sid_test_check.mjs   # SID TEST: keys 1-4 ask for the local HVSC tunes by name (gitignored, never fetched, none tracked), key 6 for hermini.sid, 5 for "none"; key 7 is requestSongBytes kind 6 of the tune's bytes, mode 7 (no key) of the same as an RSID; the loader's postSfx makes loadSid of each; the audio modules play the PSID (mode 1, heard) and refuse the RSID (status 2, silent); both tune files are cRSID's HerMiniSID (md5)
gate sid_test node apps/sid_test_check.mjs --break name   # ...and key 6 expected to ask for another file fails
gate bard_sid node apps/bard_queue_check.mjs   # BARD queue (zg.bard, table 1.12): BARD SID writes its tune into its ring; the loader's bardFrame + the worklet's bardQueue on the audio modules (raw cRSID) = host_audio (the cart and players through wasm2c, cRSID native, host/bardq_pump.c: BARD's pump), the same samples from the first heard one over 420 frames; every command applied, none refused, dropped or re-anchored, the beat marks back; key 2 resets an 8580 mid-tune (its event back, the output parts after the key); bardDrain stops at an entry not whole
gate bard_sid node apps/bard_queue_check.mjs --break stamp   # ...and the loader delaying every SID write two samples (one engine sample) fails parity
gate bard_sid node apps/bard_queue_check.mjs --break reg   # ...and the loader writing the next SID register fails parity
gate bard_sid uv run --project fpga python -m pytest -q fpga/tests/test_bard_queue.py   # ...and the board's answer across S2C (cycles/bardq_s2c.h) lands in the cart's block as the page writes it: no tail past the head, no position before the anchor, events unpacked, lapped or full counted lost
gate tri_test node apps/tri_test_check.mjs   # TRI TEST (cart 125): every TRIANGLE of set A (edge cases + 160 seeded) and of set B (48 a frame, 300 frames) equals a rasteriser written in the harness from the spec; the cart's on-screen hashes are the GOLDEN_A / GOLDEN_B the board compares against
gate tri_test node apps/tri_test_check.mjs --break floor   # ...and a rasteriser that truncates instead of flooring is caught
gate kt node apps/kt_check.mjs   # klystrack (.kt) player: each bundled song's core output for 45 s is upstream klystron's render byte for byte (kt_ref's sha256), the Paula output (high + low byte a side) is that core to within 1/32768 over odd-sized renders, mode 1, never over full scale, not silent; a non-.kt / future version / truncated file refused with its reason and counted
gate kt node apps/kt_check.mjs --break pin   # ...and a wrong pin fails
gate kt node apps/kt_check.mjs --break lowbyte   # ...and the low-byte channels silenced (8-bit sides) fail the Paula check
gate sysinfo node apps/sysinfo_check.mjs "$SHOTS/sysinfo"   # SYSINFO: every page's text is on the glass glyph for glyph; page 1's memory lines are hwRamFree/Base/Top/Size, the ROM window and hwVideoBase as the machine answers; plane 0's base is its register's; the disk lines are the .zmd descriptor's; player + YM lines follow the host live; idle frames draw nothing, a refresh only the changed span; no host clock = every speed test once, n/a; a clock = a time each, 6 ratios to the ST, f32 to the integer mul-add; Space opens the menu, a click on F4 shows the disk page whole; Q = request 4; page 3 lists the disk's JINKS.SND / GAUNTLET.SAP / SAMPLE.RAW / KEYGEN.XM / THALION.HIP / STARPORT.KT, P reads each through the drive (the bytes handed over = the FAT file's; the ZX0-packed SNDH / XM / HIP's = the repo's file, depacked by the cart), an SNDH / SAP / XM / HIP / KT goes out as requestSongBytes and the loader's postSfx + the audio module play it in mode 4 / 5 / 1 / 1 / 1, heard, the PCM is samplePlay at 12500 Hz; S stops each
gate sysinfo node apps/sysinfo_check.mjs --break free   # ...and FREE expected 4 KB off hwRamFree() fails
gate sysinfo node apps/sysinfo_check.mjs --break sound   # ...and a drive serving JINKS.SND with one byte changed fails the bytes check
gate sysinfo_gem node apps/sysinfo_gem_check.mjs   # SYSINFO as a GEM program: its disk is a DATA disk (with the No virus $1234 boot sector, which asks for request 2 and names no cart, so GEM follows) whose one program BOOT.WSM (beside six sound files) depacks to demo-sysinfo.wasm; GEM's floppy window runs it on a double-click (request 3), Q brings GEM back (request 4), 3 round trips (> MAX_GUI) and the menu still opens; page 4 reads DATA DISK + BOOT.WSM; the last Q leaves the desktop as it was
gate sysinfo_gem node apps/sysinfo_gem_check.mjs --break bootable   # ...and a disk held to the bootable kind fails
gate pure_hbl uv run --project fpga python fpga/tools/video_order_pure.py --break --frames 600 replicants automation442 union_intro@3000   # REG_FB_HBL_PURE (1.8.0): every cart whose pure HBL handler plane the board composites line by line beside another plane, replayed in the board's order (handler before its own pass, RES_FLICKER as its own handler left it) through the RTL compositor, equals the machine; a cart that no longer groups such a plane fails (nothing tested); --break: the synthetic overscan frames grouped without the firmware's RES_FLICKER store must be caught
gate kos_fat uv run --project fpga python -m pytest -q fpga/tests/test_kos_rv.py fpga/tests/test_kos_drive.py fpga/tests/test_kos_file.py   # one gate: both make gen/ on a clean tree. KOS F3b: a floppy program's own NAME.RV is the ZMRV container glass reads (version 1, the wasm's SHA-256, the ZX0-packed lean cart); a cart the system refuses (another table major) or lacks gets none; kos_rv.py floppy writes each cart's .WSM + .RV and KOS's reader lists them; carts whose 8.3 names collide are refused. KOS F5: env.kosDriveRead's request block as the board firmware writes it (cycles/bkosreq.h) is the one glass serves (map_cart.zig KOS_DRIVE_*), it answers only its own request, it sits between the media word and the cart-request block, and the native host's C: (host/disk.h) refuses what the page and glass refuse (no image, not unit 2, count 0 or > 64, past the end, dst off a word or past memory)
gate_timed c_music timeout 180 node apps/c_music_check.mjs   # a C cart's song request reaches the sealed YM (timeout: it once hung a gate)
gate union_demo_music node apps/union_demo_music_check.mjs   # the Union Demo menu's and cracktro's SNDH tunes are requested by name and play
gate union_demo_music node apps/union_demo_music_check.mjs --fail-proof   # ...and a wrong tune name fails that check
gate union_intro_music node apps/union_intro_music_check.mjs   # the cracktro's music starts with the TRSI logo, and main doesn't restart it
gate union_intro_music node apps/union_intro_music_check.mjs --fail-proof   # ...and a wrong tune name fails that check
gate union_intro_music node apps/union_tracks_play_check.mjs   # keys 1-6: every cracktro tune PLAYS after the one before (a YM dump after an SNDH once left the SNDH running over it: keys 3+ "crashed")
gate union_intro_music node apps/audio_switch_check.mjs   # a SAP or a YM dump loaded over a playing SNDH takes over (mode, sound, no runaway 68000), then an SNDH plays again
gate union_demo_doors node apps/union_demo_doors_check.mjs   # the hub's doors launch the Union screens by tag (they are hub-only)
gate union_intro_main node apps/composite_hash.mjs docs/demo-union_intro.wasm 12000 12 --disk docs/demo-union_intro.zmd --expect 0085826630925e290c96c9968069b8dfd886cbd89e9d2501cb3837b99b48a8ad   # UNION cracktro into its MAIN screen: 1000 composited pictures over 12000 frames (the parts, then ~11000 frames of the main screen: all 8 credits pages, sky raster, balls, scrolltext); two planes (balls on P0, scrolltext under P1's palette split). 2026-10-25: union_intro's wave and triangle edges run in fixed point (no per-frame float on ZIGGY); 141 of 13000 frames / 6370 pixels differ from the old f32, in the scrolltext and dragonball band, mostly by 1 px (a wave column group one raster row, dragonball edge texels); after a hold-Left slow-down far more (the Q16 ramp snaps back to exactly 0.3), see the union_intro.zig header; the f32 accumulators are kept bit-exact by union/f32emu.zig
gate_timed union_demo node apps/union_demo_headless.mjs "$SHOTS/union_demo"   # hub: street wraps, view eases, keys stop at 60/144 Hz and on key-up, door memory
gate_timed union_demo node apps/union_demo_headless.mjs --break return "$SHOTS/union_demo"   # ...and a lost ROM note fails the door-memory check
gate_timed union_demo node apps/union_demo_headless.mjs --break wrap "$SHOTS/union_demo"   # ...and a door entered before the seam fails the wrap check
gate_timed union_multifake node apps/union_multifake_headless.mjs "$SHOTS"   # TCB3: loader depack, then screen.js replayed pixel for pixel
gate union_intro_wab node apps/union_intro_wab_check.mjs docs/demo-union_intro.wasm   # cracktro WAB logo: lands as exactly wab.raw; the original JS replayed (skipped without prototypes/)
gate dbug node apps/dbug_headless.mjs "$SHOTS"
gate dbug node apps/dbug_frames.mjs   # D-BUG: every frame of the first 100 s (intro, fall, beat bounces + logo spring, settle, the credit panel throughout), tune clock driven, is the two-plane cart's COMPOSED picture byte for byte (the panel now rides plane 0)
gate dbug node apps/dbug_frames.mjs --break skip   # ...and one extra VBL is caught (in the parts after it only)
gate vex node apps/vex_headless.mjs "$SHOTS/vex"   # VEX 2025: logo, panel + its 4-page cycle, cubes, both scrollers, the raster rows
gate tcb_colorshock node apps/tcb_colorshock_headless.mjs "$SHOTS/tcb_colorshock"   # COLORSHOCK 2: the hardware pan, the per-line palettes, the strip on its table
gate replicants_emlyn node apps/replicants_emlyn_headless.mjs "$SHOTS/replicants_emlyn"   # EMLYN HUGHES: the bars are REAL rasters edge to edge (no pixel ever carries a bar colour; theta 0 is ONE colour register a line), Space switches ORIGINAL<->ZIG (bars turn, scrolltext bends on CODEF 484's curve, and the bars run on through the opened TOP and BOTTOM borders with no seam at the window edge), ORIGINAL is pinned by hash to the screen before that and its border lines stay black, 1/2 toggle ZIG's scroller/raster styles and back (and change not one pixel in ORIGINAL), the sweeping logo, the flat scroller in the opened bottom border and out through the LEFT border pixel for pixel (both modes), Escape leaves, the tune plays with no unanswered hardware write, and this fixed-point cart draws the f32 cart's screen (under 1% of pixels apart on every frame, through ZIG and back); F switches the maths live: pressed before frame 1 the cart IS the f32 cart pixel for pixel, twice it is itself again, mid-sweep it carries the screen across
gate replicants_emlyn node apps/replicants_emlyn_headless.mjs --break rasters "$SHOTS/replicants_emlyn"   # ...and one static palette instead of a per-scanline one is caught
gate replicants_emlyn node apps/replicants_emlyn_headless.mjs --break flick "$SHOTS/replicants_emlyn"   # ...and a line whose copper record does not FLICK (its borders close: the list must keep every border open, as the handler's flickerBorder() did) is caught
gate replicants_emlyn node apps/replicants_emlyn_headless.mjs --break borders "$SHOTS/replicants_emlyn"   # ...and rasters, logo OR scrolltext stopping at the content edge (the .top_bottom + window-clipped behaviour) is caught
gate replicants_emlyn node apps/replicants_emlyn_headless.mjs --break spin "$SHOTS/replicants_emlyn"   # ...and bars that never tilt without Space is caught
gate replicants_emlyn node apps/replicants_emlyn_headless.mjs --break topbottom "$SHOTS/replicants_emlyn"   # ...and ZIG's top and bottom border lines left black (the window-only raster table) is caught
gate replicants_emlyn node apps/replicants_emlyn_headless.mjs --break keys "$SHOTS/replicants_emlyn"   # ...and 1/2 that never switch ZIG's scroller or raster style is caught
gate replicants_emlyn node apps/replicants_emlyn_headless.mjs --break leftclip "$SHOTS/replicants_emlyn"   # ...and the remake's 640-px ring (letters recycled at plane column 8, cut off in the opened left border) is caught, in ORIGINAL and ZIG
gate replicants_emlyn node apps/replicants_emlyn_headless.mjs --break fixed "$SHOTS/replicants_emlyn"   # ...and a fixed-point cart a frame off the f32 one (the screens the two number systems draw no longer agree) is caught
gate replicants_emlyn node apps/replicants_emlyn_headless.mjs --break fkey "$SHOTS/replicants_emlyn"   # ...and F never switching the maths (the default cart pressed F before frame 1 is NOT then the f32 cart pixel for pixel) is caught
gate replicants_emlyn_f32 node apps/replicants_emlyn_headless.mjs "$SHOTS/replicants_emlyn_f32" --cart docs/demo-replicants_emlyn_f32.wasm   # EMLYN HUGHES F32 (cart 88, the CODEF algorithm in f32 for the FPU test): every check above, on the f32 build
gate replicants_garfield node apps/replicants_garfield_headless.mjs "$SHOTS/replicants_garfield"   # GARFIELD: the four bouncing bars and the three red tubes are colour 0, real rasters edge to edge: every visible line's border follows colour 0 (a global HBL copies the copper's table into the machine background), the tubes are ST reds, top and bottom borders black
gate replicants_garfield node apps/replicants_garfield_headless.mjs --break noclear "$SHOTS/replicants_garfield"   # ...and a border that is never painted per line is caught
gate replicants_arkanoid2 node apps/replicants_arkanoid2_headless.mjs "$SHOTS/replicants_arkanoid2"   # ARKANOID 2 (CODEF 33): the song request, and 743 frames over 2200 pixel-equal to a model from screen.js: bg, the bg2-coloured scrolltext straight then waving, HOFA/SHOGUN/A-TEAM on mycurve, bg restored exactly where the letters left
gate replicants_arkanoid2 node apps/replicants_arkanoid2_headless.mjs --break skipframe "$SHOTS/replicants_arkanoid2_break"   # ...and a cart one frame behind the model is caught
gate replicants_arkanoid2 node apps/replicants_arkanoid2_headless.mjs --break music "$SHOTS/replicants_arkanoid2_break"   # ...and another tune is caught
gate_timed tsl_hybridglenz node apps/tsl_hybridglenz_headless.mjs "$SHOTS/tsl_hybridglenz"   # HYBRID GLENZ: the blitter's OR minterm really makes 1|2=3 in the panel, the two objects interlace onto odd/even plane rows and morph apart, the square flies in and dissolves into the framed panel, the three text overlays and the logo's white flash are palette fades, the bar and scroller run the full raster
gate_timed tsl_hybridglenz node apps/tsl_hybridglenz_headless.mjs --break spin "$SHOTS/tsl_hybridglenz"   # ...and objects that never turn is caught
gate mandelbrot node apps/mandelbrot_headless.mjs   # MANDELBROT: the f32 default draws a real fractal top to bottom, F switches the escape loop LIVE to Q5.27 integers (a picture a rounding apart from the f32 one), F twice is the f32 picture again
gate mandelbrot node apps/mandelbrot_headless.mjs --break fkey   # ...and an F that never arrived is caught
gate bladerunners node apps/bladerunners_headless.mjs   # BLADERUNNERS DUNGEON: 10,500 frames (the whole scroll text and its wrap): every visible line of the composed picture is ONE raster colour from the left border through the picture to the right border (back[(line-40+R)%255], the ink font[line]), the top/bottom bands transparent; the picture area hashes to the pre-fix two-plane cart's (ring strip + one plane, same scroller)
gate bladerunners node apps/bladerunners_headless.mjs --break shift   # ...and a border HBL one table line off the picture's is caught
gate blitter node apps/blitter_headless.mjs "$SHOTS/blitter"   # BLITTER DEMO: key B draws all seven effects on the CPU with the blitter's exact pixels and palette, not one hwBlit() issued; the corner says BLITTER/CPU; B again returns, Escape asks for the menu
gate blitter node apps/blitter_headless.mjs "$SHOTS/blitter" --break pixel   # ...and a CPU frame one pixel off is caught
gate blitter node apps/blitter_headless.mjs "$SHOTS/blitter" --break nokey   # ...and a B that never arrived is caught
gate chisel_v2 node apps/chisel_v2_headless.mjs   # CHISEL V2 (cart 112, HW 1.11.0): every AFFINE (rotozoom, Mode 7) and MAP (tunnel) pixel equals a model written from the spec, four mirrored bobs a frame with the collision bit set and clear over a cycle, the IFE fill equal to a per-bit carry model, the pentagram's centre hollow
gate chisel_v2 node apps/chisel_v2_headless.mjs --break pixel   # ...and a rotozoom pixel changed is caught
gate chisel_v2 node apps/chisel_v2_headless.mjs --break fill   # ...and a model filling exclusive is caught
gate chisel_v2 node apps/chisel_v2_play_check.mjs   # CHISEL V2 at play: P shows the parrot photo (indices 56..247 only) at 64/128/256 (T) in ROTOZOOM, MODE 7 and TUNNEL; every play key (spin, reverse, zoom, pan, turn, drive, height, speed, roll, bend) changes the picture and its opposite restores it; X resets; a stopped camera and F give the same frame twice; F prints PAUSED
gate chisel_v2 node apps/chisel_v2_play_check.mjs --break photo   # ...and P never sent fails all nine photo checks
gate tc_test node apps/tc_test_check.mjs   # TC TEST (cart 113, HW 1.15.0): plane 0 alone in FB_MODE 6; the gamut shows all 65,536 colours, the plasma and hue views > 4,096, compare's bands 565 > 256-palette > 16 ST colours, ramps 32/64/32/64 steps, dither > plain; the plasma moves every frame while the pixel memory hashes the same (only the copper list moves it), the still views do not move; key 8 FADE (HW 1.16.0): a whole 256-frame cycle equals a model of the fade registers over an unchanged pixel memory, reaching full black, full white, a flash and the plain hues; eight distinct views; N/P pictures only in a ZM_TC_ART build, and the git-tracked cart carries none
gate tc_test node apps/tc_test_check.mjs --break   # ...and mode 5, colours quantised to 3 bits, a pixel written a frame, a frozen list and a tracked cart with local pictures, the fade registers zeroed, a pixel rewritten during the fade and a model without the fade are each caught
gate desk_test node apps/desk_check.mjs   # DESK TEST (cart 126, HW 1.17.0): the desk mode's 640x480 picture (hwRenderDesk) is the cart's model pixel for pixel; plane 0's buffer 64-aligned inside the VRAM pool; still; key 2 leaves for low res on the same buffer, key 1 brings the same desk back; hwClear only counts FRAME, hwRenderPlane draws nothing; a machine without the mode keeps the cart out; scene_hash's desk sample is "desk" + the bars (hwDeskBars) + the picture
gate desk_test node apps/desk_check.mjs --break   # ...and a palette entry, the checker, the halves swapped, FRAME counted twice, an older machine saying yes and the hash without its tag are each caught
gate ziggy node apps/ziggy_check.mjs   # ZIGGY (cart 115): ZM-X on and off draw the SAME picture (ROTO at 64/128/256 and VOXEL, frame 40), the picture area is the mode's own, frames move, the texture size changes the pixels, VOXEL has sky on top and ground at the bottom, the HUD is drawn and follows the mode, Escape leaves; P swaps ROTO's texture for the parrot photo at 64/128/256 (ZM-X on = off, photo indices and palette, HUD says PHOTO)
gate ziggy node apps/ziggy_check.mjs --break   # ...and ZM-X off compared a frame later is caught
gate ziggy node apps/ziggy_check.mjs --break photo   # ...and no swap asked for fails all nine photo checks
gate falcon_ays node apps/falcon_ays_headless.mjs   # ARE YOU SITTING COMFORTABLY? (cart 116, Reservoir Gods' Falcon intro): plane 0 alone in FB_MODE 5, falcon_ays.mod asked for on frame 1; the MOD's 8xx script on the frame clock: black before the blobs and in 807's gap, five blob variants at their times each drawn (colours, lines doubled by the copper list, pixel pairs, moving, five different pictures); the original's data drawn: text palette, purple LUT, the ship picture pixel for pixel, the CODE plaque, the flames on plane 1 alone in the fireball's colours; Escape leaves
gate falcon_ays node apps/falcon_ays_headless.mjs --break script   # ...and the blob checkpoints 3 s early are caught
gate falcon_ays node apps/falcon_ays_headless.mjs --break art   # ...and the ship compared one pixel off is caught
gate c64_1988 node apps/c64_1988_headless.mjs   # 1988 (cart 118, Tristar & RSI's C64 Only Sprites intro): plane 0 alone, overscan; nine C64 frames across the loop (logo + scrollers on texts 1 and 2, the logo fade, the wipe, the grid joining, cubes, the end fade, balls, the green fade) pixel-identical to VICE 3.9 x64sc (pinned SHA-256 of the 384x272 view in colodore indices, tools/c64/pin_frames.py); Escape leaves
gate c64_1988 node apps/c64_1988_headless.mjs --break pixel   # ...and the view taken one pixel to the right is caught
gate c64_transmission64 node apps/c64_transmission64_headless.mjs   # TRANSMISSION64 (cart 120, Padua's C64 invitation 2021): plane 0 alone; C64 frames across the show (the boot screen, the rings, the wipe, the logo's colours, the dots, the panel) pixel-identical to VICE 3.9 x64sc (pinned SHA-256 of the 384x272 view in colodore indices, tools/c64/pin_frames.py); Escape leaves
gate c64_transmission64 node apps/c64_transmission64_headless.mjs --break pixel   # ...and the view taken one pixel to the right is caught
gate c64_1988 node apps/c64_1988_zig.mjs   # 1988 ZIG mode (Z): plane 0 alone on a copper list, the C64 frames interpolated to 60 Hz (a new picture every machine frame in part 1), REF's picture exactly on every frame that falls on a C64 frame, <= 160 CHISEL ops a frame, Z back = REF pixel for pixel (three round trips)
gate c64_1988 node apps/c64_1988_zig.mjs --break   # ...and REF one frame ahead during the round trips is caught
gate erfurt_menu node apps/erfurt_menu_headless.mjs "$SHOTS/erfurt_menu"   # THE ERFURT MEGADEMO menu (cart 123; Atari Scene Collective ST/STE 2026, from the original protected disks): one overscan plane; the logo = logo.raw through its palette pixel for pixel; the three rainbow lines are colour-0 rasters of the ripped hue wheel edge to edge (borders open on those rows), moving; border = colour 0 (navy, the marker's $012); Down spins the drum and it settles on another entry; scroller and floor move; Space runs the exit fade, dark, back on the menu; Escape leaves
gate erfurt_menu node apps/erfurt_menu_headless.mjs "$SHOTS/erfurt_menu_break" --break hbl   # ...and a plane whose HBL never runs (no per-line colours, no open borders) is caught
gate obj node apps/obj_headless.mjs "$SHOTS/obj"   # OBJ DEMO: the icosahedron and gem in FLAT/GLENZ/WIRE/SOFT draw the pre-fixed-point cart's exact pixels for 240 frames; 1-4 pick the object (4: GLENZ NEST, 60/104), + / - walk the sphere's 13 levels (V/F 20/36 .. 1986/3968, stops at both ends, nothing on the other objects), S cycles nine distinct modes (GLENZ ORs, GOURAUD > 12 levels, WIRE/HIDDEN wire ink, HIDDEN fewer pixels, DOTS one pixel a vertex, TEXTURE the wall texels and ENVMAP Natrium's grey env map through one CHISEL AFFINE op), only last frame's box erased (no stale pixel in any mode, nest included), five sphere and three nest pins under every split, the HUD follows, Escape leaves
gate obj node apps/obj_headless.mjs --break res     # ...and + / - that never arrive are caught
gate obj node apps/obj_headless.mjs --break shade   # ...and an S that never arrives is caught
gate obj node apps/obj_headless.mjs --break erase   # ...and a stale pixel left in the object rows is caught
gate obj node apps/obj_headless.mjs --break pin     # ...and one pixel off a pinned picture is caught
gate scrolllab node apps/scrolllab_headless.mjs "$SHOTS/scrolllab"   # SCROLLTEXT LAB: the ten distortions over one text (codef_fx siny/sinx/zoomy, a 2D path with a loop, screen 345's table) all render and all differ from FLAT, and Escape leaves
gate_timed polkadots node apps/polkadots_headless.mjs "$SHOTS/polkadots"   # POLKA DOTS: the flat-shaded torus reaches the dot grid (100-700 cells stamped, never the whole grid), the light still makes big dots as well as small ones, all FOUR render modes draw a different picture at the op count the cart itself reports, and every one of them holds 60 fps; this fixed-point cart's dots match the f32 cart's (under 1% of lit cells, never more than one dot size apart); F switches the maths live: pressed before frame 1 the cart IS the f32 cart pixel for pixel, twice it is itself again, mid-turn it keeps the pose
gate_timed polkadots node apps/polkadots_headless.mjs "$SHOTS/polkadots_break" --break fixed   # ...and a fixed-point cart a frame off the f32 one (the dots the two number systems draw no longer agree) is caught
gate_timed polkadots node apps/polkadots_headless.mjs "$SHOTS/polkadots_break" --break fkey   # ...and F never switching the maths (the default cart pressed F before frame 1 is NOT then the f32 cart, every pixel) is caught
gate_timed polkadots_f32 node apps/polkadots_headless.mjs "$SHOTS/polkadots_f32" --cart docs/demo-polkadots_f32.wasm   # POLKA DOTS F32 (cart 89, the CODEF algorithm in f32 for the FPU test): every check above, on the f32 build
gate lockbuster2 node apps/lockbuster2_headless.mjs "$SHOTS/lockbuster2"   # LOCKBUSTER 2 (cart 90): at the go-lockbuster2 checkpoints (title slides + all six engines) the cart's engine ring is the original screen memory byte for byte; the drawn frame, border raster included, is the Go shader's pixel for pixel, F5's alternate bank included; F1/F4 toggle what message-3 advertises; the cycle wraps with phase sane at tick 22000; Rollout.sndh #1 is requested; Escape and Space both leave; no zg.mem allocation refused
gate_timed raytrace node apps/raytrace_headless.mjs "$SHOTS/raytrace"   # RAYTRACE (Q16.16 + f32 carts, the FPGA CPU benchmark), each run with no clock, a fake one and the real one (env.hostMicros): both finish at exactly frame 110 with no clock (fixed work, 8x8-block preview at frame 2) and 220 with the fake one (timed work), the fake-clock rate reads exactly 32000 px/s and the real one is measured and printed, Fire restarts a run, both show sky, both floor tones, all five spheres, a floor shadow and a chrome sphere mirroring floor and sky, the fixed-point picture matches the f32 one, the ray count is plausible, each frame fits 60 fps, and the finished picture's SHA-256 is pinned per cart and identical under all three clocks; the f32 cart then refines (15 more jittered samples a pixel: anti-aliasing + soft shadows), reaches pass 16 at exactly frame 1760 / 3520 and stops, its converged picture pinned and identical under all three clocks, with a floor penumbra and coverage-dithered edges the first picture lacks
gate_timed raytrace node apps/raytrace_headless.mjs --break pixel "$SHOTS/raytrace"   # ...and one wrong pixel fails the pinned fingerprint
gate_timed raytrace node apps/raytrace_headless.mjs --break clock "$SHOTS/raytrace"   # ...and a clock that never moves (a frame that never ends its budget) fails the frame count, the rate and the 60 fps budget
gate_timed raytrace node apps/raytrace_headless.mjs --break smooth "$SHOTS/raytrace"   # ...and refinement passes that change nothing fail the converged pin, the penumbra and the edge checks
gate elite_cfsr node apps/elite_cfsr_headless.mjs "$SHOTS/elite_cfsr"   # ELITE CHALLENGE FOOT: both colour-0 bars are REAL rasters read off the LEFT BORDER (BEAM_RASTERS1/2 exact, and the closing one only exists because the bottom border is open), every one of the 156 band lines carries its own RASTERS group word, and all ten copies of the 16-row XOR-filled scroller pattern agree
gate rno_sodium node apps/rno_sodium_headless.mjs "$SHOTS/rno_sodium"   # RNO SODIUM: at the eight counter values of the Hatari RAM snapshots (wobble trail, curtain, both text pages, prism and distorter back buffers) the frame on screen is the original's, pixel for pixel; the parts change on a 50 Hz counter even on a 60 Hz host; gritty.sndh restarts when the intro loops
gate rno_natrium node apps/rno_natrium_headless.mjs "$SHOTS/rno_natrium"   # RNO NATRIUM: at six timeline counters the displayed frame is Hatari's RAM snapshot through the palette, byte for byte; part 1's two-tone dot tunnel and logo band; $1E00 starts the intro over identically
gate rno_natrium node apps/rno_natrium_zig.mjs "$SHOTS/rno_natrium"   # ...ZIG mode (Z): plane 1 alone, overscan, borders open; tunnel (MAP, map = the table's formula), wobble (tex2d) and rotozoom (AFFINE) are the original's maths at every pixel of the 400x280 window; the env cube/prism show a new true-colour frame every VBL over the girl; the dot tunnel (MAP OR over the curtains/logos) and the chrome twister (ZIGGY, 100 columns, 90-line bar) FULLSCREEN, every pixel modelled and the borders lit; the credits are the original's frame; Z back (mid-cube and in the rotozoom) gives the original's frames pixel for pixel; <= 3 CHISEL ops a frame; Escape leaves
gate rno_natrium node apps/rno_natrium_zig.mjs --break   # ...and the round trip compared one VBL apart is caught, and so are the dots and twister models one VBL off
gate dhs_0pxl0reg node apps/dhs_0pxl0reg_headless.mjs "$SHOTS/dhs_0pxl0reg"   # DHS (n)0 PIXELS (n)0 REGRETS: zero bitplanes, every pixel a BEAM colour-0 write; at every 50th frame across all 17 parts the whole 400x280 physical frame, borders included, is the reference model's byte for byte; REG_BEAM_DROPPED stays 0 over the whole 22,000-frame run; no plane is ever enabled; Fake It at 159, stopped at 7759, AY Tunage at 8173
gate dhs_0pxl0reg node apps/dhs_0pxl0reg_headless.mjs --break skip "$SHOTS/dhs_0pxl0reg"   # ...and one skipped VBL fails the frame checks
gate dhs_0pxl0reg node apps/dhs_0pxl0reg_headless.mjs --break drop "$SHOTS/dhs_0pxl0reg"   # ...and a write 4 px after another (faster than a move.w) is counted as a drop
gate noextra node apps/noextra_headless.mjs "$SHOTS/noextra"   # NOEXTRA "RASTERS" (NoExtra / DHS 2005), ported from the ORIGINAL RASTERS.PRG: every 10th of 2,400 frames the whole 400x280 physical picture equals a model built from the ripped assets (D.H.S logo on the bob table; NOEXTRA + ZORRO 2 logos pixel for pixel in their ST palettes; gradient bars; 146 band lines of real colour-0 rasters from ramp.pal + two sine reads; the 32x16 one-plane scroller on the wave table; the bob from main frame 767); band lines hold only raster colours and the ink; music is mega4_disk_mag.sndh
gate noextra node apps/noextra_headless.mjs --break ste "$SHOTS/noextra"   # ...and a model decoding the colours the STE way fails the frame checks
gate noextra node apps/noextra_headless.mjs --break bob "$SHOTS/noextra"   # ...and a bob one frame late fails the frame checks
gate trsi_transarctica node apps/trsi_transarctica_headless.mjs "$SHOTS/trsi_transarctica"   # TRSI TRANSARCTICA (Falcon): at 17 program VBLs (intro flash, logo fade and slide, all six pages, the 3 RAM-snapshot and 5 screenshot frames) the 320x240 display, top/bottom borders open, is the RE model's pixel for pixel; the open bands are colour 0; the pages loop after 4210 VBLs; the MOD is requested at BPM 123 on VBL 1 and plays; audioModPlayBpm(125) is audioModPlay byte for byte
gate trsi_transarctica node apps/trsi_transarctica_headless.mjs --break skip "$SHOTS/trsi_transarctica"   # ...and one skipped VBL fails the frame checks
gate north_south node apps/north_south_headless.mjs   # NORTH & SOUTH battle (playable): the 13 reference scripts' inputs replayed through the cart's battle, and after EVERY frame (5104) the 5776-byte battle RAM, the screen flipped to, the sound sequences and the frame's VBL length are the reference model's (itself byte-exact against the original 68000 battle), the winners too; the host path: front page, Space starts, battle frames on a 50 Hz VBL clock at a 60 Hz host, the plane shows the battle screen, '/' requests the unit-switch sound, F10 leaves; the digi SNDH plays a sequence's level bytes at its Timer A rate
gate north_south node apps/north_south_headless.mjs --break   # ...and one poked RAM byte (the RNG) fails the replay
gate joust node apps/joust_headless.mjs "$SHOTS/joust"   # JOUST (the game): two recorded games (1P TAS 18,293 frames to wave 9, 2P TAS 7,015 frames) replayed from power-on in lockstep with the harness's title key and joystick bytes: every frame takes the real program's VBL count and starts its Dosound scripts, every 25th frame start the game RAM + screen hash and the CPU cycle count are the real program's; live: the title and the game on the plane pixel for pixel, '1' starts, P/any key/R/Escape, 50 Hz time on a 60 Hz host; joust_sfx.sndh leaves the YM where TOS's Dosound leaves it for all 16 scripts
gate joust node apps/joust_headless.mjs --break joy "$SHOTS/joust"   # ...and one flipped fire bit fails the replay checks
gate kickoff2 node apps/kickoff2_headless.mjs "$SHOTS/kickoff2"   # KICK OFF 2 (the friendly, playable): the title's plane is the ripped title art with FIRE starting the kickoff; ko2TestTick drives the SAME MatchP from a fixed seed for 3 simulated minutes: the ball leaves the centre circle, stays on-pitch or ends a legal restart (throw-in/corner/goal-kick/goal), scores>=0, the clock advances only while playing; possession keeps the ball within a player reach; Escape at the title and the match both, leave; no zg.mem allocation refused
gate grodan_kvack node apps/grodan_kvack_headless.mjs "$SHOTS/grodan_kvack"   # GRODAN & KVACK KVACK (cart 92): every frame to 20 s and at each scroll reset after it, the composited 320x200 window is the port's own model pixel for pixel (the six layers AND the copper's three raster entries AND the eight palette words together); the tick count, the four scrolls and the Go's animation counters equal the model's every frame; the per-line rasters really repaint palette entries 4/5/6 (more colours than a static palette can); Z (ZIG mode, apps/grodan_kvack_zig.mjs): the green plane drawn once and only hardware-panned, every rotozoom texel re-derived, the side-border scrolltexts, FLICK + per-line PINK on both planes' copper lists, and Z again gives back the original pixel for pixel; the border bands stay black; no zg.mem allocation refused; Escape leaves
gate ancool node apps/ancool_headless.mjs   # AN COOL (cart 9): 3600 frames, every composite (all enabled planes stacked as the browser does, HBLs included) equals the three-plane cart's (82db48da) per 300-frame period; ONE plane enabled every frame, <= 1 CHISEL blit a frame; the scroller raster is one colour register a line (one ink colour per line, 20+ colours in the band)
gate ancool node apps/ancool_headless.mjs --break skip     # ...and one extra frame at 2000 is caught
gate ancool node apps/ancool_headless.mjs --break planes   # ...and the three-plane cart (same pixels) fails the plane count
gate ancool node apps/ancool_headless.mjs --break raster   # ...and two inks on one line fail the raster check
gate larcociel5 node apps/larcociel5_headless.mjs "$SHOTS/larcociel5"   # DMA INTRO 5 "LARCOCIEL" (cart 93): every frame to 24 s the composited 320x200 window is the port's own model pixel for pixel AND, at 14 checkpoints, the Go re-creation's captured PNGs byte for byte; the ribbon clock's every word equals the model's each frame and, at step 149, the Go tree's native-ribbon-149.json checkpoint; the top raster and the perspective colour bank really repaint palette entries per scanline; the three Batman meters track the YM volume registers the cart itself writes; the YM delta stream fed to the chip equals the Go's music.ym register for register; no write refused, no zg.mem allocation refused; Space and Escape both leave
gate larcociel2 node apps/larcociel2_headless.mjs "$SHOTS/larcociel2"   # DMA INTRO 2 "LARCOCIEL" (cart 94): every frame to 24 s the composited 320x200 window is the port's own model pixel for pixel AND, at 14 checkpoints, the Go re-creation's captured PNGs byte for byte; the trail clock's every word equals the model's each frame and, at step 49, the Go tree's native-motion-49.json checkpoint (all 66 history points); the six projected ball poses and the whole scrolling slice window equal the model's every frame; the two rasters really repaint palette entries 8 (lines 0..15) and 4 (lines 49..92); the YM delta stream fed to the chip equals the Go's music.ym register for register; no write refused, no zg.mem allocation refused; Space and Escape both leave
gate bubblebobble node apps/bubblebobble_headless.mjs "$SHOTS/bubblebobble"   # BUBBLE BOBBLE (cart 95, the Go remake's playable campaign): the title and every page draw on the 400x280 overscan plane, the world runs its own 60 Hz (bbTestTick drives the SAME sim.Game the scene plays) — walking, the Go's jump arc, blowing and trapping an enemy in a bubble, popping it for score and dropped fruit, eating the fruit, the hurry-up at 30 s, a hit costing a life, the yellow-candy rapid-fire, all 25 campaign rounds loading with their own spawns, clearing a round, and no zg.mem allocation refused; Escape leaves
gate chonchon node apps/chonchon_headless.mjs "$SHOTS/chonchon"   # CHONCHON (cart 96): every frame to 24 s the composited 320x200 window is the port's own model pixel for pixel AND, at 14 checkpoints, the Go re-creation's captured PNGs byte for byte; the native motion's every word (stars, both ring scrollers, the chrome logo's phase) equals the model's each frame and, after 100 steps, both scroll banks equal the Go tree's own native scroll-bank checkpoints; the three plane-3 music meters track the YM volume registers the cart itself writes; the YM delta stream fed to the chip equals the Go's music.ym register for register; the per-line raster really repaints palette entries 8..15 on lines 144..199 (more colours than a static palette can); the border bands stay black; no write refused, no zg.mem allocation refused; Space and Escape both leave
gate ikplus node apps/ikplus_headless.mjs "$SHOTS/ikplus"   # THE REPLICANTS / "INTERNATIONAL KARATE PLUS" IK+ cracktro (cart 99): the cart's compiled scrolltext (1254 glyphs, 14 `^CsN;` codes, all four tile arrays) equals the harness's own copy of game.go's getFullText() (spc expansions included); off1/actSize/posY/posY2 and all eight stars equal the model every frame to 10.6 s; the composited 800x280 raster equals the model pixel for pixel at 320 frames (every frame to 6 s, then checkpoints), with both side borders open and BOTH rasters read back per line (54 distinct colours on one frame, not six); eliminator_jmp.sndh #1 requested once at start, then F1..F5 each request eliminator_jmp.sndh #1..#5 (Eliminator.sndh's five subtunes; the scrolltext's "PRESS F1-F5") and a repeated key requests nothing; Up/Down step spinc and Escape/Back leave; no zg.mem allocation refused
gate ikplus node apps/ikplus_headless.mjs --break raster "$SHOTS/ikplus_break"   # ...and the rainbow one row off is caught
gate ikplus node apps/ikplus_headless.mjs --break state "$SHOTS/ikplus_break"   # ...and one wrong star word is caught
gate ikplus node apps/ikplus_headless.mjs --break text "$SHOTS/ikplus_break"   # ...and a tile table that drifts from game.go is caught
gate ikplus node apps/ikplus_headless.mjs --break song "$SHOTS/ikplus_break"   # ...and F3 asking for the wrong subtune is caught
gate chonchon2 node apps/chonchon2_headless.mjs "$SHOTS/chonchon2"   # CHONCHON 2 (cart 100): every frame to 24 s the composited 320x200 window is the port's own model pixel for pixel; the motion clock, ribbon glyph bank, sliding panels and both sprite paths equal the model's words every frame; the per-line rasters repaint palette entries 0 and 2 on every visible line (more colours than a static palette can); the three music meters (planes 2/3) track the cart's embedded YM delta mirror, which equals the production's stream every frame; the first request is Jinks.sndh #1 and F1..F7 select the production's seven tracks; the border bands above/below the 200-line window stay black; no write refused, no zg.mem allocation refused; Space and Escape both leave
gate chonchon2 node apps/chonchon2_headless.mjs --break pixel "$SHOTS/chonchon2"   # ...and one recoloured line fails the window comparison
gate chonchon2 node apps/chonchon2_headless.mjs --break clock "$SHOTS/chonchon2"   # ...and one wrong motion word fails the clock/glyph/ribbon/screen checks
gate chonchon2 node apps/chonchon2_headless.mjs --break music "$SHOTS/chonchon2"   # ...and one wrong track request fails the F1..F7 match
gate chonchon2 node apps/chonchon2_headless.mjs --break yms "$SHOTS/chonchon2"   # ...and one wrong YM register byte fails the delta mirror
gate lockbuster3 node apps/lockbuster3_headless.mjs "$SHOTS/lockbuster3"   # LOCKBUSTER 3 (cart 101): every tick to 4800 the cart's front 320x240 index buffer, panel/scroll clocks, all 24 letter words and both restore rects equal a from-scratch model of go-lockbuster3; at the 43 native 68000 clock checkpoints (native-clock.csv) the clocks/letters equal the ORIGINAL's RAM; the composited 320x200 window is pixel for pixel every frame to 1200 and the full 400x280 frame (top and sides closed, the Go's rows 200..239 in the OPENED bottom border) at 25-tick checkpoints; text replaces bit 0 on rows 160..199 and entries 12/14 take Rasters[row-159] on real scanlines; the live Rollout SNDH #2's YM registers 0..12 equal the Go music.ym lanes for all 4800 ticks and the meters follow 8/9/10; Escape and Space leave, Backspace (ignored by the Go) does not; no zg.mem allocation refused
gate lockbuster3 node apps/lockbuster3_headless.mjs "$SHOTS/lockbuster3" --break pixels   # ...and one model window pixel off is caught
gate lockbuster3 node apps/lockbuster3_headless.mjs "$SHOTS/lockbuster3" --break front   # ...and the wrong double-buffer front (the Go's 1-front target) is caught
gate lockbuster3 node apps/lockbuster3_headless.mjs "$SHOTS/lockbuster3" --break clock   # ...and a panel clock one step out is caught
gate lockbuster3 node apps/lockbuster3_headless.mjs "$SHOTS/lockbuster3" --break music   # ...and a meter reading the next YM volume is caught
gate lockbuster3 node apps/lockbuster3_headless.mjs "$SHOTS/lockbuster3" --break raster   # ...and the raster table one row late is caught (only after a blank glyph exposes entries 12/14)
gate lockbuster3 node apps/lockbuster3_headless.mjs "$SHOTS/lockbuster3" --break keys   # ...and Backspace read as a leave key (the Go ignores it) is caught
gate phenomena node apps/phenomena_headless.mjs "$SHOTS/phenomena"   # PHENOMENA intro (cart 102, CODEF screen 560): every frame the phase chain (page 1's sliding bar, page 2's fade, the logo's grey and white silhouettes, both bars, the 139-frame photon drop, the red fade, go()) and the scroller queue (240..247 slices, msgIndex, pauses, speeds) equal apps/phenomena_model.mjs, written from screen.js; the 160 strip tops match screen.js's doubles to 1/256 row; the composited 800x280 raster equals the model pixel for pixel at 28 checkpoints; both bars are six per-line colours edge to edge; rasta_man.mod requested once, when the lower bar is in, and it plays (4 Paula channels); Escape/Back leave, Fire does nothing; no zg.mem allocation refused
gate phenomena node apps/phenomena_headless.mjs --break seq "$SHOTS/phenomena_break"   # ...and one wrong sequence word is caught
gate phenomena node apps/phenomena_headless.mjs --break dna "$SHOTS/phenomena_break"   # ...and one wrong scroller slice is caught
gate phenomena node apps/phenomena_headless.mjs --break pixels "$SHOTS/phenomena_break"   # ...and one wrong raster pixel is caught
gate phenomena node apps/phenomena_headless.mjs --break raster "$SHOTS/phenomena_break"   # ...and a bar without per-line colours is caught
gate phenomena node apps/phenomena_headless.mjs --break music "$SHOTS/phenomena_break"   # ...and the wrong tune name is caught
gate mentalhangover node apps/mentalhangover_headless.mjs "$SHOTS/mentalhangover"   # MENTAL HANGOVER (cart 103, Scoopex/Amiga): the six raw banks pinned by SHA-256 and the 59-glyph outline font / 213-byte control text equal the harness's own parse; all 3341 clock steps equal the model and the 3274 active steps equal the Go tree's original-circle-clock.csv word for word; the composited 800x280 raster equals the model pixel for pixel over 265 frames (even-odd contour text + shadow, mountain, the 49-band copper written per scanline from the HBL across both side borders, black margins, black once done); against the Go's own screenshot-2.png every visible copper row carries its source word and the SCOOPEX text mask matches exactly (shadow separately); mentalhangover.mod requested; Escape leaves, F does not; no zg.mem allocation refused
gate mentalhangover node apps/mentalhangover_headless.mjs --break state "$SHOTS/mentalhangover_break"   # ...and one wrong clock word is caught
gate mentalhangover node apps/mentalhangover_headless.mjs --break pixels "$SHOTS/mentalhangover_break"   # ...and one wrong pixel is caught
gate mentalhangover node apps/mentalhangover_headless.mjs --break raster "$SHOTS/mentalhangover_break"   # ...and a wrong copper line is caught
gate mentalhangover node apps/mentalhangover_headless.mjs --break text "$SHOTS/mentalhangover_break"   # ...and a drifted glyph point is caught
gate mentalhangover node apps/mentalhangover_headless.mjs --break music "$SHOTS/mentalhangover_break"   # ...and the wrong tune name is caught
gate gnomes node apps/gnomes_headless.mjs "$SHOTS/gnomes"   # THE GNOMES GROUP "BB25" Buxton Bytes 2025 cracktro (cart 104), re-ported from Hatari rips of the original: every frame to 1200 (then checkpoints to 3400) the composited 800x280 raster equals a model of the ORIGINAL's code (apps/gnomes_model.mjs: colour 0/1 per line, the swaying logo, VU meters, 13 TTY pages, the 8 px/frame scroller), and at 8 frames captured from the real intro in Hatari (ref/) the picture equals the capture in ST colour words, left-border latency and fresh-glyph race counted; music, keys, border rasters, no allocation refused
gate gnomes node apps/gnomes_headless.mjs --break raster "$SHOTS/gnomes_break"   # ...and the background roll one frame off is caught
gate gnomes node apps/gnomes_headless.mjs --break sweep "$SHOTS/gnomes_break"   # ...and the logo one frame early is caught
gate gnomes node apps/gnomes_headless.mjs --break scroll "$SHOTS/gnomes_break"   # ...and the scroller one column ahead is caught
gate gnomes node apps/gnomes_headless.mjs --break page "$SHOTS/gnomes_break"   # ...and page 2 typed wrong is caught
gate gnomes node apps/gnomes_headless.mjs --break vu "$SHOTS/gnomes_break"   # ...and the VU meters on the wrong channels is caught
gate gnomes node apps/gnomes_headless.mjs --break music "$SHOTS/gnomes_break"   # ...and the wrong tune name is caught
gate gnomes node apps/gnomes_headless.mjs --break pixels "$SHOTS/gnomes_break"   # ...and one wrong pixel is caught
gate hmdfac node apps/hmdfac_headless.mjs "$SHOTS/hmdfac"   # Hemoroids' Factory Cracktro, Team Factory tribute (cart 105, STe): four cube pages the ORIGINAL drew in Hatari (apps/hmdfac_original.json) equal the harness model's (wheel words + page hash: the solid six-face frustum by the $1047e edge walk and $bc08 span fill), and three phase-4 planar pages it drew equal the model's; the cart's own planar pages equal the model's; every frame the wheel counters, camera walk ($1356 -> $79e, hold, -> $1b9e), queue pair and index and the opening's screen offset equal the model's; the composited 800x280 raster equals the model pixel for pixel every frame to 1300 then checkpoints past the text's end: the 193-frame logo bob, the 777/EEE/666/DDD/555/CCC flash, all 498 cube frames (over a FULL art re-blit, pinning the cart's dirty-row restore) and phase 4 (the dot figure and the wave scroller in the font the machine renders, from the model's whole planar page), on every line the Timer B chain's split palette and both laser lines; hmd_cracoucass.sndh #1 requested once; Space pops colour 0 to $711 over the top lines and back; Escape/Back leave; no zg.mem allocation refused
gate hmdfac node apps/hmdfac_headless.mjs --break state "$SHOTS/hmdfac_break"   # ...and one wrong camera word is caught
gate hmdfac node apps/hmdfac_headless.mjs --break pixels "$SHOTS/hmdfac_break"   # ...and one wrong cube pixel is caught
gate hmdfac node apps/hmdfac_headless.mjs --break music "$SHOTS/hmdfac_break"   # ...and the wrong tune name is caught
gate hmdfac node apps/hmdfac_headless.mjs --break original "$SHOTS/hmdfac_break"   # ...and a page hash that is not the original's is caught
gate anima node apps/anima_headless.mjs "$SHOTS/anima"   # ANIMA (cart 107, a new ZigMachine multipart): the music sequence (cuddly_reset.sndh, silence at the gag's freeze, breath_2000.sndh at the tunnel); DARK every line closed, OPEN the sides opening from line 140, OLDSCHOOL the REAL raster in both side borders, the GAG's mistimed flicker filling the borders with noise, NEWSCHOOL every line open and covered; a composed frame of every part pinned by SHA-256; <= 200 CHISEL ops a frame; est. board cost of every part <= 1.75 Mc (apps/frame_cost.mjs)
gate anima node apps/anima_headless.mjs --no-cost --break hash "$SHOTS/anima_break"   # ...and a one-bit picture change is caught
gate anima node apps/anima_headless.mjs --no-cost --break border "$SHOTS/anima_break"   # ...and a line open in DARK is caught
gate anima node apps/anima_headless.mjs --no-cost --break raster "$SHOTS/anima_break"   # ...and a wrong raster colour on one line is caught
gate anima node apps/anima_headless.mjs --no-cost --break music "$SHOTS/anima_break"   # ...and a wrong tune in the sequence is caught
gate anima node apps/anima_headless.mjs --no-cost --break noise "$SHOTS/anima_break"   # ...and a gag without noise is caught
gate anima node apps/anima_headless.mjs --break cost "$SHOTS/anima_break"   # ...and a part over the cost ceiling is caught
gate leonard_spirit node apps/leonard_spirit_headless.mjs   # LEONARD'S SPIRIT (cart 108): 7 x 312 = 2,184 generated-code balls a frame, fullscreen on ONE overscan scroll plane; every frame of the show and a whole scrolltext lap (3,283 frames): the borders open exactly when the show says (180 still, then sides / bottom / top shake open), the scroll phase follows the ease-in to cruise, the window the hardware shows is the model byte for byte, and the composed 800x280 raster shows the plane where a border is open and the closed colour where it is shut, never noise; sos.sndh requested
gate leonard_spirit node apps/leonard_spirit_headless.mjs --break pixels   # ...and one wrong ball pixel is caught
gate leonard_spirit node apps/leonard_spirit_headless.mjs --break count   # ...and a 2,185th ball is caught
gate leonard_spirit node apps/leonard_spirit_headless.mjs --break music   # ...and the wrong tune name is caught
gate leonard_spirit node apps/leonard_spirit_headless.mjs --break palette   # ...and two swapped ball shades in the merged palette are caught
gate leonard_spirit node apps/leonard_spirit_headless.mjs --break border   # ...and one visible line whose flicker never happens is caught
gate leonard_spirit node apps/leonard_spirit_headless.mjs --break scroll   # ...and a linear ease-in instead of the square one is caught
gate leonard_spirit node apps/leonard_spirit_headless.mjs --break fall   # ...and a scrolltext that lands without bouncing is caught
gate leonard_spirit node apps/leonard_spirit_headless.mjs --break fade   # ...and extra snakes that pop in whole at full colour (no dissolve, no colour ramp) are caught
gate hippel_musicdisk node apps/hippel_musicdisk_headless.mjs   # JOCHEN HIPPEL MUSIC DEMO (cart 109, Amiga musicdisk): planes 0+1 as composed = a model of the original's copper list on all 400x280 for 600 frames (two COLOR00 bars, top one rotation behind; the 32-column COLOR01 rainbow scrolled a line a 50 Hz frame, 1 px lead; the $888 dual-playfield shadow); 5 steps in 6 frames; rings_of_medusa.hip song 1 at start, keys a..j/A..J the original's module + song, every .hip on the one RoM replay with enough songs; Escape leaves
gate hippel_musicdisk node apps/hippel_musicdisk_headless.mjs --break pixels   # ...and one wrong bar pixel is caught
gate hippel_musicdisk node apps/hippel_musicdisk_headless.mjs --break lead   # ...and copper columns without the 1-px lead are caught
gate hippel_musicdisk node apps/hippel_musicdisk_headless.mjs --break music   # ...and a key asking for the wrong song is caught
gate hippel_musicdisk node apps/hippel_musicdisk_headless.mjs --break pacing   # ...and a 60 Hz phase (not the original's 50) is caught
gate linebase_test node apps/linebase_test_headless.mjs   # LINE LIST TEST (cart 110, HW 1.10.0 copper LBASE + overscan HSCROLL): 420 frames, the plane shown equals the line-list model of the list the cart built (apps/linebase_model.mjs), borders included; the wobble HSCROLL, run-on lines, flipped bands, colour-0 raster and phase B's flip all used
gate linebase_test node apps/linebase_test_headless.mjs --break persist   # ...and a model whose lines do not run on from an LBASE is caught
gate linebase_test node apps/linebase_test_headless.mjs --break hscroll   # ...and a model ignoring overscan HSCROLL is caught
gate mindwind node apps/mindwind_headless.mjs "$SHOTS/mindwind"   # MIND REWIND (cart 111, Reservoir Gods STE 2003, from the depacked binary): one overscan plane on a 280-line list (LBASE), every part checked on the 800x280 raster: chrome bars = one colour 0 a line through both borders, part A's flat stripes, the wrapping picture, the cycling rainbow, the rewind's bands, the reversed half's VHS lines, the end logo
gate mindwind node apps/mindwind_headless.mjs "$SHOTS/mindwind_break" --break copper   # ...and a plane without its list is caught
gate mindwind node apps/mindwind_music_check.mjs   # ...its music (docs/music/mindwind.sndh: the demo's sequencer verbatim, a new mixer): a frame equals the original mixer's byte for byte, stereo, the song positions the parts wait on, the rewind one-shot and the reversed song
gate joust node apps/joust_headless.mjs --break clock "$SHOTS/joust"   # ...and 4 extra CPU cycles once fail them
gate rick_dangerous node apps/rick_dangerous_headless.mjs "$SHOTS/rick_dangerous"   # RICK DANGEROUS (the game): 18 recorded runs (10,890 frames: the level walks, deaths, GAME OVER, the name entries, the menus, the bots through all 4 levels) replayed in lockstep with the original's ACIA / Timer A bytes: every frame takes the original's VBLs and leaves its RAM + both screens + palette with the reference model's CRC, makes its play_sound requests (dropped or not) and the SNDH load / zg.sndhCall requests they imply, in order; live: title + tune, FIRE -> select -> intro -> level 1, the plane is the ST screen, 50 Hz time on a 60 Hz host, P, Escape; rick_dangerous.sndh's own driver RAM = the cart's for all 87 subtunes, and with later requests sndhCall-ed on the RUNNING driver (every id, the paired shot, dynamite x2)
gate rick_dangerous node apps/rick_dangerous_headless.mjs --break joy "$SHOTS/rick_dangerous"   # ...and one wrong stick byte fails the state CRC
gate rick_dangerous node apps/rick_dangerous_headless.mjs --break vbl "$SHOTS/rick_dangerous"   # ...and one VBL interrupt too many fails the VBL count
gate rick_dangerous node apps/rick_dangerous_headless.mjs --break sound "$SHOTS/rick_dangerous"   # ...and the drop rule's input flipped fails the play_sound check
gate rick_dangerous node apps/rick_dangerous_headless.mjs --break alloc "$SHOTS/rick_dangerous"   # ...and a refused zg.mem allocation fails the run
gate rick_dangerous node apps/rick_dangerous_headless.mjs --break sndh "$SHOTS/rick_dangerous"   # ...and the SNDH on the wrong subtune fails the driver RAM check
gate rick_dangerous node apps/rick_dangerous_headless.mjs --break reload "$SHOTS/rick_dangerous"   # ...and a later request forwarded as a reload (not an sndhCall) fails the resident check
gate rick_dangerous node apps/rick_cracktro_headless.mjs "$SHOTS/rick_cracktro"   # the Empire's CABAL cracktro in front (EMP_CABL.PRG, patched): the original text = Hatari's 4 screens pixel for pixel at the original's VBLs; RICK DANGEROUS on page 1 and nothing else changed; leavin_teramis.sndh #11 (= the original in Hatari), silence on Space; the 3 trainer questions, the cursor every 30 VBLs, y/n/Y; the game and its tune after; Escape leaves; each trainer flag stops its decrement in the game's replays (off: down, on: never)
gate rick_dangerous node apps/rick_cracktro_headless.mjs --break trainer "$SHOTS/rick_cracktro"   # ...and the flags not set: caught by the trainer check
gate rick_dangerous node apps/rick_cracktro_headless.mjs --break text "$SHOTS/rick_cracktro"   # ...and the patched text against the original's screens: caught by the pixels
gate rick_dangerous node apps/rick_cracktro_headless.mjs --break timing "$SHOTS/rick_cracktro"   # ...and the typing restarted after the first screen: caught by the original's VBLs (the check itself has 1-VBL resolution: it caught the ESC E clear's extra VBL, 3613 for 3614)
gate skystrike node apps/skystrike_headless.mjs "$SHOTS/skystrike"   # SKYSTRIKE (the STOS game, Automation 258): in lockstep, the title, the menu, the briefing, the first frame of play, a crash landing and the hall of fame = the original's RAM on Hatari pixel for pixel; 98 passes of takeoff = its trace; keys, the engine note, the guns, an enemy hit (+200), killed / no more aircraft -> music 2 -> the title; live 60 Hz + Escape; skystrike.sndh's tunes, digis (stopping) and engine registers
gate skystrike node apps/skystrike_headless.mjs --break screen "$SHOTS/skystrike"   # ...and Medium chosen for Easy fails the screens
gate skystrike node apps/skystrike_headless.mjs --break physics "$SHOTS/skystrike"   # ...and throttle 8 for 9 fails the takeoff trace
gate skystrike node apps/skystrike_headless.mjs --break sound "$SHOTS/skystrike"   # ...and a bomb for the gun burst fails the SFX check
gate skystrike node apps/skystrike_headless.mjs --break sndh "$SHOTS/skystrike"   # ...and the wrong sample fails the digi check
gate skystrike node apps/skystrike_headless.mjs --break alloc "$SHOTS/skystrike"   # ...and a refused zg.mem allocation fails the run
gate skystrike node apps/skystrike_levels.mjs   # SKYSTRIKE levels: the Tiled maps (tools/skystrike/levels.py) round-trip MISSIONS.DAT + SCRNDATA.DAT byte for byte and ARE the cart's data; 22 broken maps refused; a disk with an edited mission is briefed and played; a bad disk file stops on the error trap
gate skystrike node apps/skystrike_levels.mjs --break disk   # ...and a disk of the built-in data fails the custom-mission check
gate skystrike node apps/skystrike_zig.mjs "$SHOTS/skystrike_zig"   # SKYSTRIKE ZIG mode: sectors crossed left/right and layers up/down with no redraw pause and the camera gliding; each screen entered = its ring slot pixel for pixel; switched by Z mid-flight or ZIG throughout, the logic CRC after every pass = ORIGINAL's; the 400x280 frame = ring + overlay with the borders open and the HUD in them; tracers on the heading (on the runway too), none in ORIGINAL; the key help over ZIG's pause only; the title, menu and briefing 1:1 with the neighbouring sectors and the sky in the open borders and the title's credits scroller white in the bottom one; the hall of fame's picture scaled under its text 1:1; the HUD and bar 20 lines inside it; an enemy past the world's left end in the left border; no ghost plane where a bomb bursts (both modes); Ctrl/Shift/Space = the chords; a crashed enemy's crater fills in after 30 s (ORIGINAL keeps it); no zg.mem refused; the MOD for each of the game's music switch points (title, flight, pause, game over), skystrike.sndh in ORIGINAL, Z swapping them, the title's music credits line in ZIG only; each effect over the flight's MOD on its lent channel, given back at its end (the gun at SAMSTOP), the engine note on the YM = the game's commands; each MOD at its situation's gain, and in flight every effect 3+ dB (mean 5+) over the music bed and the engine under the effects
gate skystrike node apps/skystrike_zig.mjs --break pause "$SHOTS/skystrike_zig"    # ...and the crossings flown in ORIGINAL fail (a)
gate skystrike node apps/skystrike_zig.mjs --break ring "$SHOTS/skystrike_zig"     # ...and one ring pixel flipped fails (b)
gate skystrike node apps/skystrike_zig.mjs --break crc "$SHOTS/skystrike_zig"      # ...and X (a key the game reads) for Z fails (c)
gate skystrike node apps/skystrike_zig.mjs --break border "$SHOTS/skystrike_zig"   # ...and ORIGINAL's frame fails (d)
gate skystrike node apps/skystrike_zig.mjs --break alloc "$SHOTS/skystrike_zig"    # ...and a refused zg.mem allocation fails (e)
gate skystrike node apps/skystrike_zig.mjs --break sound "$SHOTS/skystrike_zig"    # ...and the sample table swapped fails the sound check
gate skystrike node apps/skystrike_zig.mjs --break tracer "$SHOTS/skystrike_zig"   # ...and the heading turned 90 degrees fails the tracer check
gate skystrike node apps/skystrike_zig.mjs --break help "$SHOTS/skystrike_zig"     # ...and ORIGINAL's pause searched for the key help fails the pause check
gate skystrike node apps/skystrike_zig.mjs --break intro "$SHOTS/skystrike_zig"    # ...and the intro screens expected scaled by 5/4 fails the screens check
gate skystrike node apps/skystrike_zig.mjs --break hiscore "$SHOTS/skystrike_zig"  # ...and the hall's text expected scaled with its picture fails the screens check
gate skystrike node apps/skystrike_zig.mjs --break hud "$SHOTS/skystrike_zig"      # ...and the panel and bar looked for on the frame's edges fails (d)
gate skystrike node apps/skystrike_zig.mjs --break landed "$SHOTS/skystrike_zig"   # ...and the runway's tracers looked for off the heading fails the landed check
gate skystrike node apps/skystrike_zig.mjs --break left "$SHOTS/skystrike_zig"     # ...and the left enemy two sectors away fails the border check
gate skystrike node apps/skystrike_zig.mjs --break ghost "$SHOTS/skystrike_zig"    # ...and the bomb's ground band searched for the ghost fails the ghost check
gate skystrike node apps/skystrike_zig.mjs --break keys "$SHOTS/skystrike_zig"     # ...and Shift compared with FIRE + left fails the keys check
gate skystrike node apps/skystrike_zig.mjs --break crater "$SHOTS/skystrike_zig"   # ...and the crater lifetime at never fails the craters check
gate skystrike node apps/skystrike_zig.mjs --break music "$SHOTS/skystrike_zig"    # ...and the flight's MOD expected on the title fails the music check
gate skystrike node apps/skystrike_zig.mjs --break swap "$SHOTS/skystrike_zig"     # ...and Z expected to leave the music alone fails the swap check
gate skystrike node apps/skystrike_zig.mjs --break credits "$SHOTS/skystrike_zig"  # ...and the credits line looked for in ORIGINAL fails the credits check
gate skystrike node apps/skystrike_zig.mjs --break gain "$SHOTS/skystrike_zig"     # ...and the flight's music gain expected on the title fails the gain check
gate skystrike node apps/skystrike_zig.mjs --break mix "$SHOTS/skystrike_zig"      # ...and the flight's music at gain 1.0 (the effects 8 dB under it) fails the mix check
gate skystrike python3 tools/skystrike/make_sfx.py --check   # ZIG mode's synthesized samples = the committed sfx/*.raw (the cart embeds them: zig_fx.zig)
gate_timed ulm_dsots node apps/ulm_dsots_headless.mjs "$SHOTS/ulm_dsots"   # ULM DARK SIDE OF THE SPOON menu vs the melonJS remake in Chrome (apps/ulm_dsots_ref.json.gz): 960 steps of griffin/viewport/parallax state equal, 9 canvases pixel for pixel, Space in mid-air opens nothing and at the temple door (the remake's DoorEntity frame) asks for demo-ulm_spoon_distorter, Escape asks for the menu, 60 steps a second at 144 Hz and one a frame at 60 Hz, no zg.mem refused, mean frame < 4 ms
gate ulm_dsots node apps/ulm_dsots_headless.mjs --break alloc "$SHOTS/ulm_dsots_break"     # ...and a refused zg.mem allocation fails the alloc check
gate ulm_dsots node apps/ulm_dsots_headless.mjs --break physics "$SHOTS/ulm_dsots_break"   # ...and "up" let go one step late fails the physics trace
gate ulm_dsots node apps/ulm_dsots_headless.mjs --break render "$SHOTS/ulm_dsots_break"    # ...and the canvas read one pixel off fails the render check
gate ulm_dsots node apps/ulm_dsots_headless.mjs --break door "$SHOTS/ulm_dsots_break"      # ...and Space pressed before the door fails the door check
gate naos_nitrowave node apps/naos_nitrowave_headless.mjs "$SHOTS/naos_nitrowave"   # NAOS NITROWAVE vs the ORIGINAL disk on Hatari (apps/naos_nitrowave_ref.json.gz): the menu (12 frames to 1100), F2 big sprite (9 to 1700) and F3 Sapristi (10 to 560, colours changed along the lines) = the captures, every pixel of the 400x280 plane as ST colours; F1 multisprites (best effort): all four figures entered, title exact, 18 frames >= 99% of Hatari's pixels; each program its tune; F1/F2/F3 enter, freeze keys, Space back to the menu / out
gate naos_nitrowave node apps/naos_nitrowave_headless.mjs --break late "$SHOTS/naos_nitrowave_break"   # ...and each frame held against the next VBL's capture is caught
gate naos_nitrowave node apps/naos_nitrowave_headless.mjs --break shift "$SHOTS/naos_nitrowave_break"  # ...and the plane read one pixel off is caught
gate naos_nitrowave node apps/naos_nitrowave_headless.mjs --break figure "$SHOTS/naos_nitrowave_break" # ...and F1 held against another figure's capture is caught
gate tcb_spreadpoint node apps/tcb_spreadpoint_headless.mjs "$SHOTS/tcb_spreadpoint"   # TCB SPREADPOINT (CODEF 469): screen.js replayed (intro fades, angle table, balls, 33-speed scroller, DNA scrolltext) and at 12 frames across the intro and 6000 main-part iterations the plane is its indices pixel for pixel; the 3 rasters are HBL register writes (entries 2..6 hold the tables on every line, <=4 changes a line) and every composited pixel is its line's colour; tcb_spreadpoint.sndh requested once, at the main part, and plays
gate tcb_spreadpoint node apps/tcb_spreadpoint_headless.mjs --break hbl "$SHOTS/tcb_spreadpoint"   # ...and a plane whose HBL never runs is caught
gate tcb_spreadpoint node apps/tcb_spreadpoint_headless.mjs --break step "$SHOTS/tcb_spreadpoint"   # ...and one frame out of step with screen.js is caught
gate stcs node apps/stcs_headless.mjs   # STCS STARGOOSE: every frame of a whole 9420-VBL cycle (all seven scroller shapes, rasters and band palettes included) is the pre-CHISEL CPU scroller's COMPOSED picture, byte for byte (the logo now rides the scroller plane)
gate stcs node apps/stcs_headless.mjs --break skip   # ...and one extra VBL is caught (in the periods after it only)
gate stcs node apps/stcs_zig_headless.mjs   # STCS ZIG MODE (Z): over the whole cycle, beside an untouched copy: 1/2/3 do nothing in ORIGINAL; in ZIG the letters run through the opened side borders in all seven shapes, the logo fades, stars scroll right to left behind logo and letters; 1, 2, 3 each turn their effect off (sides, logo, stars back to ORIGINAL's); Z again is ORIGINAL pixel for pixel
gate stcs node apps/stcs_zig_headless.mjs --break nokeys   # ...and a cart that ignores Z is caught
gate stcs node apps/stcs_zig_headless.mjs --break key1   # ...and borders that never close on 1 are caught
gate stcs node apps/stcs_zig_headless.mjs --break key3   # ...and stars that never leave on 3 are caught
gate stcs_css3 node apps/stcs_css3_headless.mjs "$SHOTS/stcs_css3"   # STCS 3RD CSS CONVENTION (original ST binary): at 149 sampled VBLs over 6000 (black pre-roll, picture, star release, warp, main loop, scroller and its pauses, the letters turning round) the whole displayed frame, border colour per physical row included, is the reference model's (itself byte-exact against Hatari); the Timer B bands and the bar run through both borders; thrust.sndh starts with the picture; Space and Escape leave
gate stcs_css3 node apps/stcs_css3_headless.mjs --break noclear "$SHOTS/stcs_css3"   # ...and a border never painted per line is caught
gate stcs_css3 node apps/stcs_css3_headless.mjs --break timerb "$SHOTS/stcs_css3"   # ...and a plane whose Timer B HBL never runs (one palette for all lines) is caught
gate stcs_css3 node apps/stcs_css3_headless.mjs --break skip "$SHOTS/stcs_css3"   # ...and one lost VBL is caught
gate tcb_weirddream node apps/tcb_weirddream_headless.mjs "$SHOTS/tcb_weirddream"   # TCB WEIRD DREAM: 51 frames equal a JS replay of screen.js pixel for pixel (splash reveal, logo zoom frames and parities, stars, precalc_scroll_x run verbatim, the cosine band, the sprites); colour 0 is the border on every line, grey through the splash and black from go()'s first frame; rollout.sndh tune 1 at go()'s start, F1/F2 as screen.js
gate tcb_weirddream node apps/tcb_weirddream_headless.mjs --break table "$SHOTS/tcb_weirddream"   # ...and a scroll table read one entry late is caught
gate tcb_weirddream node apps/tcb_weirddream_headless.mjs --break noclear "$SHOTS/tcb_weirddream"   # ...and a border never painted is caught
gate tcb_weirddream node apps/tcb_weirddream_headless.mjs --break keys "$SHOTS/tcb_weirddream"   # ...and a wrong F1/F2 rule is caught
gate swedish_newyear node apps/swedish_newyear_headless.mjs "$SHOTS/swedish_newyear"   # SWEDISH NEW YEAR: SYNC #1/#2, TCB #1/#2 and OMEGA ported from the disk, each shot vs the real demo (models / the original code on Musashi, reproducing Hatari RAM): screen, per-line colour registers (rasters), physical frame with borders (OMEGA's LED meters in the opened bottom border); TCB #2 set-up black; menu vs the CODEF remake replayed; every tune its SNDH/subtune and playing
gate swedish_newyear node apps/swedish_newyear_headless.mjs --break hbl "$SHOTS/swedish_newyear"   # ...and without the HBL the per-line registers are caught
gate snyd_90 node apps/snyd_90_headless.mjs "$SHOTS/snyd_90"   # SWEDISH NEW YEAR 89-90, ported from the disk: the intro's Spectrum 512 picture = spu.py's decode (pixel-checked vs Hatari), the menu, F1 and F2 = the original code (byte-checked); F3..F6 best effort: motion, colours vs Hatari's capture, borders open where the original opens them; every part's tune requested and playing; Escape
gate snyd_90 node apps/snyd_90_headless.mjs --break hbl "$SHOTS/snyd_90_break"    # ...and without the HBL the per-line colours are caught
gate snyd_90 node apps/snyd_90_headless.mjs --break step "$SHOTS/snyd_90_break"   # ...and one VBL too many is caught
gate snyd_90 node apps/snyd_90_headless.mjs --break tune "$SHOTS/snyd_90_break"   # ...and a wrong subtune is caught
gate snyd_90 node apps/snyd_90_headless.mjs --break f3 "$SHOTS/snyd_90_break"     # ...and an F3 that never runs a VBL is caught (motion, look, its open bottom border)
gate snyd_90 node apps/snyd_90_headless.mjs --break f4 "$SHOTS/snyd_90_break"     # ...and an F4 that never runs a VBL is caught (motion, look)
gate snyd_90 node apps/snyd_90_headless.mjs --break f5 "$SHOTS/snyd_90_break"     # ...and an F5 that never runs a VBL is caught (motion, look, its full overscan)
gate snyd_90 node apps/snyd_90_headless.mjs --break f6 "$SHOTS/snyd_90_break"     # ...and an F6 that never runs a VBL is caught (motion, look, its open bottom border)
gate snyd_90 node apps/snyd_90_pins.mjs   # every frame (60 Hz host) of the intro, the menu and F1..F6 (F3 with panel keys) = the cart before the incremental shifter: plane indices + physical RGB, 3660 frames
gate snyd_90 node apps/snyd_90_pins.mjs --break   # ...and one plane pixel altered is caught
gate swedish_newyear node apps/swedish_newyear_headless.mjs --break step "$SHOTS/swedish_newyear"   # ...and one extra cart frame is caught
gate swedish_newyear node apps/swedish_newyear_headless.mjs --break tune "$SHOTS/swedish_newyear"   # ...and a wrong subtune is caught
gate swedish_newyear node apps/swedish_newyear_headless.mjs --break border "$SHOTS/swedish_newyear"   # ...and a border left with last frame's colour 0 is caught
gate swedish_newyear node apps/swedish_newyear_headless.mjs --break meters "$SHOTS/swedish_newyear"   # ...and OMEGA's LED meters fed a frame late are caught
gate gen4_3615 node apps/gen4_3615_headless.mjs "$SHOTS/gen4_3615"   # ULM 3615 GEN4: screen.js replayed (matched to the page in Chrome) at twelve frames from 1 to 30000 (the motif table's wrap at 603, the frame THE FATE is called at 2480), through all six waveforms, with the YM volumes driven: the whole 400x280 plane pixel for pixel; the sky, VU colours and floor shading are colour registers changed per line; side and bottom borders open, top shut; the remake's SNDH plays
gate gen4_3615 node apps/gen4_3615_headless.mjs --break fate "$SHOTS/gen4_3615"   # ...and the logo's slices one canvas row down is caught
gate gen4_3615 node apps/gen4_3615_headless.mjs --break ulm "$SHOTS/gen4_3615"   # ...and the ULM table one entry late is caught
gate gen4_3615 node apps/gen4_3615_headless.mjs --break raster "$SHOTS/gen4_3615"   # ...and a sky raster one line out is caught
gate_timed dune_gen4 node apps/dune_gen4_headless.mjs "$SHOTS/dune_gen4"   # DUNE GEN4 DEMO vs DUNE.PRG in Hatari (apps/dune_gen4_ref.bin.br): 60 frames as ST colour words, borders and rasters included -- the intro bounce, the fade-in, the main part (letters, colour-0 bars, rainbow, lower-border scroller), the title, seven menu visits, two F1, two F2 (HADES) and one F3 (SOUND.TNY) visit walked with three original runs' keys; Gen4.sndh, the title's Quartet song, the poked copy for the menu, F3..F6's songs; Escape
gate dune_gen4 node apps/dune_gen4_headless.mjs --break pixels "$SHOTS/dune_gen4_break"   # ...and a main-part frame one VBL late is caught
gate dune_gen4 node apps/dune_gen4_headless.mjs --break lag "$SHOTS/dune_gen4_break"      # ...and the bounce shown without the screen latch is caught
gate dune_gen4 node apps/dune_gen4_headless.mjs --break music "$SHOTS/dune_gen4_break"    # ...and the menu playing the main part's tune is caught
gate dune_gen4 node apps/dune_gen4_headless.mjs --break quartet "$SHOTS/dune_gen4_break"  # ...and the title asking for the wrong Quartet song is caught
gate dune_gen4 node apps/dune_gen4_headless.mjs --break sound "$SHOTS/dune_gen4_break"    # ...and F3 opening on the wrong song is caught
gate dune_gen4_music node apps/irq_native_check.mjs --song dune_gen4_quartet.sndh --status 9 --seconds 40   # the title's Quartet tune: SingSong's 4-voice interrupt, its state in d0-d3/a0-a3, natively = the 68000 bit for bit, modes 1/2 unbroken
gate dune_gen4_music node apps/irq_native_check.mjs --song dune_gen4_quartet.sndh --status 9 --seconds 20 --break --mutant 7   # ...and the sample index read unsigned (mutant 7) is caught
gate dune_gen4 node apps/sndh_headless.mjs docs/music/dune_gen4_quartet.sndh 4             # the Quartet SNDH (SingSong + SOUND2.SET + DUNE.PRG's songs) plays the title's song on the sealed YM
gate dune_gen4 node apps/sndh_headless.mjs docs/music/dune_gen4_quartet.sndh 2             # ...and another subtune (F3's)
gate c_fujiboink node apps/c_fujiboink_headless.mjs "$SHOTS/c_fujiboink"   # FUJIBOINK! (C, START 1986): nine Hatari captures of FUJIBOIN.PRG, six pixel for pixel and three within a one-VBL mid-frame sliver; the rainbow is Timer B's 73 register lines (every pixel an ST index, entry 4 rewritten per line); the thud SNDH lands with the fuji and decays; F-key freeze, Space and Escape leave
gate c_fujiboink node apps/c_fujiboink_headless.mjs --break rasters "$SHOTS/c_fujiboink"   # ...and a plane whose HBL never runs (one static palette) is caught
gate c_fujiboink node apps/c_fujiboink_headless.mjs --break thud "$SHOTS/c_fujiboink"   # ...and a lost thud request is caught
gate c_bench node apps/bench_headless.mjs   # BENCH (C, apps/c/bench): the Hatari suite run to completion, 7 jobs in ~8 ms slices; on a clock that steps 100 ms a read the rates are exact (CoreMark 10.00, Dhrystone 1.13 DMIPS, Whetstone 1.00, LINPACK 3433.33 KFLOPS, RAM 0.31 MB/s); CoreMark's CRCs, Dhrystone's final values, Whetstone's checksum (pinned) and LINPACK's residual pass on the real clock too (timings printed are a browser's, not the board's); key 1 reruns and logs every result once; hostMicros = 0 prints "no clock" and no number
gate c_bench node apps/bench_headless.mjs --break crc   # ...and a corrupted CoreMark CRC table is caught
gate c_bench node apps/bench_headless.mjs --break dhry   # ...a corrupted Dhrystone final value
gate c_bench node apps/bench_headless.mjs --break resid   # ...a corrupted LINPACK solution
gate c_bench node apps/bench_headless.mjs --break clock   # ...and a no-clock run that is expected to print numbers
gate ports_pt2 node apps/ports_headless.mjs pt2   # PT2-CLONE (C, apps/ports): its GEM data disk runs the SDL boot sector (request 2), GEM lists its files, a double-click runs BOOT.WSM = the committed cart with only env imports, 300 frames no trap, the UI pinned; DISK OP (a click) lists the floppy, a click on HYBRID.MOD loads it (the song-name row changes), PLAY is heard; Esc, Esc quits back to the desktop exactly as it was (request 4)
gate ports_pt2 node apps/ports_headless.mjs pt2 --break load   # ...and the file never clicked (nothing loaded, nothing heard) is caught
gate ports_pt2 node apps/ports_headless.mjs pt2 --break quit   # ...and the quit never asked for (no desktop) is caught
gate ports_pt2 node apps/ports_headless.mjs pt2 --clock 33333   # ...and with the board's clock (hostMicros 33 ms a frame, dt 16.6): the audio fed follows the clock, not dt (kestrel_audio.h)
gate ports_pt2 node apps/pt2_paula_headless.mjs   # ...and on the machine's hardware Paula channels (HW 1.14.0, env.hostPaula*, the real worklet): pt2 claims them and stops its stream, RONKEN.MOD plays with every write landed at its sample, its loudness and semitone spectrum follow the software mixer's, a song request while it holds them is refused
gate ports_pt2 node apps/pt2_paula_headless.mjs --break pitch   # ...and every period doubled on the way (an octave down) is caught
gate ports_pt2 node apps/pt2_paula_headless.mjs --break latch   # ...and LC/LEN taken at once, not at the wrap (paula.zig mutant 2), is caught
gate ports_pt2 node apps/pt2_paula_headless.mjs --break upload   # ...and no sample uploaded to chip RAM is caught
gate ports_pt2 node apps/pt2_paula_headless.mjs --break owner   # ...and the worklet's refusal bypassed (a song let in over chip RAM) is caught
gate ports_grafx2 node apps/ports_headless.mjs grafx2   # GRAFX2 (C, GPLv2, Asyncify): boots on its skin + font off the floppy, the read-only warning pinned, OK closes it (a modal loop resumed across frames), the tool bar and palette shown, a freehand stroke paints 46 pixels; Q + Discard quits back to GEM
gate ports_grafx2 node apps/ports_headless.mjs grafx2 --break stroke   # ...and no stroke is caught
gate ports_grafx2 node apps/ports_headless.mjs grafx2 --break quit   # ...and no quit is caught
gate ports_grafx2 node apps/gemdos_grafx2_check.mjs   # KOS GEMDOS (docs/KOS_GEMDOS.md): GrafX2 launched from GEM with docs/gemdos-c.img as C:; its file selector offers "/C", lists C:\, PICTURES, PLASMA (pinned), and ZIGPLASM.PI1 loaded from C:\PICTURES\PLASMA equals, frame hash for hash, the floppy's copy loaded; C: costs <= 16 round trips
gate ports_grafx2 node apps/gemdos_grafx2_check.mjs --break c   # ...and a C: that answers nothing (kosDriveRead 0) is caught
gate ports_grafx2 node apps/gemdos_grafx2_check.mjs --break bytes   # ...and one byte of the picture changed on C: is caught (the oracle checks the bytes)
gate ports_grafx2 node apps/gemdos_grafx2_save.mjs   # KOS GEMDOS phase 2 (docs/KOS_GEMDOS.md §7): GrafX2 saves the loaded picture as C:\PICTURES\NEW.PI1 (F2, /C, PICTURES, NEW typed) in ONE kosFileOp request; the image then holds it byte for byte (mtools, fsck.fat -n clean); a new session lists it (pinned) and re-opens it: the picture's rows equal the floppy's copy loaded
gate ports_grafx2 node apps/gemdos_grafx2_save.mjs --break write   # ...and a host that refuses writes is caught
gate ports_grafx2 node apps/gemdos_grafx2_save.mjs --break torn   # ...and a save whose sectors stop half way is caught
gate ports_grafx2 node apps/gemdos_grafx2_save.mjs --break bytes   # ...and a byte changed on its way to the host is caught
gate ports_klystrack node apps/ports_headless.mjs klystrack   # KLYSTRACK (C, Asyncify): boots on the Default theme bundle with STARPRT2.KT opened off the floppy, launched from GEM, UI pinned; the pointer moves over the idle UI (no repaint); F5 after cyd went quiet hands the song to the machine's .kt player (a .kt via requestSongBytes kind 5 that the audio modules play, cyd's stream stopped) and the screen follows play; a note typed while it plays re-sends it from the row playing; Esc (and No to "Save song?") quits back to GEM
gate ports_klystrack node apps/ports_headless.mjs klystrack --break silent   # ...and F5 never pressed (silence) is caught
gate ports_klystrack node apps/ports_headless.mjs klystrack --break edit   # ...and no edit while it plays (nothing re-sent) is caught
gate ports_klystrack node apps/ports_headless.mjs klystrack --break pointer   # ...and a pointer that never moves is caught
gate ports_klystrack node apps/ports_headless.mjs klystrack --break quit   # ...and no quit is caught
gate ports_klystrack node apps/klystrack_cost.mjs   # KLYSTRACK repaint cost (apps/frame_cost.mjs est. Mc, deterministic): playing STARPRT2 median repaint <= 1.8, worst row change <= 9.5, mean <= 2.3 a frame; the menu bar open with the pointer moving <= 1.25; both mean <= 2.9; the instrument tab while playing mean <= 1.35, worst <= 1.9; File > Import's sub-menu, over one item <= 1.7, crossing its items while playing mean <= 10 (round 4: 41-48, the command list overflowed); Edit > Pattern's sub-menu over the instrument tab, over one item <= 1.6, crossing its items while playing mean <= 4.5 (round 5: 39.6 / 40.1, the list overflowed again; round 6: a bevel's uniform parts one copy each) (round 5: the menu a layer over a snapshot, occluded tiles, scrolled caches name only their changed tiles, the instrument tab skipped; round 4 was 1.47 / 9.3 / 2.03, instrument tab 2.0 / 3.2)
gate ports_klystrack node apps/klystrack_cost.mjs --break cost   # ...and ceilings of ~0 are caught
gate ports_klystrack make -s -C apps/ports/klystrack printf-test   # KLYSTRACK labels: kestrel_printf.c (the conversions it does itself, the rest handed to libc) equals the host C library's vsnprintf over 3,834 format/value/buffer-size cases (native zig cc)
gate ports_chipnomad node apps/ports_headless.mjs chipnomad   # CHIPNOMAD (C++): the song screen in the ST font pinned; X (the A button) puts chain 00 in the first cell; chain -> phrase -> a C-4 on instrument 00 made AY Classic, START plays it: the stream is not silent; Settings > Quit ChipNomad goes back to GEM
gate ports_chipnomad node apps/ports_headless.mjs chipnomad --break key   # ...and X never pressed is caught
gate ports_chipnomad node apps/ports_headless.mjs chipnomad --break silent   # ...and START never pressed (silence) is caught
gate ports_chipnomad node apps/ports_headless.mjs chipnomad --break quit   # ...and no quit is caught
gate ports_sidwizard node apps/ports_headless.mjs sidwizard   # SID-WIZARD (C, Hermit's C64 program on its own libcRSID C64): launched from GEM, FLASHBAK.SWM opened off the floppy at start (upstream's command-line key simulator), the editor pinned; Tab (an owner-only key code, 0xE019 = C64 CONTROL) steps the cursor to track 2, Down, Space (editing) and W type a note there; F1 plays the song, heard on the page's SID live (the BARD queue); Shift+F8, Y quits back to GEM
gate ports_sidwizard node apps/ports_headless.mjs sidwizard --break silent   # ...and F1 never pressed (silence) is caught
gate ports_sidwizard node apps/ports_headless.mjs sidwizard --break tab   # ...and Tab never pressed (the cursor stays on track 1) is caught
gate ports_sidwizard node apps/ports_headless.mjs sidwizard --break edit   # ...and no note typed (track 2's row 1 stays empty) is caught
gate ports_sidwizard node apps/ports_headless.mjs sidwizard --break quit   # ...and no quit is caught
gate ports_sidwizard node apps/sidwizard_save.mjs   # SID-WIZARD saves to C: (KOS GEMDOS): F8, SAVE TUNE, into the floppy root's "C" folder, MYSONG: C:\MYSONG.SWM is the floppy's FLASHBAK.SWM byte for byte past its load address
gate ports_sidwizard node apps/sidwizard_save.mjs --break write   # ...and a host that refuses writes (no file) is caught
gate ports_sidwizard node apps/sidwizard_bard_check.mjs   # SID-WIZARD's SID on BARD (the BARD queue, table 1.12): every SID write stamped with its C64 cycle; page (loader + worklet + audio modules) = native host_audio, 14.8 s of Flash It Back from the first heard sample; 20 ms and 60 ms frames make the same writes and samples (the C64 runs on the frame's time); with the main program held ~3/4 of each frame (a late host clock) the song's ticks are unchanged
gate ports_sidwizard node apps/sidwizard_bard_check.mjs --break stamp   # ...and the loader delaying every SID write two samples fails parity
gate ports_sidwizard node apps/sidwizard_bard_check.mjs --break reg   # ...and the loader writing the next SID register fails parity
gate ports_sidwizard node apps/sidwizard_cpu_check.mjs   # SID-WIZARD's fast 6502 (kestrel_sw_cpu.c, the registers in locals) = libcRSID's own, byte for byte: every opcode on 48 random C64s (the whole 275 KB machine compared after one instruction) and 4,000 C64 samples of random code (interrupts, the wait, I/O)
gate ports_sidwizard node apps/sidwizard_cpu_check.mjs --break   # ...and a wrong ADC carry is caught
gate fallen_angels node apps/fallen_angels_headless.mjs "$SHOTS"   # per-plane rasters on all 200 lines
gate tex_loader_fx node apps/tex_loader_fx_headless.mjs "$SHOTS/tex_loader_fx"   # fx = tex_loader on a real asset, bytes checked
gate_timed tex node apps/tex_headless.mjs "$SHOTS"             # the eleven sprites on screen.js's chain
gate equinox node apps/equinox_headless.mjs "$SHOTS"   # the dragons morph egg -> dragon -> egg
gate tex_neoshow node apps/tex_neoshow_headless.mjs "$SHOTS/tex_neoshow"   # TEX NEO SHOW: the scroller band is a REAL per-line raster (copper), full plane width
gate tex_neoshow_music node apps/monty_native_check.mjs   # its tune (Monty, Timer D digidrums) played natively = the 68000, bit for bit over 50 s, modes 1/2 unbroken
gate tex_neoshow_music node apps/monty_native_check.mjs --break   # ...and volume C written over the drums (mutant 3) is caught
gate mpp_truecolor node apps/mpp_truecolor_headless.mjs "$SHOTS"   # per-line palettes: colours on screen = captions; the copper lists load exactly the converter's records; mode 3 is ONE true-colour plane showing the converter's 565 picture
gate mpp_truecolor node apps/mpp_truecolor_headless.mjs --break k1tail   # ...and a 256-entry line that loses its entry-255 PALREF is caught
gate truecolor node apps/truecolor_check.mjs   # the true-colour plane (HW 1.15.0): modes 5 and 6 composited by the machine equal an independent model pixel for pixel: all 65,536 565 values expanded by bit replication, the window and the whole raster, odd FB_BASE / stride / HSCROLL (bit 0 ignored), HSCROLL per line, copper LBASEs, the frame restarting from FB_BASE
gate truecolor node apps/truecolor_check.mjs --break   # ...and a model with the expansion by shift, bit 0 honoured, the stride in pixels, HSCROLL latched, mode 6 as a window or LBASE ignored is caught
gate_timed union_textracker node apps/union_textracker_headless.mjs "$SHOTS"   # TEX loader depack, then screen.js replayed pixel for pixel
gate_timed union_demo_intro node apps/union_demo_intro_headless.mjs "$SHOTS"   # TEX loader depack, then every pixel on the screen.js replay
gate_timed stream_pacing node apps/stream_pacing_check.mjs   # streamed audio tracks wall time at 18 fps, 144 Hz and across a 3 s stall
gate st_replay_outputs node apps/st_replay_outputs_check.mjs   # ST Replay's Alt: INTERNAL feeds the stream ring every frame, EXTERNAL hands the whole sample over once (zg.samplePlay) and the worklet plays it as the fed bytes would sound
gate st_replay_outputs node apps/st_replay_outputs_check.mjs --break refill   # ...and a worklet that never refills the ring is caught
gate st_replay_filesel node apps/filesel_check.mjs   # GEM's ITEM SELECTOR as ST Replay opens it is TOS 1.02's: the 320-wide box keeps a full 8.3 Selection (DRUMLOOP.RAW) inside its frame, empty list rows show ________.___, files list as NAME    .EXT; three pinned pictures
gate_timed union_deltaforce node apps/union_deltaforce_headless.mjs "$SHOTS"   # DELTA FORCE: TEX loader depack, screen.js replayed pixel for pixel, the SNDH plays
gate_timed union_texcopier node apps/union_texcopier_headless.mjs "$SHOTS"   # COPIER TEX: loader depack, screen.js replay incl. Chrome's blends, Scoop plays
gate union_texcopier node apps/depack_align_check.mjs   # the depack loaders (TEX, Union: texcopier, tnt2, multifake, deltaforce) make no misaligned wide access while they load: each traps on the board (~210 cycles); the TEX loader's glyph copy made ~440 a frame until 2026-10-24
gate_timed union_tnt3 node apps/union_tnt3_headless.mjs "$SHOTS"   # TNT3: loader depack, then screen.js + three.js r49 replayed pixel for pixel
gate_timed union_l16 node apps/union_l16_headless.mjs "$SHOTS"   # L16: loader depack, both overscan planes = screen.js replay, SNDH plays, Esc
gate_timed union_tnt1 node apps/union_tnt1_headless.mjs "$SHOTS"   # TNT1 Starballs: TEX loader depack, screen.js replay (keys 5, 0), Pandora plays
gate_timed union_reps node apps/union_reps_headless.mjs "$SHOTS"   # REPS: loader depack, screen.js replayed with the joystick, the SNDH plays
gate_timed union_tnt2 node apps/union_tnt2_headless.mjs "$SHOTS"   # TNT2: TEX loader depack, screen.js + its keys replayed pixel for pixel, Cybernoid plays
gate_timed union_beatdis node apps/union_beatdis_headless.mjs "$SHOTS"   # TCB1: loader depack + question, both versions replayed pixel for pixel, both SNDHs play
gate_timed union_beatdis node apps/union_beatdis_headless.mjs --break keylock "$SHOTS"   # ...and a key lock that releases between repeats fails the hold check
gate union_beatdis node apps/union_beatdis_headless.mjs --break modes   # ...and a wrong native Beat Dis replay fails the 1/2 mode-switch check
gate union_beatdis node apps/union_beatdis_headless.mjs --break hq   # ...and mode 3 playing Beat Dis's bytes raw (unsigned, inverted) fails the sound check
gate_timed union_superscroller node apps/union_superscroller_headless.mjs "$SHOTS"   # TCB2: TEX loader depack, screen.js with Chrome's filtering replayed pixel for pixel, the SNDH plays
gate union_superscroller_music node apps/wow_native_check.mjs   # its tune (Wow Scroller, Timer A digi) natively = the 68000 bit for bit, modes 1/2 unbroken, mode 3 on PCM follows the YM path
gate union_superscroller_music node apps/wow_native_check.mjs --break   # ...and Beat Dis's handler on Wow's bytes (mutant 4) is caught
gate union_textracker_music node apps/irq_native_check.mjs --song union/thalion_forever.sndh --status 8 --seconds 60   # its tune's 4-voice mixer interrupt natively = the 68000 bit for bit, modes 1/2 unbroken
gate union_textracker_music node apps/irq_native_check.mjs --song union/thalion_forever.sndh --status 8 --seconds 20 --break   # ...and the steps play patches frozen at arming (mutant 5) are caught
gate big_demo_music node apps/irq_native_check.mjs --song digital/Ace_2.sndh --status 16 --seconds 40   # the digital screen's PLAY (Mad Max's sequencer) and 3-voice mixer interrupt natively = the 68000 bit for bit, modes 1/2 unbroken
gate big_demo_music node apps/irq_native_check.mjs --song digital/Ace_2.sndh --status 16 --seconds 20 --break   # ...and the steps play patches frozen at arming (mutant 5) are caught
gate big_demo_music node apps/irq_native_check.mjs --song digital/Ace_2.sndh --status 16 --seconds 20 --break --mutant 12   # ...and the native PLAY's note lengths a frame short (mutant 12) are caught
gate snyd_90_music node apps/irq_native_check.mjs --song snyd90_f6.sndh --status 12 --seconds 40   # part 6's Timer C 3-voice mixer interrupt natively = the 68000 bit for bit, modes 1/2 unbroken
gate snyd_90_music node apps/irq_native_check.mjs --song snyd90_f6.sndh --status 12 --seconds 20 --break   # ...and the steps play patches frozen at arming (mutant 5) are caught
gate tcb_spreadpoint_music node apps/irq_native_check.mjs --song tcb_spreadpoint.sndh --status 13 --seconds 40   # its three volume streams' interrupt natively = the 68000 bit for bit, modes 1/2 unbroken
gate tcb_spreadpoint_music node apps/irq_native_check.mjs --song tcb_spreadpoint.sndh --status 13 --seconds 20 --break --mutant 6   # ...and registers 9 and 10 swapped (mutant 6) are caught
gate dbug_music node apps/irq_native_check.mjs --song crystallized.sndh --status 14 --seconds 40   # maxYMiser's drum interrupts (from 12.8 s) natively = the 68000 bit for bit, modes 1/2 unbroken
gate dbug_music node apps/irq_native_check.mjs --song crystallized.sndh --status 14 --seconds 20 --break --mutant 10   # ...and the 8-bit drum routine without its addi.b (mutant 10) is caught
gate north_south_music node apps/irq_native_check.mjs --song north_south_digi.sndh --tune 33 --status 15 --seconds 8   # an effect's interrupt natively = the 68000 bit for bit (all 47 in test_sndh_irq.py)
gate north_south_music node apps/irq_native_check.mjs --song north_south_digi.sndh --tune 33 --status 15 --seconds 8 --break --mutant 11   # ...and the pointer stored past the 0 byte (mutant 11) is caught
gate rick_dangerous_music node apps/irq_native_check.mjs --song rick_dangerous.sndh --tune 9 --status 15 --seconds 8   # an effect's interrupt natively = the 68000 bit for bit (all 87 in test_sndh_irq.py)
gate rick_dangerous_music node apps/irq_native_check.mjs --song rick_dangerous.sndh --tune 9 --status 15 --seconds 8 --break --mutant 11   # ...and the pointer stored past the 0 byte (mutant 11) is caught
gate swedish_newyear_music node apps/irq_native_check.mjs --song swedish_newyear_tcb_digi.sndh --status 10 --seconds 40   # TCB #1's one-byte digi interrupt natively = the 68000 bit for bit, modes 1/2 unbroken
gate swedish_newyear_music node apps/irq_native_check.mjs --song swedish_newyear_tcb_digi.sndh --status 10 --seconds 20 --break --mutant 8   # ...and the pointer kept in Zig past play's rewind (mutant 8) is caught
gate swedish_newyear_music node apps/irq_native_check.mjs --song Swedish_New_Year_Demo_Sync.sndh --status 11 --seconds 40   # SYNC's self-modifying 4-voice mixer interrupt natively = the 68000 bit for bit, modes 1/2 unbroken
gate swedish_newyear_music node apps/irq_native_check.mjs --song Swedish_New_Year_Demo_Sync.sndh --status 11 --seconds 20 --break   # ...and the ends play patches frozen at arming (mutant 5) are caught
gate automation442 node apps/automation442_headless.mjs "$SHOTS/automation442"   # AUTOMATION 442: the panned overscan scroll plane through one bgcount cycle
gate_timed big_demo node apps/big_demo_headless.mjs   # TEX B.I.G. DEMO: wait screen hands over at frame 201, TEX's own 118 rows ripped from RAM, cursor clamps [2,115], all 45 named SNDH present, bands cycle
gate_timed big_demo node apps/big_demo_headless.mjs --break nav   # ...and a list that never moves fails the clamp checks
gate_timed big_demo node apps/big_demo_headless.mjs --break music   # ...and the wrong subtune fails the song check
gate_timed big_demo node apps/big_demo_headless.mjs --break noop   # ...and an entry with no SNDH that asks for one fails (no silent substitution)
gate_timed big_demo node apps/big_demo_headless.mjs --break songs   # ...and a named SNDH missing from docs/music/big/ fails (it would play silence)
gate_timed digital_solution node apps/digital_solution_headless.mjs   # THE DIGITAL SOLUTION (a screen OF big_demo): list row 115 opens it, every px outside the scroller band = screen.raw, the band is the SHARED scrolltext in lockstep, the text cycles on texbg, opening it plays the DIGI Ace 2, keys 1-6 -> 6 subtunes
gate_timed digital_solution node apps/digital_solution_headless.mjs --break pixels   # ...and one changed pixel of the reference fails the picture check
gate_timed digital_solution node apps/digital_solution_headless.mjs --break tune   # ...and PHANTOMS 2 on the wrong subtune fails the key mapping
gate_timed digital_solution node apps/digital_solution_headless.mjs --break songs   # ...and a named SNDH missing from docs/music/digital/ fails (it would play silence)
gate_timed digital_solution node apps/digital_solution_headless.mjs --break exit   # ...and a key that is not Space failing to leave is caught
gate_timed digital_solution node apps/digital_solution_headless.mjs --break route   # ...and Return one row short of the Digital Department not opening it is caught
gate_timed digital_solution node apps/digital_solution_headless.mjs --break drift   # ...and one frame of scrolltext drift is caught (so a restart would be too)
gate_timed digital_solution node apps/digital_solution_headless.mjs --break cycle   # ...and the text one cycle step out of phase is caught
gate stniccc node apps/stniccc_headless.mjs "$SHOTS/stniccc"   # STNICCC 2000 (Oxygene): the frame-replay flight, small -> rewind -> fullscreen
gate stniccc node apps/stniccc_pins.mjs   # every frame (3300, 60 Hz host: small, rewind, message, zoom, fullscreen, disk streaming) = the cart at c77c6c2e, before the CPU spans, physical RGB hashed
gate stniccc node apps/stniccc_pins.mjs --break   # ...and one altered pixel is caught
gate cuddly_starwars node apps/cuddly_starwars_headless.mjs "$SHOTS/cuddly_starwars"   # CUDDLY STAR WARS: the harness existed but no gate ran it; fails on a refused zg.mem allocation
gate ulm_spoon_distorter node apps/ulm_spoon_distorter_headless.mjs "$SHOTS/ulm_spoon_distorter"   # ULM SPOON DISTORTER: the harness existed but no gate ran it; fails on a refused zg.mem allocation
gate tlb_spoon node apps/tlb_spoon_headless.mjs "$SHOTS/tlb_spoon"   # TLB TWIDDLE: the sine intro, then starballs + logo + the rotating-letter scroller; pins the composed picture at 6 frames
gate tlb_spoon node apps/tlb_spoon_headless.mjs "$SHOTS/tlb_spoon_break" --break   # ...and one extra frame is caught by the pin
gate perf_audit node apps/perf_audit_test.mjs   # the KESTREL perf suite: each bad pattern planted in a tiny cart is found statically and (dynamic ones) hot in a real run, the byte-loop clear first at ~0.5 Mc, the f64 loop first; each clean twin is not; the counts are deterministic
gate perf_audit node apps/perf_audit_test.mjs --break bytefill   # ...and the byte-loop clear swapped for its memset twin fails the byte_fill checks
gate perf_audit node apps/perf_audit_test.mjs --break f64        # ...and the f64 loop swapped for integer maths fails the f64 checks
gate perf_audit node apps/perf_audit_test.mjs --break redundant  # ...and a static page redrawn every frame swapped for a changing one fails redundant_store
gate perf_audit node apps/perf_audit_test.mjs --break clear      # ...and clear-then-redraw-the-same swapped for drawing only what changes fails clear_then_redraw
gate perf_audit node apps/perf_audit_test.mjs --break static     # ...and a plane drawn once swapped for one that changes fails static_plane
gate perf_audit node apps/perf_audit_test.mjs --break lines      # ...and one changed row a frame swapped for all rows fails the lines_changed count
gate perf_audit node apps/perf_audit_test.mjs --break tiny       # ...and twenty 4x4 blits swapped for one big one fails tiny_blits
gate perf_audit node apps/perf_audit_test.mjs --break scroll     # ...and a band shifted by the CPU swapped for a band redrawn with new content fails scroll_band
gate perf_audit node apps/perf_audit_test.mjs --break div        # ...and a divide by a fixed value swapped for a multiply fails div_loop
gate perf_audit node apps/perf_audit_test.mjs --break recompute  # ...and a product of loop-invariant values swapped for a varying one fails recompute
gate perf_audit node apps/perf_audit_test.mjs --break cache      # ...and a 256-byte-stride walk swapped for a sequential one fails cache_hostile
gate perf_audit node apps/perf_audit_test.mjs --break call       # ...and a per-iteration call swapped for the inline add fails call_in_loop
gate perf_audit node apps/perf_audit_test.mjs --break i64fit     # ...and i64 maths that always fits swapped for maths that never does fails i64_fits_i32
gate perf_audit node apps/perf_audit_test.mjs --break branch     # ...and a frame-constant test swapped for an alternating one fails invariant_branch
gate perf_audit node apps/perf_audit_test.mjs --break misaligned # ...and i32 loads from an odd address swapped for aligned ones fails misaligned (each traps on ZIGGY)
gate perf_audit node apps/perf_audit_test.mjs --break budget     # ...and the plane left disabled fails frame_cost --budget's 280-pass FRESCO check
gate perf_audit node apps/perf_audit_test.mjs --break mcopy      # ...and a memcpy whose source is aligned with its destination fails misaligned_memcpy (the board's copy_fwd byte-loops a misaligned source)
gate perf_audit node apps/perf_audit_test.mjs --break inplane    # ...and a copy from cart RAM in place of one from the plane's own rows fails inplane_copy (ordered on the board)
gate perf_report sh tools/perf_audit.sh --report --jobs 2   # REPORT, never fails the gate: the shelf ranked by ESTIMATED Mc/frame on ZIGGY with each cart's first hot finding (JSON: zig-out/perf_audit.json)
run_gates
# A green gate's shots go: each run leaves ~240 MB, and a busy night of gates
# filled / (2026-10-24: pushes died with ENOSPC). A red gate never reaches here
# (set -e), so its shots stay for the post-mortem. KEEP_SHOTS=1 keeps them.
if [ -n "${KEEP_SHOTS:-}" ]; then
    echo "shots in $SHOTS"
else
    rm -rf "$SHOTS"
fi

# Green stamp: only a FULL gate, only if the tree was clean at the start and is
# still clean now (a rebuilt docs/ file that differs from HEAD makes it dirty).
if [ -n "$STAMPABLE" ]; then
    sh tools/gate_stamp.sh write || echo "gate green, but the tree is dirty now: NOT stamped"
fi
