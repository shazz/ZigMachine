// --------------------------------------------------------------------------
// The headless harness's door into the battle (apps/north_south_headless.mjs):
// start a battle exactly as a reference script does, run one battle-loop
// iteration with the three input bytes the original read, and read back the
// state, the screen, the sounds and the frame's length. It drives the SAME
// Game the scene plays, so what it proves is the cart's own battle.
// Every cart's build analyses every scene file, so these exports are pulled
// in only when this scene IS the cart (north_south.zig checks cart.Cart).
// --------------------------------------------------------------------------
const mem = @import("mem.zig");
const G = @import("game.zig");
const setup = @import("setup.zig");
const scene = @import("../north_south.zig");

/// army bytes 255 = keep the dump's record; seed_given 0 = keep the dump's RNG.
export fn nsTestStart(field: u32, ui: u32, uc: u32, un: u32, ci: u32, cc: u32, cn: u32, mode: u32, la: i32, lb: i32, seed_given: u32, seed: u32) void {
    mem.misses = 0;
    setup.start(&scene.game, .{
        .field = @intCast(field),
        .union_army = if (ui == 255) null else .{ @intCast(ui), @intCast(uc), @intCast(un) },
        .confed_army = if (ci == 255) null else .{ @intCast(ci), @intCast(cc), @intCast(cn) },
        .mode = @enumFromInt(mode),
        .level_a = la,
        .level_b = lb,
        .seed = if (seed_given != 0) seed else null,
    });
}

/// One battle frame; returns the result (0 = still running, 1 or 2).
export fn nsTestFrame(key: u32, joy: u32, port1: u32) u32 {
    scene.game.frame(.{ .key = @truncate(key), .joy = @truncate(joy), .port1 = @truncate(port1) });
    return scene.game.result;
}

export fn nsRamPtr() [*]u8 {
    return &scene.game.m.ram;
}
export fn nsRamLen() u32 {
    return mem.SIZE;
}
export fn nsShownPtr() [*]u8 {
    return scene.game.shown();
}
export fn nsEventCount() u32 {
    return @intCast(scene.game.nevents);
}
export fn nsEvent(i: u32) u32 {
    return scene.game.events[i];
}
export fn nsVbls() u32 {
    return scene.game.pace.last_vbls;
}
export fn nsFrames() u32 {
    return scene.game.frames;
}
export fn nsMisses() u32 {
    return mem.misses;
}
