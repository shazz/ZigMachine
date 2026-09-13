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
pub const Entry = struct { name: []const u8, tag: []const u8 };

pub const ENTRIES = [_]Entry{
    .{ .name = "UNION INTRO", .tag = "union_intro" },
    .{ .name = "UNION MAIN", .tag = "union_main" },
    .{ .name = "MUSIC DEBUG", .tag = "music" },
    .{ .name = "BLITTER DEMO", .tag = "blitter" },
    .{ .name = "SCROLL DEMO", .tag = "scroll" },
    .{ .name = "OBJ DEMO", .tag = "obj" },
    .{ .name = "EXIT TO GEM", .tag = "gem" },
    .{ .name = "ST REPLAY", .tag = "st_replay" },
    .{ .name = "ANCOOL", .tag = "ancool" },
    .{ .name = "BLADERUNNERS", .tag = "bladerunners" },
    .{ .name = "DBUG", .tag = "dbug" },
    .{ .name = "DELTA FORCE", .tag = "deltaforce" },
    .{ .name = "DELTA FORCE 2", .tag = "deltaforce2" },
    .{ .name = "EMPIRE", .tag = "empire" },
    .{ .name = "EQUINOX", .tag = "equinox" },
    .{ .name = "FALLEN ANGELS", .tag = "fallen_angels" },
    .{ .name = "FULLSCREEN", .tag = "fullscreen" },
    .{ .name = "BAD FLICKER", .tag = "badflicker" },
    .{ .name = "ICS", .tag = "ics" },
    .{ .name = "LEONARD", .tag = "leonard" },
    .{ .name = "MAXI", .tag = "maxi" },
    .{ .name = "MED OVERSCAN", .tag = "medium_overscan" },
    .{ .name = "RES SWITCH", .tag = "res_switch" },
    .{ .name = "SHAPES", .tag = "shapes" },
    .{ .name = "STCS", .tag = "stcs" },
    .{ .name = "TEX", .tag = "tex" },
    .{ .name = "STREAM", .tag = "stream" },
    .{ .name = "NOEXTRA", .tag = "noextra" },
    .{ .name = "REPLICANTS DD2", .tag = "replicants_dd2" },
    .{ .name = "SUPPLEX FS2", .tag = "supplex_fs2" },
    .{ .name = "REPLICANTS GARFIELD", .tag = "replicants_garfield" },
    .{ .name = "ULM SPOON DISTORTER", .tag = "ulm_spoon_distorter" },
    .{ .name = "REPS OLD", .tag = "replicants" },
    .{ .name = "CUDDLY STARWARS", .tag = "cuddly_starwars" },
    .{ .name = "REPLICANTS KICK OFF 2", .tag = "replicants_kickoff2" },
    .{ .name = "DYNO PARADIS3", .tag = "dyno_paradis3" },
    .{ .name = "MANDELBROT", .tag = "mandelbrot" },
    .{ .name = "STNICCC 2000", .tag = "stniccc" },
    .{ .name = "TEX NEO SHOW", .tag = "tex_neoshow" },
    .{ .name = "REPS FRED (C)", .tag = "c-screen34" },
    .{ .name = "V8 POPULOUS (RUST)", .tag = "rust-v8_populous" },
    .{ .name = "ELITE SNOOKER", .tag = "elite_snooker" },
    .{ .name = "UNION DEMO", .tag = "union_demo" },
};
