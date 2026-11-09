// Native tests of the damage pass + compositor (scene.zig, damage.zig, compose.zig):
// painting only the damage gives, byte for byte, what a whole repaint gives; a scene
// that did not change damages nothing; an external layer is never painted over.
const std = @import("std");
const obj = @import("obj.zig");
const L = @import("look.zig");
const canvas = @import("canvas.zig");
const rect = @import("rect.zig");
const scene = @import("scene.zig");
const damage = @import("damage.zig");
const compose = @import("compose.zig");
const Object = obj.Object;
const Rect = rect.Rect;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

const W = 96;
const H = 64;
const SCREEN: Rect = .{ .w = W, .h = H };
const glyphs = [_]u8{0xA0} ** (256 * 3);
const FONT: canvas.Font = .{ .w = 3, .h = 3, .data = &glyphs };
const PAL = [16]u8{ 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 };
const LOOK: L.Look = .{ .pal = PAL, .font = &FONT, .small = &FONT, .three_d = true };

const desk_box = obj.boxSpec(0, 0, obj.colorWord(1, 1, true, 4, 3)); // replace mode: opaque, as the desktop is
const win_box = obj.boxSpec(0, 1, obj.colorWord(1, 1, true, 7, 0));
const arrow_bits = [_]u8{ 0xF0, 0xE0, 0xC0, 0x80 };

const World = struct {
    desk: [3]Object = .{
        .{ .head = 1, .tail = 2, .ty = obj.G_BOX, .spec = .{ .box = desk_box }, .w = W, .h = H },
        .{ .next = 2, .ty = obj.G_BUTTON, .flags = obj.FL3DACT, .spec = .{ .str = "AB" }, .x = 6, .y = 40, .w = 14, .h = 8 },
        .{ .next = 0, .ty = obj.G_STRING, .spec = .{ .str = "DESK" }, .x = 60, .y = 50, .w = 12, .h = 5 },
    },
    wins: [2][2]Object = .{ win(10, 8), win(40, 20) },
    order: [2]u16 = .{ 0, 1 },
    ptr: [1]Object = .{.{ .ty = obj.G_IMAGE, .x = 30, .y = 30, .w = 4, .h = 4 }},
    image: obj.BitBlk = .{ .data = &arrow_bits, .w = 4, .h = 4, .color = 1 },

    fn build(self: *World, s: *scene.Scene) void {
        s.* = .{};
        self.ptr[0].spec = .{ .image = &self.image };
        s.add(.{ .key = 1, .tree = &self.desk });
        for (self.order) |k| {
            const w = &self.wins[k][0];
            s.add(.{ .key = 10 + k, .tree = &self.wins[k], .cover = .{ .{ .x = w.x, .y = w.y, .w = w.w, .h = w.h }, .{}, .{}, .{} }, .n_cover = 1 });
        }
        s.add(.{ .key = 99, .tree = &self.ptr });
        s.measure(&LOOK);
    }
};

fn win(x: i16, y: i16) [2]Object {
    return .{
        .{ .head = 1, .tail = 1, .ty = obj.G_BOX, .flags = obj.CLIPKIDS, .spec = .{ .box = win_box }, .x = x, .y = y, .w = 36, .h = 24 },
        .{ .next = 0, .ty = obj.G_STRING, .spec = .{ .str = "FILE.TXT" }, .x = 2, .y = 4, .w = 24, .h = 5 },
    };
}

fn whole(w: *World, buf: *[W * H]u8) void {
    var s: scene.Scene = undefined;
    w.build(&s);
    @memset(buf, 0);
    var cv = canvas.Canvas.init(buf, W, W, H);
    var d: rect.RectList = .{};
    d.add(SCREEN);
    var st: compose.Stats = .{};
    compose.compose(&cv, &LOOK, &s, &d, &st);
}

/// One incremental frame into `buf` (holding `snap`'s scene); returns the damage area.
fn step(w: *World, buf: *[W * H]u8, snap: *damage.Snap) u32 {
    var s: scene.Scene = undefined;
    w.build(&s);
    var d: rect.RectList = .{};
    damage.diff(&s, snap, SCREEN, &d);
    var cv = canvas.Canvas.init(buf, W, W, H);
    var st: compose.Stats = .{};
    compose.compose(&cv, &LOOK, &s, &d, &st);
    snap.record(&s);
    return d.area();
}

