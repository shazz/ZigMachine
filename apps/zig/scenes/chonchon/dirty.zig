// --------------------------------------------------------------------------
// Which 16-pixel planar groups a tick changed -- everything else of
// clock.screen is the background, untouched.
//
// The set is read back from the clock's own state after a step, so nothing is
// recorded while drawing:
//   * star i ORed one long at clock.starOffset(i): its group, and the next
//     one when the long straddles (offsets are even, mod 8 in {0, 2, 4, 6}
//     and a few odd ones in the Go's paths);
//   * scroller column c wrote its hi bytes on rows y1.. and its lo bytes on
//     rows y2.. (26 rows each) of group c+1: the span min(y1,y2)..max+25;
//   * meter ch ORed plane 3 of its 3/2/3 groups on rows 147..147+height.
// A group named twice is visited twice: both visits are idempotent (a
// restore, or an exact expansion), so no set is ever stored.
//
// Live: before the next step the cart restores the background under this set
// (computed while the clock still holds the last tick's state), and after it
// expands the new set into the WORK plane over the BG plane's copy.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");
const Clock = @import("clock.zig").Clock;

pub const METER_ROW: usize = 147;
pub const METER_GROUP = [3]usize{ 6, 9, 11 }; // x 96, 144, 176
pub const METER_GROUPS = [3]usize{ 3, 2, 3 }; // 48, 32, 48 px

/// The bar height a YM volume register selects (the Go's volume curve).
pub fn meterHeights(regs: [14]u8) [3]u8 {
    var h: [3]u8 = undefined;
    for (0..3) |ch| h[ch] = assets.volume_curve[regs[8 + ch] & 15];
    return h;
}

pub fn forEach(c: *const Clock, heights: [3]u8, ctx: anytype, comptime f: fn (@TypeOf(ctx), usize) void) void {
    for (0..100) |i| {
        const off = c.starOffset(i) orelse continue;
        f(ctx, off / 8);
        if ((off + 3) / 8 != off / 8) f(ctx, (off + 3) / 8);
    }
    for (0..18) |col| {
        const ys = c.columnYs(col);
        const lo = @max(@min(ys[0], ys[1]), 0);
        const hi = @min(@max(ys[0], ys[1]) + 26, 200);
        var y = lo;
        while (y < hi) : (y += 1) f(ctx, @as(usize, @intCast(y)) * 20 + col + 1);
    }
    for (0..3) |ch| {
        const h: usize = heights[ch];
        if (h == 0) continue;
        for (0..@min(h, 51) + 1) |row| {
            for (0..METER_GROUPS[ch]) |j| f(ctx, (METER_ROW + row) * 20 + METER_GROUP[ch] + j);
        }
    }
}
