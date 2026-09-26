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

# --- selective gate: --only <tags> / --changed -----------------------------
# The DEFAULT is the full gate, and the pre-push hook must keep using it. These
# flags are an inner-loop convenience ONLY.
#
# Why they are conservative: the failures this gate catches are silent and
# CROSS-CUTTING. A change under libs/, rom/, machine/, docs/*.js or build.zig
# can break a screen whose own files never changed, so --changed refuses to
# narrow anything unless the diff touches scene/asset files and nothing else.
# The cheap cross-cutting checks (windows, ABI, disks) always run regardless.
ONLY=""
FAST=""
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
        # Everything changed ON THIS BRANCH, not just since HEAD: diffing HEAD alone
        # means the first commit empties the set and silently widens back to the full
        # gate, exactly while you are iterating in small commits.
        _base=$(git merge-base HEAD origin/main 2>/dev/null || echo HEAD)
        _touched=$(git diff --name-only "$_base" 2>/dev/null; \
                   git ls-files -o --exclude-standard 2>/dev/null)
        # anything outside a scene or its assets forces the full gate
        _wide=$(printf '%s\n' "$_touched" | grep -v '^$' \
                | grep -vE '^apps/zig/(scenes|assets/screens)/' \
                | grep -vE '^docs/(demo-[^/]+\.(wasm|zmd)|music/)' || true)
        if [ -n "$_wide" ]; then
            echo "--changed: full gate (these are outside scenes/assets):"
            printf '%s\n' "$_wide" | sed 's/^/    /'
        else
            ONLY=$(printf '%s\n' "$_touched" \
                   | sed -nE 's#^apps/zig/(scenes|assets/screens)/([^/.]+).*#\2#p' \
                   | sort -u | tr '\n' ' ')
            [ -z "$ONLY" ] && echo "--changed: nothing changed; full gate"
        fi ;;
esac
if [ -n "$ONLY" ]; then
    # A tag matching no gate line would run ZERO screen harnesses and still exit
    # 0 -- a check that did not run and said it passed. Refuse instead.
    _tags=$(grep -oE '^gate [A-Za-z0-9_]+' "$0" | cut -d' ' -f2 | sort -u)
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
    # demo-big_demo.wasm. Name both, or use the bare gate.
fi

# gate <tag> <command...> - run a harness unless --only/--changed excludes it.
gate() {
    _tag=$1; shift
    if [ -n "$ONLY" ]; then
        for _s in $ONLY; do
            case "$_tag" in *"$_s"*) "$@"; return ;; esac
        done
        return 0
    fi
    "$@"
}

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
node apps/ram_check.mjs
node apps/rom_abi_check.mjs   # the ROM survives hostile arguments from any language
node apps/blitter_check.mjs   # blitter sources: plane offsets, cart RAM (SRC_ABS), refusals
node apps/beam_check.mjs      # BEAM (1.6.0): mid-line colour-0 cells across the whole line, persistence, no drops
node apps/beam_check.mjs --break   # ...and writes 4 px apart (faster than a move.w) are caught and counted as drops

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
    libs/zig/effects/pathchain_test.zig \
    libs/zig/effects/wave_test.zig \
    libs/zig/effects/spans_test.zig \
    libs/zig/effects/ballfield_test.zig \
    libs/zig/effects/chrome_draw_test.zig \
    libs/zig/effects/linepal_test.zig \
    libs/zig/effects/spanfont_test.zig \
    libs/zig/effects/tilegrid_test.zig \
    libs/zig/effects/zig3d_test.zig \
    libs/zig/effects/canvas_poly_test.zig \
    libs/zig/effects/colour_bank_test.zig \
    libs/zig/effects/beam_test.zig \
    machine/beam_test.zig \
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
    # printed only its binary path and the gate went on green (tnt3's zig3d and
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
python3 tools/gen_tutorial.py --check   # TUTORIAL.html regenerated from TUTORIAL.md
python3 -m unittest discover -q -s tools/tests -t tools   # the doc generators' own tests
node apps/disk_check.mjs
node apps/upload_check.mjs    # an uploaded disk mounts exactly like a URL one; bad uploads refused
node apps/tutorial_steps_check.mjs   # docs/TUTORIAL.html's per-step carts have not drifted from the finished ones