test "an unchanged scene damages nothing; a pointer move damages two small boxes" {
    var w: World = .{};
    var buf: [W * H]u8 = undefined;
    var snap: damage.Snap = .{};
    @memset(&buf, 0);
    try expectEqual(@as(u32, W * H), step(&w, &buf, &snap)); // nothing known: everything
    try expectEqual(@as(u32, 0), step(&w, &buf, &snap));
    w.ptr[0].x += 7;
    try expect(step(&w, &buf, &snap) <= 2 * 4 * 4);
    var ref: [W * H]u8 = undefined;
    whole(&w, &ref);
    try expect(std.mem.eql(u8, &ref, &buf));
}

test "random edits: painting the damage equals a whole repaint, every step" {
    var w: World = .{};
    var buf: [W * H]u8 = undefined;
    var ref: [W * H]u8 = undefined;
    var snap: damage.Snap = .{};
    @memset(&buf, 0);
    _ = step(&w, &buf, &snap);
    var prng = std.Random.DefaultPrng.init(0x6E35);
    const r = prng.random();
    for (0..300) |_| {
        switch (r.uintLessThan(u8, 6)) {
            0 => w.ptr[0].x = r.intRangeAtMost(i16, -4, W),
            1 => w.wins[r.uintLessThan(u8, 2)][0].x = r.intRangeAtMost(i16, -20, W),
            2 => w.wins[r.uintLessThan(u8, 2)][0].y = r.intRangeAtMost(i16, -10, H),
            3 => std.mem.swap(u16, &w.order[0], &w.order[1]), // the other window topped
            4 => w.desk[1].state ^= obj.SELECTED,
            else => w.wins[r.uintLessThan(u8, 2)][1].x = r.intRangeAtMost(i16, -8, 40),
        }
        _ = step(&w, &buf, &snap);
        whole(&w, &ref);
        try expect(std.mem.eql(u8, &ref, &buf));
    }
}

// The text view scrolled sideways (Matt on the board, 9 Nov 2026): a row WIDER than its window
// spans both clip edges before and after a step, so its clipped extent is the same and its
// text, size and type are too. Only its position says it moved.
fn wideRow(w: *World, x: i16) void {
    w.wins[0][1] = .{ .next = 0, .ty = obj.G_STRING, .spec = .{ .str = "NAME.EXT   12345 09-12-26" }, .x = x, .y = 4, .w = 75, .h = 5 };
}

test "a clipped row that scrolled sideways inside its window is repainted (the damage sees its position)" {
    var w: World = .{};
    var buf: [W * H]u8 = undefined;
    var ref: [W * H]u8 = undefined;
    var snap: damage.Snap = .{};
    @memset(&buf, 0);
    wideRow(&w, -3);
    _ = step(&w, &buf, &snap);
    wideRow(&w, -6); // one character cell (3 px here) left: the clipped extent is unchanged
    try expect(step(&w, &buf, &snap) > 0);
    whole(&w, &ref);
    try expect(std.mem.eql(u8, &ref, &buf));
}

test "an external layer is never painted over, but the pointer above it is" {
    var w: World = .{};
    var buf: [W * H]u8 = undefined;
    @memset(&buf, 0);
    const dlg_r: Rect = .{ .x = 20, .y = 20, .w = 30, .h = 20 };
    var s: scene.Scene = .{};
    s.add(.{ .key = 1, .tree = &w.desk });
    s.add(.{ .key = 50, .external = true, .cover = .{ dlg_r, .{}, .{}, .{} }, .n_cover = 1 });
    w.ptr[0].spec = .{ .image = &w.image };
    w.ptr[0].x = 24;
    w.ptr[0].y = 24;
    s.add(.{ .key = 99, .tree = &w.ptr });
    s.measure(&LOOK);
    var cv = canvas.Canvas.init(&buf, W, W, H);
    cv.setClip(dlg_r);
    cv.fill(dlg_r, 77); // the old code's dialog
    var d: rect.RectList = .{};
    d.add(SCREEN);
    var st: compose.Stats = .{};
    cv.setClip(SCREEN);
    compose.compose(&cv, &LOOK, &s, &d, &st);
    try expectEqual(PAL[1], buf[24 * W + 24]); // the arrow, over the dialog
    try expectEqual(@as(u8, 77), buf[30 * W + 40]); // the dialog, untouched
    try expect(buf[10 * W + 10] != 77 and buf[10 * W + 10] != 0); // the desktop around it
}
