// --------------------------------------------------------------------------
// Launcher catalog — the scenes the menu offers, as display name + cartridge tag.
// Each tag <t> is built as demo-<t>.wasm and packed into demo-<t>.zmd (a floppy);
// on Fire the menu returns the tag and the host boots that disk.
//
// This is a plain string list — the menu links NO scenes (that's the whole point:
// each scene is its own cartridge, so nothing bloats the launcher). MUST stay in
// sync with the cartridge matrix in build.zig — except polyglot carts (tags
// c-* / rust-*), which apps/{c,rust}/build.sh builds; tools/mkdisks.sh packs a
// floppy for any polyglot tag listed here.
//
// Excluded (pre-existing bit-rot vs the current ZigOS API): demo, demo_test,
// bladerunners_fullscreen.
// --------------------------------------------------------------------------
// The trailing comment on each entry is its TYPE — the machine the screen comes
// from: "atari st", "amiga", "zigmachine" (an original screen or a tech demo),
// "system" (GEM, ST Replay: not demos), or "unknown" where the scene's own source
// does not say and nobody has checked. tools/channels.py parses it into
// docs/channels.json, and the host's VHS name card (docs/cart-osd.js) prints it.
// It is a COMMENT, not a field, on purpose: this is host presentation metadata,
// which the menu cart would otherwise carry as dead bytes — and a comment on the
// line you already edit when adding a screen cannot drift out of sync the way a
// second list would. channels.py FAILS if an entry has no known type.
pub const Entry = struct { name: []const u8, tag: []const u8 };

pub const ENTRIES = [_]Entry{
    .{ .name = "UNION INTRO", .tag = "union_intro" }, // atari st
    .{ .name = "UNION MAIN", .tag = "union_main" }, // atari st
    .{ .name = "MUSIC DEBUG", .tag = "music" }, // zigmachine
    .{ .name = "BLITTER DEMO", .tag = "blitter" }, // zigmachine
    .{ .name = "SCROLL DEMO", .tag = "scroll" }, // zigmachine
    .{ .name = "OBJ DEMO", .tag = "obj" }, // zigmachine
    .{ .name = "EXIT TO GEM", .tag = "gem" }, // system
    .{ .name = "ST REPLAY", .tag = "st_replay" }, // system
    .{ .name = "ANCOOL", .tag = "ancool" }, // atari st
    .{ .name = "BLADERUNNERS", .tag = "bladerunners" }, // atari st
    .{ .name = "DBUG", .tag = "dbug" }, // atari st
    .{ .name = "DELTA FORCE", .tag = "deltaforce" }, // atari st
    .{ .name = "DELTA FORCE 2", .tag = "deltaforce2" }, // atari st
    .{ .name = "EMPIRE", .tag = "empire" }, // atari st
    .{ .name = "EQUINOX", .tag = "equinox" }, // atari st
    .{ .name = "FALLEN ANGELS", .tag = "fallen_angels" }, // atari st
    .{ .name = "FULLSCREEN", .tag = "fullscreen" }, // zigmachine
    .{ .name = "BAD FLICKER", .tag = "badflicker" }, // zigmachine
    .{ .name = "ICS", .tag = "ics" }, // atari st
    .{ .name = "LEONARD", .tag = "leonard" }, // atari st
    .{ .name = "MAXI", .tag = "maxi" }, // zigmachine
    .{ .name = "MED OVERSCAN", .tag = "medium_overscan" }, // zigmachine
    .{ .name = "RES SWITCH", .tag = "res_switch" }, // zigmachine
    .{ .name = "SHAPES", .tag = "shapes" }, // zigmachine
    .{ .name = "STCS", .tag = "stcs" }, // atari st
    .{ .name = "TEX", .tag = "tex" }, // atari st
    .{ .name = "STREAM", .tag = "stream" }, // zigmachine
    .{ .name = "NOEXTRA", .tag = "noextra" }, // atari st
    .{ .name = "REPLICANTS DD2", .tag = "replicants_dd2" }, // atari st
    .{ .name = "SUPPLEX FS2", .tag = "supplex_fs2" }, // amiga
    .{ .name = "REPLICANTS GARFIELD", .tag = "replicants_garfield" }, // atari st
    .{ .name = "ULM SPOON DISTORTER", .tag = "ulm_spoon_distorter" }, // atari st
    .{ .name = "REPS OLD", .tag = "replicants" }, // atari st
    .{ .name = "CUDDLY STARWARS", .tag = "cuddly_starwars" }, // atari st
    .{ .name = "REPLICANTS KICK OFF 2", .tag = "replicants_kickoff2" }, // atari st
    .{ .name = "DYNO PARADIS3", .tag = "dyno_paradis3" }, // atari st
    .{ .name = "MANDELBROT", .tag = "mandelbrot" }, // zigmachine
    .{ .name = "STNICCC 2000", .tag = "stniccc" }, // atari st
    .{ .name = "TEX NEO SHOW", .tag = "tex_neoshow" }, // atari st
    .{ .name = "REPS FRED (C)", .tag = "c-screen34" }, // atari st
    .{ .name = "V8 POPULOUS (RUST)", .tag = "rust-v8_populous" }, // atari st
    .{ .name = "ELITE SNOOKER", .tag = "elite_snooker" }, // atari st
    .{ .name = "UNION DEMO", .tag = "union_intro_screen" }, // atari st — the demo opens on its intro splash; Space goes on to the street (union_demo)
    .{ .name = "TUTORIAL", .tag = "tutorial" }, // zigmachine
    .{ .name = "MPP TRUECOLOR", .tag = "mpp_truecolor" }, // zigmachine
    .{ .name = "AUTOMATION 442", .tag = "automation442" }, // atari st
    .{ .name = "TEX B.I.G. DEMO", .tag = "big_demo" }, // atari st
    .{ .name = "TLB TWIDDLE DEMO", .tag = "tlb_spoon" }, // atari st
    .{ .name = "TCB COLORSHOCK", .tag = "tcb_colorshock" }, // atari st
    .{ .name = "VEX 2025 GTA VI", .tag = "vex" }, // atari st
    .{ .name = "REPLICANTS EMLYN", .tag = "replicants_emlyn" }, // atari st
    .{ .name = "SCROLLTEXT LAB", .tag = "scrolllab" }, // zigmachine
    .{ .name = "SILENTS HYBRID GLENZ", .tag = "tsl_hybridglenz" }, // amiga
    .{ .name = "POLKA DOTS", .tag = "polkadots" }, // zigmachine
    .{ .name = "ELITE CHALLENGE FOOT", .tag = "elite_cfsr" }, // atari st
    .{ .name = "RNO SODIUM", .tag = "rno_sodium" }, // atari st
    .{ .name = "RNO NATRIUM", .tag = "rno_natrium" }, // atari st
    .{ .name = "DHS 0PIXELS 0REGRETS", .tag = "dhs_0pxl0reg" }, // atari st
    .{ .name = "TRSI TRANSARCTICA", .tag = "trsi_transarctica" }, // atari falcon
    .{ .name = "FUJIBOINK (C)", .tag = "c-fujiboink" }, // atari st
    .{ .name = "NORTH & SOUTH BATTLE", .tag = "north_south" }, // atari st
    // The Union Demo's screens (union_multifake, union_textracker, ...) are NOT
    // listed: they are reached only through the UNION DEMO hub's doors (Matt,
    // 2026-09-13). Their carts stay in build.zig / cart.zig, so their disks build.
};
