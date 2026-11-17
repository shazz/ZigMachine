const std = @import("std");
const expect = std.testing.expect;
const eq = std.testing.expectEqual;
const nfo = @import("nfo.zig");
const render = @import("nfo_render.zig");

// --- the viewer ---

const doc = ("line\n" ** 60); // 540 px of text

var buf: [640 * 600]u8 = undefined; // the 60-line document needs 558 rows

fn newNfo(cfg: nfo.Config) !nfo.Nfo {
    return nfo.Nfo.init(doc, cfg);
}

test "nfo: the buffer is the text plus a window, and the first window is unmoved" {
    const n = try newNfo(.{ .prompt = "go" });
    try eq(@as(u32, 540 - (480 - 18)), n.y_max);
    try eq(n.y_max + 480, n.bufferRows());
    try eq(@as(usize, n.bufferRows()) * 640, n.bufferBytes());
    const short = try nfo.Nfo.init("a\nb\n", .{});
    try eq(@as(u32, 0), short.y_max);
    try eq(@as(u32, 480), short.bufferRows());
}

test "nfo: init refuses a zero step, a long prompt and a huge text" {
    try std.testing.expectError(error.BadConfig, newNfo(.{ .frames_per_px = 0 }));
    try std.testing.expectError(error.PromptTooLong, newNfo(.{ .prompt = "x" ** 81 }));
    try std.testing.expectError(error.TooManyLines, nfo.Nfo.init("x\n" ** 161, .{}));
}

test "nfo: waits start_delay, then moves 1 px every frames_per_px and stops at the end" {
    var n = try newNfo(.{ .start_delay = 5, .frames_per_px = 3, .prompt = "go" });
    n.paint(buf[0..n.bufferBytes()]);
    for (0..5) |_| try eq(@as(u32, 0), n.update());
    try eq(@as(u32, 0), n.update());
    try eq(@as(u32, 0), n.update());
    try eq(@as(u32, 1), n.update()); // the third frame after the delay
    for (0..3 * 10) |_| _ = n.update();
    try eq(@as(u32, 11), n.y);
    for (0..3 * 400) |_| _ = n.update();
    try eq(n.y_max, n.y); // stopped at the end
    try eq(n.y_max, n.update());
}

test "nfo: loop goes back to the top after end_hold frames" {
    var n = try newNfo(.{ .start_delay = 0, .frames_per_px = 1, .end = .loop, .end_hold = 4, .prompt = "go" });
    n.paint(buf[0..n.bufferBytes()]);
    for (0..n.y_max) |_| _ = n.update();
    try eq(n.y_max, n.y);
    for (0..3) |_| try eq(n.y_max, n.update());
    try eq(@as(u32, 0), n.update()); // the fourth hold frame
}

test "nfo: the bar stays at the window bottom and the text under it comes back" {
    var n = try newNfo(.{ .prompt = "press a key" });
    n.paint(buf[0..n.bufferBytes()]);
    var fresh: [640]u8 = undefined;
    for ([_]u32{ 1, 2, 30, 31, 10, 0, 29, 29, 78 }) |y| {
        n.scrollTo(y);
        const top: usize = n.barTop();
        try eq(@as(usize, y + 480 - 18), top);
        try std.testing.expectEqualSlices(u8, &n.bar, buf[top * 640 ..][0 .. 18 * 640]);
        // every row outside the bar equals a fresh render of that row
        for (0..n.bufferRows()) |r| {
            if (r >= top and r < top + 18) continue;
            render.renderRow(&n.text, @intCast(r), &fresh);
            try std.testing.expectEqualSlices(u8, &fresh, buf[r * 640 ..][0..640]);
        }
    }
}

test "nfo: scrollBy clamps, scrollTo past the end stops at the end" {
    var n = try newNfo(.{ .prompt = "go" });
    n.scrollBy(-5);
    try eq(@as(u32, 0), n.y);
    n.scrollBy(10);
    try eq(@as(u32, 10), n.y);
    n.scrollTo(100000);
    try eq(n.y_max, n.y);
    n.scrollBy(100000);
    try eq(n.y_max, n.y);
}

test "nfo: key matches the configured keys without case, others are nothing" {
    var n = try newNfo(.{ .keys = "OK" });
    try eq(@as(?u8, 'O'), n.key('o'));
    try eq(@as(?u8, 'O'), n.chosen);
    try eq(@as(?u8, 'K'), n.key('K'));
    try eq(@as(?u8, null), n.key('x'));
    try eq(@as(?u8, null), n.key(0xE012)); // Escape's code is not a letter
    try eq(@as(?u8, 'K'), n.chosen); // a miss keeps the last choice
}

test "nfo: a scroll by the reader stops the automatic scroll, restart() runs it again from the top" {
    var n = try newNfo(.{ .start_delay = 2, .frames_per_px = 1, .prompt = "go" });
    n.paint(buf[0..n.bufferBytes()]);
    for (0..12) |_| _ = n.update();
    try eq(@as(u32, 10), n.y);
    n.userScroll(5);
    try eq(@as(u32, 10), n.y); // queued: nothing moves before the frame's update
    for (0..50) |_| try eq(@as(u32, 15), n.update()); // then held where the reader put it
    n.userScroll(2);
    n.userScroll(3); // two keys in one frame add up
    try eq(@as(u32, 20), n.update());
    n.userScroll(-1000); // clamped at the top, still by hand
    for (0..10) |_| try eq(@as(u32, 0), n.update());
    n.restart();
    try expect(!n.manual);
    for (0..2) |_| try eq(@as(u32, 0), n.update()); // the start delay again
    try eq(@as(u32, 1), n.update());
}

test "nfo: page is the window less the bar, a whole window without a prompt" {
    const with_bar = try newNfo(.{ .prompt = "go" });
    const bare = try newNfo(.{ .prompt = "" });
    try expect(with_bar.page() < bare.page());
    try eq(@as(u32, 480), bare.page());
}
