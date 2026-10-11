// --------------------------------------------------------------------------
// The rewind on the real stream (scene1.bin): once the flight has been played
// forward, seeking back to ANY frame draws at most snaps.EVERY frames, and the
// window then holds exactly what playing in order left there. Without the
// keyframes a seek replays its whole delta chain (up to ~100 frames), which is
// what froze the rewind on the board. Run from apps/zig/scene_tests.zig (the
// embed resolves under apps/zig/).
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("stream.zig");
const player_mod = @import("player.zig");
const snaps_mod = @import("snaps.zig");
const polyfill = @import("polyfill.zig");

const SCENE = @embedFile("../../assets/screens/stniccc/scene1.bin");
// Past the frame the rewind turns back at (frame ~674: the 600 small frames,
// then the slow-down's ~75), so every frame it can ask for was played forward.
const LAST: u32 = 760;
const STRIDE = 320; // the scene's small window: 256x200, centred on a 320-wide plane
const OX = (STRIDE - player_mod.SRC_W) / 2;
const WIN = player_mod.SRC_W * player_mod.SRC_H;

const Rig = struct {
    src: st.SliceSource,
    buf: [st.BLOCK]u8,
    index: player_mod.Index,
    screen: [STRIDE * player_mod.SRC_H]u8,
    snaps: snaps_mod.Snaps,
    p: player_mod.Player,

    fn view(self: *Rig) player_mod.View {
        const t = polyfill.Target{ .px = &self.screen, .stride = STRIDE, .w = player_mod.SRC_W, .h = player_mod.SRC_H, .ox = OX };
        return .{ .target = t, .w = player_mod.SRC_W, .h = player_mod.SRC_H };
    }
    fn window(self: *const Rig, out: []u8) void {
        for (0..player_mod.SRC_H) |y| @memcpy(out[y * player_mod.SRC_W ..][0..player_mod.SRC_W], self.screen[y * STRIDE + OX ..][0..player_mod.SRC_W]);
    }
};

// A rig played forward over frames 0..LAST, each frame's window recorded in `ref`.
fn playForward(a: std.mem.Allocator, pool: ?[]u8, ref: []u8) !*Rig {
    const r = try a.create(Rig);
    r.src = .{ .bytes = SCENE };
    @memset(&r.screen, 0);
    r.p.init(r.src.source(), &r.buf, &r.index);
    if (pool) |bytes| {
        r.snaps.init(bytes);
        r.p.snaps = &r.snaps;
    }
    for (0..LAST + 1) |n| {
        try r.p.show(@intCast(n), r.view());
        r.window(ref[n * WIN ..][0..WIN]);
    }
    return r;
}

test "with keyframes, seeking back to any frame draws at most EVERY frames and is pixel-exact" {
    const a = std.testing.allocator;
    const ref = try a.alloc(u8, (LAST + 1) * WIN);
    defer a.free(ref);
    const pool = try a.alloc(u8, snaps_mod.POOL_BYTES);
    defer a.free(pool);
    const r = try playForward(a, pool, ref);
    defer a.destroy(r);
    try std.testing.expect(!r.snaps.full); // every keyframe up to LAST fit the scene's pool
    var got: [WIN]u8 = undefined;
    var n: u32 = LAST;
    while (true) : (n -= 1) { // back one frame at a time: every seek is out of order
        try r.p.show(n, r.view());
        try std.testing.expect(r.p.drawn <= snaps_mod.EVERY);
        r.window(&got);
        try std.testing.expectEqualSlices(u8, ref[n * WIN ..][0..WIN], &got);
        if (n == 0) break;
    }
}

test "without keyframes a seek back replays its whole delta chain (the frozen rewind)" {
    const a = std.testing.allocator;
    const ref = try a.alloc(u8, (LAST + 1) * WIN);
    defer a.free(ref);
    const r = try playForward(a, null, ref);
    defer a.destroy(r);
    var worst: u32 = 0;
    var n: u32 = LAST;
    while (n > 0) : (n -= 8) { // the rewind's top speed: 8 frames a VBL
        try r.p.show(n, r.view());
        worst = @max(worst, r.p.drawn);
    }
    try std.testing.expect(worst > 50);
}
