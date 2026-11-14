// The screenshot's copy (shot_grab.zig) over a fake cart window: a mailbox as ZIGGY's firmware
// keeps it (cycles/bmailbox.h), a fake firmware that answers the freeze from the worker's naps,
// both pictures, and the desk mode's plane 0 and palette 0.
const std = @import("std");
const bus = @import("bus.zig");
const mc = @import("map_cart.zig");
const mm = @import("memmap");
const g = @import("shot_grab.zig");

const gpa = std.testing.allocator;
const CPU: u32 = 0x4000_0000;

/// The fake firmware: it stops after "its frame" on the first nap that finds the freeze asked.
pub const Fw = struct {
    pub var mb: ?[]u32 = null;
    pub var front: u32 = 0;
    pub var naps: u32 = 0;
    pub var answers = true;

    pub fn nap(ms: u32) void {
        _ = ms;
        naps += 1;
        const m = mb orelse return;
        if (!answers) return;
        if (m[g.MB_FREEZE] != 0 and m[g.MB_FROZEN] == 0) {
            m[g.MB_FRONT] = front;
            m[g.MB_FROZEN] = 1234;
        }
    }
};

/// The window's mailbox, pointing at two w x h pictures at word offsets fb0 and fb1.
pub fn mailbox(words: []u32, fb0: u32, fb1: u32, w: u32, h: u32) []u32 {
    const mb = words[words.len - mc.MB_BYTES / 4 ..];
    @memset(mb, 0);
    mb[0] = mc.MB_MAGIC;
    mb[1] = 2;
    mb[g.MB_FB0] = CPU + 4 * fb0;
    mb[g.MB_FB1] = CPU + 4 * fb1;
    mb[g.MB_PIC_W] = w;
    mb[g.MB_PIC_H] = h;
    mb[g.MB_CPU_BASE] = CPU;
    Fw.mb = mb;
    Fw.naps = 0;
    Fw.answers = true;
    return mb;
}

fn env(words: []u32) g.Env {
    return .{ .ddr = .{ .words = words }, .nap = Fw.nap, .freeze_ms = 50 };
}

fn rgb(r: u8, gr: u8, b: u8) u32 { // a picture word, {0, B, G, R}
    return @as(u32, b) << 16 | @as(u32, gr) << 8 | r;
}

test "the picture on screen is copied with the cart frozen, then let go; low-res columns undoubled" {
    var words = [_]u32{0} ** 512;
    const mb = mailbox(&words, 16, 64, 8, 3);
    for (words[64..][0..24], 0..) |*w, i| w.* = rgb(@intCast(i / 2), 0x80, 0xFF); // pairs: low res
    for (words[16..][0..24]) |*w| w.* = rgb(9, 9, 9); // the other picture: never copied
    Fw.front = 1;
    const s = try g.grab(gpa, env(&words), false);
    defer s.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 0), mb[g.MB_FREEZE]); // let go
    try std.testing.expect(Fw.naps >= 1);
    try std.testing.expectEqual(@as(u32, 4), s.w);
    try std.testing.expectEqual(@as(u32, 3), s.h);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0x80, 0xFF, 1, 0x80, 0xFF }, s.px[0..6]); // R, G, B
    try std.testing.expectEqualSlices(u8, &.{ 11, 0x80, 0xFF }, s.px[s.px.len - 3 ..]);
}

test "a picture with 1:1 detail keeps its columns and doubles its lines, as the TV shows it" {
    const raw = [_]u32{ rgb(1, 2, 3), rgb(1, 2, 3), rgb(4, 5, 6), rgb(7, 8, 9) }; // a medium pair
    const s = try g.fromPicture(gpa, &raw, 2, 2);
    defer s.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 2), s.w);
    try std.testing.expectEqual(@as(u32, 4), s.h);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 4, 5, 6, 7, 8, 9, 4, 5, 6, 7, 8, 9 }, s.px);
}

test "a firmware that never stops: a timeout, and the freeze is withdrawn" {
    var words = [_]u32{0} ** 512;
    const mb = mailbox(&words, 16, 64, 8, 3);
    Fw.answers = false;
    try std.testing.expectError(error.FreezeTimeout, g.grab(gpa, env(&words), false));
    try std.testing.expectEqual(@as(u32, 0), mb[g.MB_FREEZE]);
    try std.testing.expectEqual(@as(u32, 50), Fw.naps); // bounded: freeze_ms naps of 1 ms
}

test "no mailbox, or one pointing off the window: refused, nothing left frozen" {
    var words = [_]u32{0} ** 512;
    try std.testing.expectError(error.NoMailbox, g.grab(gpa, env(&words), false));
    const mb = mailbox(&words, 16, 500, 8, 3); // picture 1 runs into the mailbox
    Fw.front = 1;
    try std.testing.expectError(error.BadMailbox, g.grab(gpa, env(&words), false));
    try std.testing.expectEqual(@as(u32, 0), mb[g.MB_FREEZE]);
    mb[g.MB_FB1] = CPU + 4 * 16 + 2; // off a word
    try std.testing.expectError(error.BadMailbox, g.grab(gpa, env(&words), false));
    _ = mailbox(&words, 16, 64, 7, 3); // an odd width is no picture
    try std.testing.expectError(error.BadMailbox, g.grab(gpa, env(&words), false));
    _ = mailbox(&words, 16, 64, 1 << 20, 1 << 20); // a corrupt size sizes no allocation
    try std.testing.expectError(error.BadMailbox, g.grab(gpa, env(&words), false));
}

test "the desk: plane 0's bytes through palette 0, from FB_BASE as the scanout reads it" {
    const VB: u32 = 0x400; // the video region's word offset in the window
    const plane_off: u32 = mm.OFF_VRAM + 0x40; // a region offset, 8-aligned
    const n = VB + (plane_off + mm.DESK_FB_BYTES) / 4 + 64 + mc.MB_BYTES / 4;
    const words = try gpa.alloc(u32, n);
    defer gpa.free(words);
    @memset(words, 0);
    const mb = mailbox(words, 0, 0, 800, 280);
    mb[g.MB_PFB] = CPU + 4 * VB + mm.OFF_PFB; // the PFB itself lies past this window: only its address counts
    words[VB + mm.REG_FB_BASE / 4] = plane_off + 5; // low bits dropped: a beat
    for (0..256) |i| words[VB + mm.OFF_PAL / 4 + i] = 0xFF00_0000 | rgb(@intCast(i), @intCast(255 - i), 7);
    const plane = words[VB + plane_off / 4 ..][0 .. mm.DESK_FB_BYTES / 4];
    plane[0] = 0x0403_0201; // pixels 1, 2, 3, 4: byte 0 is the leftmost
    plane[plane.len - 1] = 0xFF00_0000;
    const s = try g.grab(gpa, env(words), true);
    defer s.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 0), mb[g.MB_FREEZE]);
    try std.testing.expect(s.desk);
    try std.testing.expectEqual(@as(u32, 640), s.w);
    try std.testing.expectEqual(@as(u32, 480), s.h);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 0 }, s.px[0..5]);
    try std.testing.expectEqual(@as(u8, 0xFF), s.px[s.px.len - 1]);
    try std.testing.expectEqualSlices(u8, &.{ 3, 252, 7 }, s.pal[9..12]); // entry 3: R, G, B, alpha dropped
}
