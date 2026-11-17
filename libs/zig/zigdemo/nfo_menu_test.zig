const std = @import("std");
const expect = std.testing.expect;
const eq = std.testing.expectEqual;
const nfo = @import("nfo.zig");
const glyph = @import("nfo_glyph.zig");

const doc = ("line\n" ** 60);
const panel = "\xdb\xdb\xdb\xdb\xdb\xdb\n\xdb A  \xdb\n\xdb B  \xdb\n\xdb\xdb\xdb\xdb\xdb\xdb\n"; // a block frame round two choices
var buf: [640 * 600]u8 = undefined;

fn viewer() !nfo.Nfo {
    var n = try nfo.Nfo.init(doc, .{ .start_delay = 0, .frames_per_px = 1, .prompt = "SPACE: menu" });
    try n.setMenu(panel, "AB");
    n.paint(buf[0..n.bufferBytes()]);
    return n;
}

fn rowsEqual(a: []const u8, b: []const u8, from: usize, n: usize) bool {
    return std.mem.eql(u8, a[from * 640 ..][0 .. n * 640], b[from * 640 ..][0 .. n * 640]);
}

test "menu: Space opens it at the next update, centred in the page, and the page stops scrolling" {
    var n = try viewer();
    _ = n.update();
    const y = n.update();
    try eq(@as(u32, 2), y);
    try eq(@as(?u8, null), n.menu.?.key(' '));
    try expect(!n.menu.?.shown); // a key only queues: nothing drawn before the frame
    try eq(y, n.update());
    const m = &n.menu.?;
    try expect(m.shown);
    try eq(@as(u32, 4 * 9 + 1), m.rows());
    try eq(y + (462 - m.rows()) / 2, m.top);
    try eq(@as(usize, (80 - 6) / 2 * 8), m.x0());
    try eq(glyph.white, buf[(m.top + 3) * 640 + m.x0() + 3]); // the frame's top-left block
    for (0..20) |_| try eq(y, n.update()); // held
    n.userScroll(100); // the reader's scroll is dropped while it is open
    try eq(y, n.update());
}

test "menu: Space again or Esc closes it, its rows are the page's again and the scroll goes on" {
    var n = try viewer();
    var before: [640 * 600]u8 = undefined;
    @memcpy(before[0..n.bufferBytes()], buf[0..n.bufferBytes()]);
    _ = n.menu.?.key(' ');
    _ = n.update();
    const top = n.menu.?.top;
    try expect(!rowsEqual(&before, &buf, top, n.menu.?.rows()));
    _ = n.menu.?.key(nfo.menu.K_ESC);
    _ = n.update();
    try expect(!n.menu.?.shown);
    try expect(rowsEqual(&before, &buf, top, n.menu.?.rows()));
    const y0 = n.y;
    try expect(n.update() > y0); // the automatic scroll again
    _ = n.menu.?.key(' ');
    _ = n.update();
    _ = n.menu.?.key(' ');
    _ = n.update();
    try expect(!n.menu.?.shown);
}

test "menu: a choice key chooses only while open, in any case; other keys choose nothing" {
    var n = try viewer();
    const m = &n.menu.?;
    try eq(@as(?u8, null), m.key('a')); // closed
    _ = m.key(' ');
    try eq(@as(?u8, null), m.key('x'));
    try eq(@as(?u8, null), m.key(0xE001));
    try eq(@as(?u8, 'B'), m.key('b'));
    try eq(@as(?u8, 'B'), m.chosen);
    try expect(m.isOpen());
}

test "menu: a panel too wide, too tall or empty is an error" {
    var n = try nfo.Nfo.init(doc, .{ .prompt = "p" });
    try std.testing.expectError(error.MenuTooBig, n.setMenu("x" ** 79, "X"));
    try std.testing.expectError(error.MenuTooBig, n.setMenu("x\n" ** 52, "X"));
    try std.testing.expectError(error.MenuTooBig, n.setMenu("", "X"));
    try n.setMenu("x" ** 78, "X");
}
