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

zig build -Drelease=true -Dwasm

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
node apps/beam_check.mjs      # BEAM (1.6.0): mid-line colour-0 cells across the whole line, persistence, no drops
node apps/beam_check.mjs --break   # ...and writes 4 px apart (faster than a move.w) are caught and counted as drops

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
    libs/zig/players/mod_format_test.zig
    libs/zig/players/xm_format_test.zig
    libs/zig/players/xm_instr_test.zig
    libs/zig/players/xm_mix_test.zig
    libs/zig/players/xm_ring_test.zig
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
    libs/zig/effects/sprite_draw_test.zig
    libs/zig/effects/scrolltext2_test.zig
    libs/zig/effects/parallax_test.zig
    libs/zig/effects/tilemap_test.zig
    libs/zig/effects/text_plot_test.zig
    libs/zig/effects/glyph_line_test.zig
    libs/zig/effects/copper_test.zig
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
    machine/audio/ym_test.zig
    machine/audio/ym_env_test.zig
    machine/audio/ym_dac_test.zig
    machine/arena_test.zig
    libs/zig/mem_test.zig
    libs/zig/libm_f32_test.zig
    libs/zig/sndh_call_test.zig
    libs/zig/shapes_test.zig
    libs/zig/wireframe_test.zig
    libs/zig/tvnoise/tvnoise.zig
    apps/zig/scene_tests.zig
    rom/gem/desktop/namefield.zig
    rom/gem/desktop/stamp.zig
    rom/gem/desktop/dirmodel_test.zig
    rom/gem/desktop/deskinf.zig
    rom/gem/gui/grid.zig
    apps/zig/scenes/stniccc/stream.zig
    apps/zig/scenes/stniccc/polyfill_test.zig
    apps/zig/scenes/stniccc/span.zig
    apps/zig/scenes/stniccc/player_test.zig
    apps/zig/scenes/union/wab_table_test.zig
    apps/zig/scenes/ancool/stars_test.zig
    apps/zig/scenes/union/dragonball_squash.zig
    apps/zig/scenes/blitter_demo/wobble.zig
    apps/zig/scenes/blitter_demo/soft.zig
    apps/zig/scenes/leonard_spirit/ball_test.zig
    apps/zig/scenes/gen4_3615/fate_test.zig
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
python3 tools/gen_docs.py --check   # ZIGMACHINE_GUIDE.html regenerated from MUSIC.md, FLOPPY_DISK.md and the sources
python3 tools/gen_tutorial.py --check   # TUTORIAL.html regenerated from TUTORIAL.md
python3 -m unittest discover -q -s tools/tests -t tools   # the doc generators' own tests
node apps/disk_check.mjs
node apps/upload_check.mjs    # an uploaded disk mounts exactly like a URL one; bad uploads refused
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
gate gem node apps/gem_headless.mjs "$SHOTS"
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
gate sysinfo node apps/sysinfo_check.mjs "$SHOTS/sysinfo"   # SYSINFO: every page's text is on the glass glyph for glyph; page 1's memory lines are hwRamFree/Base/Top/Size, the ROM window and hwVideoBase as the machine answers; plane 0's base is its register's; the disk lines are the .zmd descriptor's; player + YM lines follow the host live; idle frames draw nothing, a refresh only the changed span; no host clock = every speed test once, n/a; a clock = a time each, 6 ratios to the ST, f32 to the integer mul-add; Space opens the menu, a click on F4 shows the disk page whole; Q = request 4; page 3 lists the disk's JINKS.SND / GAUNTLET.SAP / SAMPLE.RAW, P reads each through the drive (the bytes handed over = the FAT file's), an SNDH / SAP goes out as requestSongBytes and the loader's postSfx + the audio module play it in mode 4 / 5, the PCM is samplePlay at 12500 Hz; S stops each
gate sysinfo node apps/sysinfo_check.mjs --break free   # ...and FREE expected 4 KB off hwRamFree() fails
gate sysinfo node apps/sysinfo_check.mjs --break sound   # ...and a drive serving JINKS.SND with one byte changed fails the bytes check
gate sysinfo_gem node apps/sysinfo_gem_check.mjs   # SYSINFO as a GEM program: its disk is a DATA disk (with the No virus $1234 boot sector, which asks for request 2 and names no cart, so GEM follows) whose one program BOOT.WSM depacks to demo-sysinfo.wasm; GEM's floppy window runs it on a double-click (request 3), Q brings GEM back (request 4), 3 round trips (> MAX_GUI) and the menu still opens; page 4 reads DATA DISK + BOOT.WSM; the last Q leaves the desktop as it was
gate sysinfo_gem node apps/sysinfo_gem_check.mjs --break bootable   # ...and a disk held to the bootable kind fails
gate pure_hbl uv run --project fpga python fpga/tools/video_order_pure.py --break --frames 600 replicants automation442 union_intro@3000   # REG_FB_HBL_PURE (1.8.0): every cart whose pure HBL handler plane the board composites line by line beside another plane, replayed in the board's order (handler before its own pass, RES_FLICKER as its own handler left it) through the RTL compositor, equals the machine; a cart that no longer groups such a plane fails (nothing tested); --break: the synthetic overscan frames grouped without the firmware's RES_FLICKER store must be caught
gate_timed c_music timeout 180 node apps/c_music_check.mjs   # a C cart's song request reaches the sealed YM (timeout: it once hung a gate)
gate union_demo_music node apps/union_demo_music_check.mjs   # the Union Demo menu's and cracktro's SNDH tunes are requested by name and play
gate union_demo_music node apps/union_demo_music_check.mjs --fail-proof   # ...and a wrong tune name fails that check
gate union_intro_music node apps/union_intro_music_check.mjs   # the cracktro's music starts with the TRSI logo, and main doesn't restart it
gate union_intro_music node apps/union_intro_music_check.mjs --fail-proof   # ...and a wrong tune name fails that check
gate union_intro_music node apps/union_tracks_play_check.mjs   # keys 1-6: every cracktro tune PLAYS after the one before (a YM dump after an SNDH once left the SNDH running over it: keys 3+ "crashed")
gate union_intro_music node apps/audio_switch_check.mjs   # a SAP or a YM dump loaded over a playing SNDH takes over (mode, sound, no runaway 68000), then an SNDH plays again
gate union_demo_doors node apps/union_demo_doors_check.mjs   # the hub's doors launch the Union screens by tag (they are hub-only)
gate union_intro_main node apps/composite_hash.mjs docs/demo-union_intro.wasm 12000 12 --disk docs/demo-union_intro.zmd --expect 457d60d279a2e769cbb62998d3e843ca3fc579eabff37ed3a41719505e5df559   # UNION cracktro into its MAIN screen: 1000 composited pictures over 12000 frames (the parts, then ~11000 frames of the main screen: all 8 credits pages, sky raster, balls, scrolltext) = the three-plane build's (cecc6dd0), now two planes (balls on P0, scrolltext under P1's palette split)
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
gate scrolllab node apps/scrolllab_headless.mjs "$SHOTS/scrolllab"   # SCROLLTEXT LAB: the ten distortions over one text (codef_fx siny/sinx/zoomy, a 2D path with a loop, screen 345's table) all render and all differ from FLAT, and Escape leaves
gate_timed polkadots node apps/polkadots_headless.mjs "$SHOTS/polkadots"   # POLKA DOTS: the flat-shaded torus reaches the dot grid (100-700 cells stamped, never the whole grid), the light still makes big dots as well as small ones, all FOUR render modes draw a different picture at the op count the cart itself reports, and every one of them holds 60 fps; this fixed-point cart's dots match the f32 cart's (under 1% of lit cells, never more than one dot size apart); F switches the maths live: pressed before frame 1 the cart IS the f32 cart pixel for pixel, twice it is itself again, mid-turn it keeps the pose
gate_timed polkadots node apps/polkadots_headless.mjs "$SHOTS/polkadots_break" --break fixed   # ...and a fixed-point cart a frame off the f32 one (the dots the two number systems draw no longer agree) is caught
gate_timed polkadots node apps/polkadots_headless.mjs "$SHOTS/polkadots_break" --break fkey   # ...and F never switching the maths (the default cart pressed F before frame 1 is NOT then the f32 cart, every pixel) is caught
gate_timed polkadots_f32 node apps/polkadots_headless.mjs "$SHOTS/polkadots_f32" --cart docs/demo-polkadots_f32.wasm   # POLKA DOTS F32 (cart 89, the CODEF algorithm in f32 for the FPU test): every check above, on the f32 build
gate lockbuster2 node apps/lockbuster2_headless.mjs "$SHOTS/lockbuster2"   # LOCKBUSTER 2 (cart 90): at the go-lockbuster2 checkpoints (title slides + all six engines) the cart's engine ring is the original screen memory byte for byte; the drawn frame, border raster included, is the Go shader's pixel for pixel, F5's alternate bank included; F1/F4 toggle what message-3 advertises; the cycle wraps with phase sane at tick 22000; Rollout.sndh #1 is requested; Escape and Space both leave; no zg.mem allocation refused
gate_timed raytrace node apps/raytrace_headless.mjs "$SHOTS/raytrace"   # RAYTRACE (Q16.16 + f32 carts, the FPGA CPU benchmark), each run with no clock, a fake one and the real one (env.hostMicros): both finish at exactly frame 110 with no clock (fixed work, 8x8-block preview at frame 2) and 220 with the fake one (timed work), the fake-clock rate reads exactly 32000 px/s and the real one is measured and printed, Fire restarts a run, both show sky, both floor tones, all five spheres, a floor shadow and a chrome sphere mirroring floor and sky, the fixed-point picture matches the f32 one, the ray count is plausible, each frame fits 60 fps, and the finished picture's SHA-256 is pinned per cart and identical under all three clocks
gate_timed raytrace node apps/raytrace_headless.mjs --break pixel "$SHOTS/raytrace"   # ...and one wrong pixel fails the pinned fingerprint
gate_timed raytrace node apps/raytrace_headless.mjs --break clock "$SHOTS/raytrace"   # ...and a clock that never moves (a frame that never ends its budget) fails the frame count, the rate and the 60 fps budget
gate elite_cfsr node apps/elite_cfsr_headless.mjs "$SHOTS/elite_cfsr"   # ELITE CHALLENGE FOOT: both colour-0 bars are REAL rasters read off the LEFT BORDER (BEAM_RASTERS1/2 exact, and the closing one only exists because the bottom border is open), every one of the 156 band lines carries its own RASTERS group word, and all ten copies of the 16-row XOR-filled scroller pattern agree
gate rno_sodium node apps/rno_sodium_headless.mjs "$SHOTS/rno_sodium"   # RNO SODIUM: at the eight counter values of the Hatari RAM snapshots (wobble trail, curtain, both text pages, prism and distorter back buffers) the frame on screen is the original's, pixel for pixel; the parts change on a 50 Hz counter even on a 60 Hz host; gritty.sndh restarts when the intro loops
gate rno_natrium node apps/rno_natrium_headless.mjs "$SHOTS/rno_natrium"   # RNO NATRIUM: at six timeline counters the displayed frame is Hatari's RAM snapshot through the palette, byte for byte; part 1's two-tone dot tunnel and logo band; $1E00 starts the intro over identically
gate dhs_0pxl0reg node apps/dhs_0pxl0reg_headless.mjs "$SHOTS/dhs_0pxl0reg"   # DHS (n)0 PIXELS (n)0 REGRETS: zero bitplanes, every pixel a BEAM colour-0 write; at every 50th frame across all 17 parts the whole 400x280 physical frame, borders included, is the reference model's byte for byte; REG_BEAM_DROPPED stays 0 over the whole 22,000-frame run; no plane is ever enabled; Fake It at 159, stopped at 7759, AY Tunage at 8173
gate dhs_0pxl0reg node apps/dhs_0pxl0reg_headless.mjs --break skip "$SHOTS/dhs_0pxl0reg"   # ...and one skipped VBL fails the frame checks
gate dhs_0pxl0reg node apps/dhs_0pxl0reg_headless.mjs --break drop "$SHOTS/dhs_0pxl0reg"   # ...and a write 4 px after another (faster than a move.w) is counted as a drop
gate trsi_transarctica node apps/trsi_transarctica_headless.mjs "$SHOTS/trsi_transarctica"   # TRSI TRANSARCTICA (Falcon): at 17 program VBLs (intro flash, logo fade and slide, all six pages, the 3 RAM-snapshot and 5 screenshot frames) the 320x240 display, top/bottom borders open, is the RE model's pixel for pixel; the open bands are colour 0; the pages loop after 4210 VBLs; the MOD is requested at BPM 123 on VBL 1 and plays; audioModPlayBpm(125) is audioModPlay byte for byte
gate trsi_transarctica node apps/trsi_transarctica_headless.mjs --break skip "$SHOTS/trsi_transarctica"   # ...and one skipped VBL fails the frame checks
gate north_south node apps/north_south_headless.mjs   # NORTH & SOUTH battle (playable): the 13 reference scripts' inputs replayed through the cart's battle, and after EVERY frame (5104) the 5776-byte battle RAM, the screen flipped to, the sound sequences and the frame's VBL length are the reference model's (itself byte-exact against the original 68000 battle), the winners too; the host path: front page, Space starts, battle frames on a 50 Hz VBL clock at a 60 Hz host, the plane shows the battle screen, '/' requests the unit-switch sound, F10 leaves; the digi SNDH plays a sequence's level bytes at its Timer A rate
gate north_south node apps/north_south_headless.mjs --break   # ...and one poked RAM byte (the RNG) fails the replay
gate joust node apps/joust_headless.mjs "$SHOTS/joust"   # JOUST (the game): two recorded games (1P TAS 18,293 frames to wave 9, 2P TAS 7,015 frames) replayed from power-on in lockstep with the harness's title key and joystick bytes: every frame takes the real program's VBL count and starts its Dosound scripts, every 25th frame start the game RAM + screen hash and the CPU cycle count are the real program's; live: the title and the game on the plane pixel for pixel, '1' starts, P/any key/R/Escape, 50 Hz time on a 60 Hz host; joust_sfx.sndh leaves the YM where TOS's Dosound leaves it for all 16 scripts
gate joust node apps/joust_headless.mjs --break joy "$SHOTS/joust"   # ...and one flipped fire bit fails the replay checks
gate kickoff2 node apps/kickoff2_headless.mjs "$SHOTS/kickoff2"   # KICK OFF 2 (the friendly, playable): the title's plane is the ripped title art with FIRE starting the kickoff; ko2TestTick drives the SAME MatchP from a fixed seed for 3 simulated minutes: the ball leaves the centre circle, stays on-pitch or ends a legal restart (throw-in/corner/goal-kick/goal), scores>=0, the clock advances only while playing; possession keeps the ball within a player reach; Escape at the title and the match both, leave; no zg.mem allocation refused
gate grodan_kvack node apps/grodan_kvack_headless.mjs "$SHOTS/grodan_kvack"   # GRODAN & KVACK KVACK (cart 92): every frame to 20 s and at each scroll reset after it, the composited 320x200 window is the port's own model pixel for pixel (the six layers AND the copper's three raster entries AND the eight palette words together); the tick count, the four scrolls and the Go's animation counters equal the model's every frame; the per-line rasters really repaint palette entries 4/5/6 (more colours than a static palette can); the border bands stay black; no zg.mem allocation refused; Escape leaves
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
gate gnomes node apps/gnomes_headless.mjs "$SHOTS/gnomes"   # THE GNOMES GROUP "BB25" Buxton Bytes 2025 cracktro (cart 104): every frame the rainbow roll, the big band's text index/scroll and the TTY's pointer/column/row/pause equal the harness's model; the composited 800x280 raster equals the model pixel for pixel every frame to 900 (two TTY cycles with their wipes) then checkpoints to 4000 -- SpongeBob, boxes, rimmed logo, 4x band, cyan message -- with the three copper slots (rainbow / T2 brick / T1 logo ramp) read back per physical line in all four open borders; a border column carries 40+ colours, no two neighbours equal; custodian.sndh #1 requested once, F1-F6 request #1..#6; Escape/Back leave; no zg.mem allocation refused
gate gnomes node apps/gnomes_headless.mjs --break raster "$SHOTS/gnomes_break"   # ...and the rainbow one line off is caught
gate gnomes node apps/gnomes_headless.mjs --break state "$SHOTS/gnomes_break"   # ...and one wrong TTY word is caught
gate gnomes node apps/gnomes_headless.mjs --break pixels "$SHOTS/gnomes_break"   # ...and one wrong pixel is caught
gate gnomes node apps/gnomes_headless.mjs --break music "$SHOTS/gnomes_break"   # ...and the wrong tune name is caught
gate hmdfac node apps/hmdfac_headless.mjs "$SHOTS/hmdfac"   # HMD "HMDFAC" Team Factory tribute (cart 105, Falcon): every frame the wheel counters, camera walk ($1356 -> $79e, hold, -> $1b9e), queue pair and index equal the harness's model; the composited 800x280 raster equals the model pixel for pixel every frame to 1300 then checkpoints past the text's end: 199 dark frames under sixteen $0011, the 777/EEE/666/DDD/555/CCC flash, all 498 cube frames (the frustum in the model's own exact 68k word maths over a FULL art re-blit, pinning the cart's dirty-row restore) and phase 4's wave scroller over band B (over a FULL clear, pinning the cart's erase-the-boxes); hmd_cracoucass.sndh #1 requested once; Space pops colour 0 to $711 and back; Escape/Back leave; no zg.mem allocation refused
gate hmdfac node apps/hmdfac_headless.mjs --break state "$SHOTS/hmdfac_break"   # ...and one wrong camera word is caught
gate hmdfac node apps/hmdfac_headless.mjs --break pixels "$SHOTS/hmdfac_break"   # ...and one wrong cube pixel is caught
gate hmdfac node apps/hmdfac_headless.mjs --break music "$SHOTS/hmdfac_break"   # ...and the wrong tune name is caught
gate anima node apps/anima_headless.mjs "$SHOTS/anima"   # ANIMA (cart 107, a new ZigMachine multipart): the music sequence (cuddly_reset.sndh, silence at the gag's freeze, breath_2000.sndh at the tunnel); DARK every line closed, OPEN the sides opening from line 140, OLDSCHOOL the REAL raster in both side borders, the GAG's mistimed flicker filling the borders with noise, NEWSCHOOL every line open and covered; a composed frame of every part pinned by SHA-256; <= 200 CHISEL ops a frame; est. board cost of every part <= 1.75 Mc (apps/frame_cost.mjs)
gate anima node apps/anima_headless.mjs --no-cost --break hash "$SHOTS/anima_break"   # ...and a one-bit picture change is caught
gate anima node apps/anima_headless.mjs --no-cost --break border "$SHOTS/anima_break"   # ...and a line open in DARK is caught
gate anima node apps/anima_headless.mjs --no-cost --break raster "$SHOTS/anima_break"   # ...and a wrong raster colour on one line is caught
gate anima node apps/anima_headless.mjs --no-cost --break music "$SHOTS/anima_break"   # ...and a wrong tune in the sequence is caught
gate anima node apps/anima_headless.mjs --no-cost --break noise "$SHOTS/anima_break"   # ...and a gag without noise is caught
gate anima node apps/anima_headless.mjs --break cost "$SHOTS/anima_break"   # ...and a part over the cost ceiling is caught
gate leonard_spirit node apps/leonard_spirit_headless.mjs   # LEONARD'S SPIRIT (cart 108): 8 x 312 = 2,496 generated-code balls a frame on ONE plane; the composed plane shows the merged palette (every 500 frames); every frame of a whole scrolltext lap (3,148 frames, > 8 path periods) plane 0 = the model byte for byte (back.raw, the eight snakes in painter's order, the 6x6 ink at y 194); over 2,000 distinct ball positions in frame 0; only plane 0 enabled; sos.sndh requested
gate leonard_spirit node apps/leonard_spirit_headless.mjs --break pixels   # ...and one wrong ball pixel is caught
gate leonard_spirit node apps/leonard_spirit_headless.mjs --break count   # ...and a 2,497th ball is caught
gate leonard_spirit node apps/leonard_spirit_headless.mjs --break music   # ...and the wrong tune name is caught
gate leonard_spirit node apps/leonard_spirit_headless.mjs --break palette   # ...and two swapped ball shades in the merged palette are caught
gate hippel_musicdisk node apps/hippel_musicdisk_headless.mjs   # JOCHEN HIPPEL MUSIC DEMO (cart 109, Amiga musicdisk): planes 0+1 as composed = a model of the original's copper list on all 400x280 for 600 frames (two COLOR00 bars, top one rotation behind; the 32-column COLOR01 rainbow scrolled a line a 50 Hz frame, 1 px lead; the $888 dual-playfield shadow); 5 steps in 6 frames; rings_of_medusa.hip song 1 at start, keys a..j/A..J the original's module + song, every .hip on the one RoM replay with enough songs; Escape leaves
gate hippel_musicdisk node apps/hippel_musicdisk_headless.mjs --break pixels   # ...and one wrong bar pixel is caught
gate hippel_musicdisk node apps/hippel_musicdisk_headless.mjs --break lead   # ...and copper columns without the 1-px lead are caught
gate hippel_musicdisk node apps/hippel_musicdisk_headless.mjs --break music   # ...and a key asking for the wrong song is caught
gate hippel_musicdisk node apps/hippel_musicdisk_headless.mjs --break pacing   # ...and a 60 Hz phase (not the original's 50) is caught
gate joust node apps/joust_headless.mjs --break clock "$SHOTS/joust"   # ...and 4 extra CPU cycles once fail them
gate rick_dangerous node apps/rick_dangerous_headless.mjs "$SHOTS/rick_dangerous"   # RICK DANGEROUS (the game): 18 recorded runs (10,890 frames: the level walks, deaths, GAME OVER, the name entries, the menus, the bots through all 4 levels) replayed in lockstep with the original's ACIA / Timer A bytes: every frame takes the original's VBLs and leaves its RAM + both screens + palette with the reference model's CRC, makes its play_sound requests (dropped or not) and the SNDH load / zg.sndhCall requests they imply, in order; live: title + tune, FIRE -> select -> intro -> level 1, the plane is the ST screen, 50 Hz time on a 60 Hz host, P, Escape; rick_dangerous.sndh's own driver RAM = the cart's for all 87 subtunes, and with later requests sndhCall-ed on the RUNNING driver (every id, the paired shot, dynamite x2)
gate rick_dangerous node apps/rick_dangerous_headless.mjs --break joy "$SHOTS/rick_dangerous"   # ...and one wrong stick byte fails the state CRC
gate rick_dangerous node apps/rick_dangerous_headless.mjs --break vbl "$SHOTS/rick_dangerous"   # ...and one VBL interrupt too many fails the VBL count
gate rick_dangerous node apps/rick_dangerous_headless.mjs --break sound "$SHOTS/rick_dangerous"   # ...and the drop rule's input flipped fails the play_sound check
gate rick_dangerous node apps/rick_dangerous_headless.mjs --break alloc "$SHOTS/rick_dangerous"   # ...and a refused zg.mem allocation fails the run
gate rick_dangerous node apps/rick_dangerous_headless.mjs --break sndh "$SHOTS/rick_dangerous"   # ...and the SNDH on the wrong subtune fails the driver RAM check
gate rick_dangerous node apps/rick_dangerous_headless.mjs --break reload "$SHOTS/rick_dangerous"   # ...and a later request forwarded as a reload (not an sndhCall) fails the resident check
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
gate fallen_angels node apps/fallen_angels_headless.mjs "$SHOTS"   # per-plane rasters on all 200 lines
gate tex_loader_fx node apps/tex_loader_fx_headless.mjs "$SHOTS/tex_loader_fx"   # fx = tex_loader on a real asset, bytes checked
gate_timed tex node apps/tex_headless.mjs "$SHOTS"             # the eleven sprites on screen.js's chain
gate equinox node apps/equinox_headless.mjs "$SHOTS"   # the dragons morph egg -> dragon -> egg
gate tex_neoshow node apps/tex_neoshow_headless.mjs "$SHOTS/tex_neoshow"   # TEX NEO SHOW: the scroller band is a REAL per-line raster (copper), full plane width
gate tex_neoshow_music node apps/monty_native_check.mjs   # its tune (Monty, Timer D digidrums) played natively = the 68000, bit for bit over 50 s, modes 1/2 unbroken
gate tex_neoshow_music node apps/monty_native_check.mjs --break   # ...and volume C written over the drums (mutant 3) is caught
gate mpp_truecolor node apps/mpp_truecolor_headless.mjs "$SHOTS"   # per-line palettes: colours on screen = captions
gate_timed union_textracker node apps/union_textracker_headless.mjs "$SHOTS"   # TEX loader depack, then screen.js replayed pixel for pixel
gate_timed union_demo_intro node apps/union_demo_intro_headless.mjs "$SHOTS"   # TEX loader depack, then every pixel on the screen.js replay
gate_timed stream_pacing node apps/stream_pacing_check.mjs   # streamed audio tracks wall time at 18 fps, 144 Hz and across a 3 s stall
gate st_replay_outputs node apps/st_replay_outputs_check.mjs   # ST Replay's Alt: INTERNAL feeds the stream ring every frame, EXTERNAL hands the whole sample over once (zg.samplePlay) and the worklet plays it as the fed bytes would sound
gate st_replay_outputs node apps/st_replay_outputs_check.mjs --break refill   # ...and a worklet that never refills the ring is caught
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
gate tlb_spoon node apps/tlb_spoon_headless.mjs "$SHOTS/tlb_spoon"   # TLB TWIDDLE: the sine intro, then starballs + logo + the rotating-letter scroller
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
