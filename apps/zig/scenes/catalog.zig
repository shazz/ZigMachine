// --------------------------------------------------------------------------
// Scene catalog — the scenes the menu links directly, as a tagged union + a
// parallel display list. Kept separate from menu.zig (the UI) so both stay under
// the 200-line limit.
//
// NOTE: linking every scene into one demo.wasm overflows the 2 MiB demo window
// (all their @embedFile'd assets compile in at once). The plan is to boot scenes
// as SEPARATE cartridges (demo-<name>.wasm) launched by the host — see the
// cartridge-launcher work — so this list is the linkable core, not everything.
// All 30 scenes still compile individually; a fuller list lived here transiently
// and proved the reorg didn't break them (5 are pre-existing bit-rot: demo,
// demo_test, bladerunners_fullscreen, mandelbrot, replicants).
// --------------------------------------------------------------------------
const std = @import("std");

pub const Child = union(enum) {
    none,
    union_intro: @import("union_intro.zig").Demo,
    union_main: @import("union/doors.zig").Doors,
    music: @import("music_debug.zig").Demo,
    blitter: @import("blitter_demo.zig").Demo,
    scroll: @import("scroll_demo.zig").Demo,
    obj: @import("obj_demo.zig").Demo,
    gem: @import("gem_desktop.zig").Demo,
    st_replay: @import("st_replay.zig").App,
};

pub const Tag = std.meta.Tag(Child);
pub const Entry = struct { name: []const u8, tag: Tag };

// Display order (column-major, filled by the menu into 2 columns).
pub const ENTRIES = [_]Entry{
    .{ .name = "UNION INTRO", .tag = .union_intro },
    .{ .name = "UNION MAIN", .tag = .union_main },
    .{ .name = "MUSIC DEBUG", .tag = .music },
    .{ .name = "BLITTER DEMO", .tag = .blitter },
    .{ .name = "SCROLL DEMO", .tag = .scroll },
    .{ .name = "OBJ DEMO", .tag = .obj },
    .{ .name = "GEM DESKTOP", .tag = .gem },
    .{ .name = "ST REPLAY", .tag = .st_replay },
};
