// Native tests of the object renderer (draw.zig, paint.zig, paint_icon.zig): what lands
// where, the flat and 3D looks, and that the clip and extent() hold.
const std = @import("std");
const obj = @import("obj.zig");
const draw = @import("draw.zig");
const L = @import("look.zig");
const canvas = @import("canvas.zig");
const rect = @import("rect.zig");
const Object = obj.Object;
const Rect = rect.Rect;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

const W = 64;
const H = 48;
const BG: u8 = 99;
// A font whose every glyph is a solid 2x3 block: text shows as its cells.
const solid = [_]u8{0xC0} ** (256 * 3);
const FONT: canvas.Font = .{ .w = 2, .h = 3, .data = &solid };
const PAL = [16]u8{ 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 };
const FLAT: L.Look = .{ .pal = PAL, .font = &FONT, .small = &FONT };
const TOS4: L.Look = .{ .pal = PAL, .font = &FONT, .small = &FONT, .three_d = true };

fn fresh(buf: *[W * H]u8) canvas.Canvas {
    @memset(buf, BG);
    return canvas.Canvas.init(buf, W, W, H);
}
fn px(buf: *const [W * H]u8, x: usize, y: usize) u8 {
    return buf[y * W + x];
}

const white_box = obj.boxSpec(0, 1, obj.colorWord(1, 1, true, 7, 0)); // black border, solid white
const tree = [_]Object{
    .{ .head = 1, .tail = 2, .ty = obj.G_BOX, .spec = .{ .box = white_box }, .x = 4, .y = 4, .w = 40, .h = 30 },
    .{ .next = 2, .ty = obj.G_STRING, .spec = .{ .str = "AB" }, .x = 2, .y = 2, .w = 8, .h = 5 },
    .{ .next = 0, .ty = obj.G_BUTTON, .flags = obj.FL3DACT | obj.EXIT, .spec = .{ .str = "X" }, .x = 10, .y = 14, .w = 12, .h = 8 },
};

test "a box, a string and a button land where the tree says (flat look)" {
    var buf: [W * H]u8 = undefined;
    var c = fresh(&buf);
    draw.draw(&c, &FLAT, &tree, 0, draw.MAX_DEPTH);
    try expectEqual(PAL[1], px(&buf, 4, 4)); // border, black
    try expectEqual(PAL[0], px(&buf, 5, 5)); // interior, white
    try expectEqual(PAL[1], px(&buf, 6, 7)); // the string's first cell (y centred: 6 + 1)
    try expectEqual(PAL[1], px(&buf, 13, 17)); // an EXIT button's 2-px outside border
    try expectEqual(BG, px(&buf, 45, 4)); // nothing right of the box
}

test "the 3D look: a grey face, a pushed activator, the 2-pixel outset" {
    var buf: [W * H]u8 = undefined;
    var c = fresh(&buf);
    draw.draw(&c, &TOS4, &tree, 0, draw.MAX_DEPTH);
    const bx = 4 + 10;
    const by = 4 + 14;
    try expectEqual(PAL[1], px(&buf, bx - 3, by - 3)); // the black frame, outside the outset
    try expectEqual(PAL[0], px(&buf, bx - 2, by - 2)); // light edge top-left
    try expectEqual(PAL[9], px(&buf, bx + 12 + 1, by + 8 + 1)); // dark edge bottom-right
    try expectEqual(PAL[8], px(&buf, bx + 1, by + 1)); // the face
    var t2 = tree;
    t2[2].state = obj.SELECTED;
    c = fresh(&buf);
    draw.draw(&c, &TOS4, &t2, 0, draw.MAX_DEPTH);
    try expectEqual(PAL[9], px(&buf, bx - 2, by - 2)); // pushed: the edges swap
}

test "selected flat objects are inverted, HIDETREE is not drawn" {
    var buf: [W * H]u8 = undefined;
    var c = fresh(&buf);
    var t2 = tree;
    t2[1].state = obj.SELECTED;
    t2[2].flags |= obj.HIDETREE;
    draw.draw(&c, &FLAT, &t2, 0, draw.MAX_DEPTH);
    try expectEqual(PAL[0], px(&buf, 6, 7)); // white text on the black bar
    try expectEqual(PAL[1], px(&buf, 13, 7)); // the bar fills the string's box
    try expectEqual(PAL[0], px(&buf, 13, 17)); // no button: the box's white
}

test "nothing outside the clip, and every pixel inside extent()" {
    var buf: [W * H]u8 = undefined;
    var c = fresh(&buf);
    c.setClip(.{ .x = 10, .y = 10, .w = 9, .h = 9 });
    draw.draw(&c, &TOS4, &tree, 0, draw.MAX_DEPTH);
    for (buf, 0..) |v, i| if (v != BG) try expect(c.clip.contains(@intCast(i % W), @intCast(i / W)));
    var full = fresh(&buf);
    var t2 = tree;
    t2[2].state = obj.OUTLINED | obj.SHADOWED | obj.CHECKED;
    draw.draw(&full, &TOS4, &t2, 2, 0); // the button alone
    const e = draw.extent(&TOS4, &t2[2], obj.offset(&t2, 2).?);
    for (buf, 0..) |v, i| if (v != BG) try expect(e.contains(@intCast(i % W), @intCast(i / W)));
}

test "CLIPKIDS confines children to the parent's box" {
    var buf: [W * H]u8 = undefined;
    var c = fresh(&buf);
    var t2 = tree;
    t2[0].flags = obj.CLIPKIDS;
    t2[1].x = 36; // the string now runs past the right edge (x 40..48)
    draw.draw(&c, &FLAT, &t2, 0, draw.MAX_DEPTH);
    try expectEqual(BG, px(&buf, 45, 7));
    try expectEqual(PAL[1], px(&buf, 40, 7));
}

test "an icon: mask in white, data in black, the label under it, swapped when selected" {
    var buf: [W * H]u8 = undefined;
    var c = fresh(&buf);
    const ib: obj.IconBlk = .{ .mask = &[_]u8{ 0xF0, 0xF0 }, .data = &[_]u8{ 0x80, 0x00 }, .w = 4, .h = 2, .text = "A", .tx = 0, .ty = 3, .tw = 6, .th = 4 };
    var t = [_]Object{.{ .ty = obj.G_ICON, .spec = .{ .icon = &ib }, .x = 2, .y = 2, .w = 6, .h = 7 }};
    draw.draw(&c, &FLAT, &t, 0, 0);
    try expectEqual(PAL[1], px(&buf, 2, 2));
    try expectEqual(PAL[0], px(&buf, 3, 2));
    try expectEqual(BG, px(&buf, 6, 2)); // outside the mask: transparent
    try expectEqual(PAL[0], px(&buf, 2, 5)); // label box, white
    t[0].state = obj.SELECTED;
    draw.draw(&c, &FLAT, &t, 0, 0);
    try expectEqual(PAL[0], px(&buf, 2, 2));
    try expectEqual(PAL[1], px(&buf, 3, 2));
}
