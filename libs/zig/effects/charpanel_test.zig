// Tests for effects/charpanel.zig. They live beside the effect rather than
// inside it (the usual convention here) only because charpanel.zig is already
// at the 200-line ceiling.
//
// The panels below use 1x1 cells and a two-stage zoom, so one cell is exactly
// one pixel and the whole animation can be asserted as a flat byte slice.
const std = @import("std");
const charpanel = @import("charpanel.zig");

const COLS = 4;
const ROWS = 3;
const CELLS = COLS * ROWS;

// glyph i is the single pixel value i; 0 stays transparent, as the effect expects
const FONT = blk: {
    var f: [256]u8 = undefined;
    for (&f, 0..) |*p, i| p.* = @intCast(i);
    break :blk f;
};

const TEXTS = [_][]const u8{ "ABCDEFGHIJKL", "MNOPQRSTUVWX" };
// pattern 0 fills left to right, pattern 1 empties right to left
const PATTERNS = [_]u8{
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
    11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0,
};
const STEPS = [_]charpanel.Step{ .{ .size = 0, .off = 0 }, .{ .size = 1, .off = 0 } };

const Panel = charpanel.Panel(STEPS.len);

fn config(font: []const u8) charpanel.Config {
    return .{
        .cols = COLS,
        .rows = ROWS,
        .cell_w = 1,
        .cell_h = 1,
        .font = font,
        .steps = &STEPS,
        .texts = &TEXTS,
        .patterns = &PATTERNS,
        .wait_frames = 3,
    };
}

fn run(panel: *Panel, dst: []u8, frames: usize) void {
    for (0..frames) |_| {
        panel.update();
        panel.render(dst, COLS, 0, 0);
    }
}

// One cell starts per frame and needs one more frame to reach full size, so the
// last cell of a 12-cell panel stands on frame 13.
const WRITE_FRAMES = CELLS + 1;

test "a panel writes every cell of its pattern, one per frame" {
    var panel: Panel = undefined;
    panel.init(config(&FONT));
    var screen = [_]u8{0} ** CELLS;

    run(&panel, &screen, WRITE_FRAMES - 1);
    try std.testing.expectEqual(@as(u8, 0), screen[CELLS - 1]); // last cell not there yet

    run(&panel, &screen, 1);
    for (screen, 0..) |pixel, i| try std.testing.expectEqual(@as(u8, 'A' - 32 + @as(u8, @intCast(i))), pixel);
}

test "a finished panel is held, then erased, and the next text takes over" {
    var panel: Panel = undefined;
    panel.init(config(&FONT));
    var screen = [_]u8{0} ** CELLS;

    run(&panel, &screen, WRITE_FRAMES);
    // The hold: one frame to turn around, then wait_frames of nothing.
    run(&panel, &screen, 1 + 3);
    try std.testing.expectEqual(@as(u8, 'A' - 32), screen[0]); // still standing

    run(&panel, &screen, CELLS); // erased right to left, one cell per frame
    try std.testing.expectEqualSlices(u8, &[_]u8{0} ** CELLS, &screen);

    run(&panel, &screen, 1 + WRITE_FRAMES); // turn around again, write text 2
    for (screen, 0..) |pixel, i| try std.testing.expectEqual(@as(u8, 'M' - 32 + @as(u8, @intCast(i))), pixel);
}

test "a character the font sheet does not carry leaves its cell blank" {
    const short = FONT[0..60]; // ASCII 32..91 only, as the D-BUG sheets are
    const missing = [_][]const u8{"abcdefghijkl"}; // lowercase: past the end of the sheet
    var cfg = config(short);
    cfg.texts = &missing;

    var panel: Panel = undefined;
    panel.init(cfg);
    var screen = [_]u8{0} ** CELLS;
    run(&panel, &screen, WRITE_FRAMES);

    try std.testing.expectEqualSlices(u8, &[_]u8{0} ** CELLS, &screen);
}

test "a panel that does not fit its destination clips instead of running off the end" {
    var panel: Panel = undefined;
    panel.init(config(&FONT));
    var screen = [_]u8{0} ** CELLS;

    // Two rows below the top: the bottom row of the panel falls off the buffer.
    for (0..WRITE_FRAMES) |_| {
        panel.update();
        panel.render(&screen, COLS, 0, 2);
    }
    // The rows that DO fit were written; nothing beyond the slice was touched.
    try std.testing.expectEqual(@as(u8, 'A' - 32), screen[2 * COLS]);
}
