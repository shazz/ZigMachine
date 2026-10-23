// --------------------------------------------------------------------------
// The live picture, built in the chunky domain (the board's 64,000 per-pixel
// stores a frame were more than its whole frame budget):
//
//   tick:   restore(clock.screen) under the last tick's dirty groups from an
//           aligned copy of the background, then Clock.advance + meter.apply
//           (the planar engine itself, minus its 32000-byte memcpy);
//   render: WORK <- BG (one CHISEL copy), the dirty groups expanded from
//           clock.screen into WORK (4 u32 stores each), the 63 logo rows as
//           keyed blits from logo.idx, then SHOWN <- WORK (one copy).
//
// Exact by construction: clock.screen differs from the background only in the
// dirty groups, so WORK == expand(clock.screen). chunky_test.zig proves it on
// every tick against reference.zig. In-plane copies: 0.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");
const Clock = @import("clock.zig").Clock;
const dirty = @import("dirty.zig");
const gpu = @import("gpu.zig");

/// The background, 4-aligned, so a group restores as two u32 stores.
pub var bg_aligned: [32000]u8 align(4) = undefined;

pub fn initBackground(comptime G: type, g: *G) void {
    @memcpy(&bg_aligned, assets.background);
    gpu.expandScreen(g.words(gpu.BG), &bg_aligned);
}

fn restoreGroup(screen: *[32000]u8, group: usize) void {
    const d: *[2]u32 = @ptrCast(@alignCast(screen[group * 8 ..][0..8]));
    const s: *const [2]u32 = @ptrCast(@alignCast(bg_aligned[group * 8 ..][0..8]));
    d[0] = s[0];
    d[1] = s[1];
}

/// One 50 Hz step of the live cart (the reference's Clock.step + meter.apply).
pub fn tick(c: *Clock, prev_heights: [3]u8, regs: [14]u8, comptime meterApply: fn ([]u8, [14]u8) void) void {
    dirty.forEach(c, prev_heights, &c.screen, restoreGroup);
    c.advance();
    meterApply(c.screen[0..], regs);
}

const Expand = struct { out: [*]u32, screen: *const [32000]u8 };

fn expandOne(e: Expand, group: usize) void {
    gpu.expandGroup(e.out + group * 4, e.screen[group * 8 ..][0..8]);
}

pub fn render(comptime G: type, g: *G, c: *const Clock, heights: [3]u8) void {
    g.copy(gpu.WORK, gpu.BG);
    dirty.forEach(c, heights, Expand{ .out = g.words(gpu.WORK), .screen = &c.screen }, expandOne);
    for (0..63) |row| {
        const lr = c.logoRow(row);
        if (lr.y < 0 or lr.y >= gpu.H or lr.x >= gpu.W) continue;
        const w: u16 = @intCast(@min(96, gpu.W - @as(usize, @intCast(lr.x))));
        const sy: u16 = @intCast(row * 17 + lr.phase);
        g.image(gpu.WORK, @intCast(lr.x), @intCast(lr.y), assets.logo, 96, 0, sy, w, 1, 0);
    }
    g.copy(gpu.SHOWN, gpu.WORK);
}
