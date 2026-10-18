// The dirty-band bookkeeping of dbug_draw.zig must leave the plane exactly as
// clearing and copying all 280 rows would: random scroller tops and logo
// positions, the plane compared with a full-clear reference after every frame.
// (The harnesses cannot drive it: the bounce follows the tune's clock.)
const std = @import("std");
const zg = @import("zigos");
const draw = @import("dbug_draw.zig");

test "dirty rows give the same plane as clearing and copying everything" {
    const logo_h = 38;
    var strip_px: [50 * 24]u8 = undefined;
    var rng = std.Random.DefaultPrng.init(7);
    for (&strip_px) |*p| p.* = rng.random().intRangeAtMost(u8, 0, 3);
    var strip_rb: zg.RenderBuffer = .{ .buffer = &strip_px, .width = 50, .height = 24 };
    const strip: zg.RenderTarget = .{ .render_buffer = &strip_rb };

    var page: [400 * 280]u8 align(4) = @splat(0);
    var ref: [400 * 280]u8 align(4) = @splat(0);
    var plane: [400 * 280]u8 = @splat(0);
    var page_rb: zg.RenderBuffer = .{ .buffer = &page, .width = 400, .height = 280 };
    var ref_rb: zg.RenderBuffer = .{ .buffer = &ref, .width = 400, .height = 280 };
    var dirty: draw.Dirty = .{};

    for (0..400) |_| {
        const top: u16 = rng.random().intRangeAtMost(u16, 0, 120); // 192 rows: some run off the page
        const ly: i32 = 20 + rng.random().intRangeAtMost(i32, -25, 40);
        const band = draw.Dirty.rows(top, @as(i32, top) + 24 * draw.ZOOM);

        draw.clearStale(&page, dirty, band);
        draw.zoomScroller(.{ .render_buffer = &page_rb }, strip, top, 24);
        @memset(&ref, 0);
        draw.zoomScroller(.{ .render_buffer = &ref_rb }, strip, top, 24);
        for ([_]*[400 * 280]u8{ &page, &ref }) |p| {
            const lo: usize = @intCast(@max(ly, 0));
            const hi: usize = @intCast(@min(ly + logo_h, 280));
            if (lo < hi) @memset(p[lo * 400 .. hi * 400], 9);
        }
        const now = band.merge(draw.Dirty.rows(ly, ly + logo_h));
        const copy = dirty.merge(now);
        const a = @as(usize, copy.lo) * 400;
        const b = @as(usize, copy.hi) * 400;
        @memcpy(plane[a..b], page[a..b]);
        dirty = now;
        try std.testing.expectEqualSlices(u8, &ref, &page);
        try std.testing.expectEqualSlices(u8, &ref, &plane);
    }
}
