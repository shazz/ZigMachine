// --------------------------------------------------------------------------
// DESKTOP.INF read back: what deskinf.zig writes, parsed for the boot that finds
// it on the disk (the shell reads the file, deskLoadInf hands it here). Only the
// records the writer emits are read; any other line (TOS's own #a, #b, #Z ...) is
// skipped, and a record that does not parse is skipped whole rather than half
// applied. Nothing here knows the screen: the window rectangles and icon cells
// come back as they were saved, and the desktop clamps them to the screen it is
// on when it applies them (deskmode.zig), so a desk-mode window is still
// reachable after a boot into low res. Pure text, so `zig test` covers it.
// --------------------------------------------------------------------------
const std = @import("std");
const deskinf = @import("deskinf.zig");

pub const Res = deskinf.Res;
pub const MAX_WINS = 7; // gui.MAX_WIN: one record a window the desktop can open
pub const PATH_MAX = 40; // dirmodel's window title

pub const Cell = struct { col: i16, row: i16 };
pub const Win = struct {
    x: i16, // pixels (the file holds character cells of 8)
    y: i16,
    w: i16,
    h: i16,
    text_view: bool,
    path: [PATH_MAX]u8 = [_]u8{0} ** PATH_MAX,
    plen: u8 = 0,

    pub fn pathSlice(self: *const Win) []const u8 {
        return self.path[0..self.plen];
    }
};

pub const Loaded = struct {
    res: ?Res = null,
    bg: ?[3]u8 = null,
    drive: ?Cell = null,
    trash: ?Cell = null,
    wins: [MAX_WINS]Win = undefined,
    n_wins: u8 = 0,
};

pub fn parse(text: []const u8) Loaded {
    var out = Loaded{};
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len < 3 or line[0] != '#') continue;
        var tok = std.mem.tokenizeScalar(u8, line[3..], ' ');
        switch (line[1]) {
            'E' => readE(&out, &tok),
            'W' => readW(&out, &tok, line),
            'M' => out.drive = readCell(&tok) orelse out.drive,
            'T' => out.trash = readCell(&tok) orelse out.trash,
            else => {},
        }
    }
    return out;
}

const Tok = std.mem.TokenIterator(u8, .scalar);

fn num(tok: *Tok) ?i16 {
    return std.fmt.parseInt(i16, tok.next() orelse return null, 10) catch null;
}

fn readE(out: *Loaded, tok: *Tok) void {
    const code = num(tok) orelse return;
    const rgb = tok.next() orelse return;
    if (code < 0 or code > 2 or rgb.len != 6) return; // an unknown resolution: no #E at all
    var bg: [3]u8 = undefined;
    for (&bg, 0..) |*c, i| c.* = std.fmt.parseInt(u8, rgb[i * 2 ..][0..2], 16) catch return;
    out.res = @enumFromInt(@as(u8, @intCast(code)));
    out.bg = bg;
}

fn readCell(tok: *Tok) ?Cell {
    const col = num(tok) orelse return null;
    const row = num(tok) orelse return null;
    if (col < 0 or row < 0) return null;
    return .{ .col = col, .row = row };
}

// "#W 00 00 xx yy ww hh v path@": the path runs to the '@' and may hold spaces.
fn readW(out: *Loaded, tok: *Tok, line: []const u8) void {
    if (out.n_wins == MAX_WINS) return;
    _ = num(tok) orelse return; // TOS's slider fields, which we write as 00
    _ = num(tok) orelse return;
    var v: [5]i16 = undefined;
    for (&v) |*x| x.* = num(tok) orelse return;
    const rest = line[3 + tok.index ..]; // the tokenizer runs over line[3..]
    const start = std.mem.indexOfNone(u8, rest, " ") orelse return;
    const end = std.mem.indexOfScalar(u8, rest, '@') orelse return;
    if (end < start or v[2] <= 0 or v[3] <= 0) return;
    const path = rest[start..end];
    var w = Win{ .x = v[0] * 8, .y = v[1] * 8, .w = v[2] * 8, .h = v[3] * 8, .text_view = v[4] != 0 };
    w.plen = @intCast(@min(path.len, PATH_MAX));
    @memcpy(w.path[0..w.plen], path[0..w.plen]);
    out.wins[out.n_wins] = w;
    out.n_wins += 1;
}

// --- native tests -----------------------------------------------------------
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "what deskinf.write writes reads back, the desk mode's 02 included" {
    var buf: [deskinf.MAX_BYTES]u8 = undefined;
    const text = deskinf.write(&buf, .{
        .res = .desk,
        .bg = .{ 1, 160, 164 },
        .drive = .{ .col = 0, .row = 0, .label = "FLOPPY DISK" },
        .trash = .{ .col = 0, .row = 57, .label = "TRASH" },
        .wins = &.{.{ .x = 400, .y = 296, .w = 200, .h = 160, .text_view = true, .path = "A:\\FOLDER ONE" }},
    });
    const got = parse(text);
    try expectEqual(Res.desk, got.res.?);
    try expectEqual([3]u8{ 1, 160, 164 }, got.bg.?);
    try expectEqual(Cell{ .col = 0, .row = 57 }, got.trash.?);
    try expectEqual(@as(u8, 1), got.n_wins);
    const w = got.wins[0];
    try expectEqual(@as(i16, 400), w.x);
    try expectEqual(@as(i16, 296), w.y);
    try expectEqual(@as(i16, 200), w.w);
    try expect(w.text_view);
    try std.testing.expectEqualStrings("A:\\FOLDER ONE", w.pathSlice());
}

test "low and medium read back as themselves" {
    try expectEqual(Res.low, parse("#E 00 ffffff\r\n").res.?);
    try expectEqual(Res.medium, parse("#E 01 000000\n").res.?);
}

test "an unknown resolution or a broken record is skipped, not guessed" {
    try expectEqual(@as(?Res, null), parse("#E 03 01a0a4\r\n").res);
    try expectEqual(@as(?Res, null), parse("#E 02 01a0\r\n").res);
    try expectEqual(@as(?Res, null), parse("#E xx 01a0a4\r\n").res);
    try expectEqual(@as(u8, 0), parse("#W 00 00 01 02 03\r\n").n_wins); // no size, no path
    try expectEqual(@as(u8, 0), parse("#W 00 00 01 02 00 05 00 A:\\@\r\n").n_wins); // zero width
    try expectEqual(@as(?Cell, null), parse("#M 01\r\n").drive);
}

test "an empty or foreign file loads nothing" {
    const none = parse("");
    try expectEqual(@as(?Res, null), none.res);
    try expectEqual(@as(u8, 0), none.n_wins);
    const tos = parse("#a000000\r\n#Z 01 C:\\EDIT.PRG@ *.S@\r\n#E 01 7fffff\r\n");
    try expectEqual(Res.medium, tos.res.?); // TOS's other records are skipped around
}