# --- headless harnesses: each drives the real machine end to end -----------
# Shots go to a scratch dir so a build does not litter the repo. These cover
# BOTH halves of the machine — GEM/ROM and the audio/SNDH side — because a host
# or ABI change breaks whichever one you were not thinking about.
SHOTS=$(mktemp -d)
node apps/verify.mjs          # the C and Rust carts still talk to the ABI
node apps/tunein_check.mjs    # C/Rust channels tune in through Zig's snow, byte for byte, then start as skipBoot
node apps/tunein_check.mjs --fail-proof docs/demo-c.wasm docs/demo-rust.wasm   # ...and a cart without tuneIn fails it
gate gem node apps/gem_headless.mjs "$SHOTS"
gate sndh node apps/sndh_headless.mjs
gate sndh_relocate node apps/sndh_relocate_check.mjs   # a tune that installs its own MFP vectors (Alloy Run) plays: images load at $10002
gate c_music timeout 180 node apps/c_music_check.mjs   # a C cart's song request reaches the sealed YM (timeout: it once hung a gate)
gate union_demo_music node apps/union_demo_music_check.mjs   # the Union Demo menu's and cracktro's SNDH tunes are requested by name and play
gate union_demo_music node apps/union_demo_music_check.mjs --fail-proof   # ...and a wrong tune name fails that check
gate union_intro_music node apps/union_intro_music_check.mjs   # the cracktro's music starts with the TRSI logo, and main doesn't restart it
gate union_intro_music node apps/union_intro_music_check.mjs --fail-proof   # ...and a wrong tune name fails that check
gate union_demo_doors node apps/union_demo_doors_check.mjs   # the hub's doors launch the Union screens by tag (they are hub-only)
gate union_demo node apps/union_demo_headless.mjs "$SHOTS/union_demo"   # hub: street wraps, view eases, keys stop at 60/144 Hz and on key-up, door memory
gate union_demo node apps/union_demo_headless.mjs --break return "$SHOTS/union_demo"   # ...and a lost ROM note fails the door-memory check
gate union_demo node apps/union_demo_headless.mjs --break wrap "$SHOTS/union_demo"   # ...and a door entered before the seam fails the wrap check
gate union_multifake node apps/union_multifake_headless.mjs "$SHOTS"   # TCB3: loader depack, then screen.js replayed pixel for pixel
gate union_intro_wab node apps/union_intro_wab_check.mjs docs/demo-union_intro.wasm   # cracktro WAB logo: lands as exactly wab.raw; the original JS replayed (skipped without prototypes/)
gate dbug node apps/dbug_headless.mjs "$SHOTS"
gate vex node apps/vex_headless.mjs "$SHOTS/vex"   # VEX 2025: logo, panel + its 4-page cycle, cubes, both scrollers, the raster rows
gate tcb_colorshock node apps/tcb_colorshock_headless.mjs "$SHOTS/tcb_colorshock"   # COLORSHOCK 2: the hardware pan, the per-line palettes, the strip on its table
gate replicants_emlyn node apps/replicants_emlyn_headless.mjs "$SHOTS/replicants_emlyn"   # EMLYN HUGHES: the bars are REAL rasters edge to edge (no pixel ever carries a bar colour; theta 0 is ONE colour register a line), Space switches ORIGINAL<->ZIG (bars turn, scrolltext bends on CODEF 484's curve), the sweeping logo, the flat scroller in the opened bottom border, Escape leaves, the tune plays with no unanswered hardware write
gate replicants_emlyn node apps/replicants_emlyn_headless.mjs --break rasters "$SHOTS/replicants_emlyn"   # ...and one static palette instead of a per-scanline one is caught
gate replicants_emlyn node apps/replicants_emlyn_headless.mjs --break borders "$SHOTS/replicants_emlyn"   # ...and rasters, logo OR scrolltext stopping at the content edge (the .top_bottom + window-clipped behaviour) is caught
gate replicants_emlyn node apps/replicants_emlyn_headless.mjs --break spin "$SHOTS/replicants_emlyn"   # ...and bars that never tilt without Space is caught
gate replicants_garfield node apps/replicants_garfield_headless.mjs "$SHOTS/replicants_garfield"   # GARFIELD: the four bouncing bars and the three red tubes are colour 0, real rasters edge to edge: every visible line's border follows colour 0 (a global HBL copies the copper's table into the machine background), the tubes are ST reds, top and bottom borders black
gate replicants_garfield node apps/replicants_garfield_headless.mjs --break noclear "$SHOTS/replicants_garfield"   # ...and a border that is never painted per line is caught
gate tsl_hybridglenz node apps/tsl_hybridglenz_headless.mjs "$SHOTS/tsl_hybridglenz"   # HYBRID GLENZ: the blitter's OR minterm really makes 1|2=3 in the panel, the two objects interlace onto odd/even plane rows and morph apart, the square flies in and dissolves into the framed panel, the three text overlays and the logo's white flash are palette fades, the bar and scroller run the full raster
gate tsl_hybridglenz node apps/tsl_hybridglenz_headless.mjs --break spin "$SHOTS/tsl_hybridglenz"   # ...and objects that never turn is caught
gate scrolllab node apps/scrolllab_headless.mjs "$SHOTS/scrolllab"   # SCROLLTEXT LAB: the ten distortions over one text (codef_fx siny/sinx/zoomy, a 2D path with a loop, screen 345's table) all render and all differ from FLAT, and Escape leaves
gate polkadots node apps/polkadots_headless.mjs "$SHOTS/polkadots"   # POLKA DOTS: the flat-shaded torus reaches the dot grid (100-700 cells stamped, never the whole grid), the light still makes big dots as well as small ones, all FOUR render modes draw a different picture at the op count the cart itself reports, and every one of them holds 60 fps
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
gate c_fujiboink node apps/c_fujiboink_headless.mjs "$SHOTS/c_fujiboink"   # FUJIBOINK! (C, START 1986): nine Hatari captures of FUJIBOIN.PRG, six pixel for pixel and three within a one-VBL mid-frame sliver; the rainbow is Timer B's 73 register lines (every pixel an ST index, entry 4 rewritten per line); the thud SNDH lands with the fuji and decays; F-key freeze, Space and Escape leave
gate c_fujiboink node apps/c_fujiboink_headless.mjs --break rasters "$SHOTS/c_fujiboink"   # ...and a plane whose HBL never runs (one static palette) is caught
gate c_fujiboink node apps/c_fujiboink_headless.mjs --break thud "$SHOTS/c_fujiboink"   # ...and a lost thud request is caught
gate fallen_angels node apps/fallen_angels_headless.mjs "$SHOTS"   # per-plane rasters on all 200 lines
gate tex_loader_fx node apps/tex_loader_fx_headless.mjs "$SHOTS/tex_loader_fx"   # fx = tex_loader on a real asset, bytes checked
gate tex node apps/tex_headless.mjs "$SHOTS"             # the eleven sprites on screen.js's chain
gate equinox node apps/equinox_headless.mjs "$SHOTS"   # the dragons morph egg -> dragon -> egg
gate tex_neoshow node apps/tex_neoshow_headless.mjs "$SHOTS/tex_neoshow"   # TEX NEO SHOW: the scroller band is a REAL per-line raster (copper), full plane width
gate mpp_truecolor node apps/mpp_truecolor_headless.mjs "$SHOTS"   # per-line palettes: colours on screen = captions
gate union_textracker node apps/union_textracker_headless.mjs "$SHOTS"   # TEX loader depack, then screen.js replayed pixel for pixel
gate union_demo_intro node apps/union_demo_intro_headless.mjs "$SHOTS"   # TEX loader depack, then every pixel on the screen.js replay
gate stream_pacing node apps/stream_pacing_check.mjs   # streamed audio tracks wall time at 18 fps, 144 Hz and across a 3 s stall
gate union_deltaforce node apps/union_deltaforce_headless.mjs "$SHOTS"   # DELTA FORCE: TEX loader depack, screen.js replayed pixel for pixel, the SNDH plays
gate union_texcopier node apps/union_texcopier_headless.mjs "$SHOTS"   # COPIER TEX: loader depack, screen.js replay incl. Chrome's blends, Scoop plays
gate union_tnt3 node apps/union_tnt3_headless.mjs "$SHOTS"   # TNT3: loader depack, then screen.js + three.js r49 replayed pixel for pixel
gate union_l16 node apps/union_l16_headless.mjs "$SHOTS"   # L16: loader depack, both overscan planes = screen.js replay, SNDH plays, Esc
gate union_tnt1 node apps/union_tnt1_headless.mjs "$SHOTS"   # TNT1 Starballs: TEX loader depack, screen.js replay (keys 5, 0), Pandora plays
gate union_reps node apps/union_reps_headless.mjs "$SHOTS"   # REPS: loader depack, screen.js replayed with the joystick, the SNDH plays
gate union_tnt2 node apps/union_tnt2_headless.mjs "$SHOTS"   # TNT2: TEX loader depack, screen.js + its keys replayed pixel for pixel, Cybernoid plays
gate union_beatdis node apps/union_beatdis_headless.mjs "$SHOTS"   # TCB1: loader depack + question, both versions replayed pixel for pixel, both SNDHs play
gate union_beatdis node apps/union_beatdis_headless.mjs --break keylock "$SHOTS"   # ...and a key lock that releases between repeats fails the hold check
gate union_superscroller node apps/union_superscroller_headless.mjs "$SHOTS"   # TCB2: TEX loader depack, screen.js with Chrome's filtering replayed pixel for pixel, the SNDH plays
gate automation442 node apps/automation442_headless.mjs "$SHOTS/automation442"   # AUTOMATION 442: the panned overscan scroll plane through one bgcount cycle
gate big_demo node apps/big_demo_headless.mjs   # TEX B.I.G. DEMO: wait screen hands over at frame 201, TEX's own 118 rows ripped from RAM, cursor clamps [2,115], all 45 named SNDH present, bands cycle
gate big_demo node apps/big_demo_headless.mjs --break nav   # ...and a list that never moves fails the clamp checks
gate big_demo node apps/big_demo_headless.mjs --break music   # ...and the wrong subtune fails the song check
gate big_demo node apps/big_demo_headless.mjs --break noop   # ...and an entry with no SNDH that asks for one fails (no silent substitution)
gate big_demo node apps/big_demo_headless.mjs --break songs   # ...and a named SNDH missing from docs/music/big/ fails (it would play silence)
gate digital_solution node apps/digital_solution_headless.mjs   # THE DIGITAL SOLUTION (a screen OF big_demo): list row 115 opens it, every px outside the scroller band = screen.raw, the band is the SHARED scrolltext in lockstep, the text cycles on texbg, opening it plays the DIGI Ace 2, keys 1-6 -> 6 subtunes
gate digital_solution node apps/digital_solution_headless.mjs --break pixels   # ...and one changed pixel of the reference fails the picture check
gate digital_solution node apps/digital_solution_headless.mjs --break tune   # ...and PHANTOMS 2 on the wrong subtune fails the key mapping
gate digital_solution node apps/digital_solution_headless.mjs --break songs   # ...and a named SNDH missing from docs/music/digital/ fails (it would play silence)
gate digital_solution node apps/digital_solution_headless.mjs --break exit   # ...and a key that is not Space failing to leave is caught
gate digital_solution node apps/digital_solution_headless.mjs --break route   # ...and Return one row short of the Digital Department not opening it is caught
gate digital_solution node apps/digital_solution_headless.mjs --break drift   # ...and one frame of scrolltext drift is caught (so a restart would be too)
gate digital_solution node apps/digital_solution_headless.mjs --break cycle   # ...and the text one cycle step out of phase is caught
node apps/tlb_spoon_headless.mjs "$SHOTS/tlb_spoon"   # TLB TWIDDLE: the sine intro, then starballs + logo + the rotating-letter scroller
gate stniccc node apps/stniccc_headless.mjs "$SHOTS/stniccc"   # STNICCC 2000 (Oxygene): the frame-replay flight, small -> rewind -> fullscreen
gate tlb_spoon node apps/tlb_spoon_headless.mjs "$SHOTS/tlb_spoon"   # TLB TWIDDLE: the sine intro, then starballs + logo + the rotating-letter scroller
echo "shots in $SHOTS"
