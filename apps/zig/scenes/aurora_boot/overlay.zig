// --------------------------------------------------------------------------
// AURORA BOOT: the star plane played back pixel for pixel (tools/boot/aurora_overlay.py).
//
// The baker drew every 60 Hz frame of the star plane (the stars as one dot each, the falcon's wire, the name) with
// the cart's own integer drawing and kept, per frame, only the bytes that change: u16 LE count, then count x
// (u16 LE offset, u8 palette entry). The cart writes them and nothing else: no clear, no lines, no seek. The
// colours (the wire's and the name's alpha, the fade) stay palette writes (colours.zig), from SCALARS.
// Byte loads only (embedded data is not aligned). No ZigOS import: it tests natively.
// --------------------------------------------------------------------------
const std = @import("std");

pub const PLANE: u32 = 320 * 200;

pub const Overlay = struct {
    data: []const u8,
    at: u32 = 0, // the next frame's list
    frame: u32 = 0, // the frame that list is for

    /// Apply frame `f`'s changes (the frames are played in order from 0; a frame already applied is a no-op).
    /// False when the list overruns the data or leaves the plane.
    pub fn play(self: *Overlay, plane: [*]u8, f: u32) bool {
        while (self.frame <= f) : (self.frame += 1) {
            if (self.at + 2 > self.data.len) return self.at == self.data.len; // past the last baked frame: nothing changes
            const d = self.data;
            const n: u32 = @as(u32, d[self.at]) | @as(u32, d[self.at + 1]) << 8;
            const end = self.at + 2 + 3 * n;
            if (end > d.len) return false;
            var i = self.at + 2;
            while (i < end) : (i += 3) {
                const o: u32 = @as(u32, d[i]) | @as(u32, d[i + 1]) << 8;
                if (o >= PLANE) return false;
                plane[o] = d[i + 2];
            }
            self.at = end;
        }
        return true;
    }

    /// Back to frame 0: the caller clears the plane (the baked lists start from an empty one).
    pub fn restart(self: *Overlay) void {
        self.at = 0;
        self.frame = 0;
    }
};

test "each frame writes its own bytes once, in order; a replay starts again from the first list" {
    var plane = [_]u8{0} ** PLANE;
    const data = [_]u8{ 1, 0, 5, 0, 7, 2, 0, 5, 0, 0, 0x40, 0x01, 16 }; // f0: [5]=7; f1: [5]=0, [320]=16
    var ov = Overlay{ .data = &data };
    try std.testing.expect(ov.play(&plane, 0));
    try std.testing.expectEqual(@as(u8, 7), plane[5]);
    try std.testing.expect(ov.play(&plane, 0)); // the same frame again (the last frame repeats): nothing new
    try std.testing.expect(ov.play(&plane, 1));
    try std.testing.expectEqual(@as(u8, 0), plane[5]);
    try std.testing.expectEqual(@as(u8, 16), plane[320]);
    try std.testing.expect(ov.play(&plane, 5)); // past the last list: the plane holds
    ov.restart();
    try std.testing.expect(ov.play(&plane, 0));
    try std.testing.expectEqual(@as(u8, 7), plane[5]);
}

test "a list that overruns the data or leaves the plane is refused" {
    var plane = [_]u8{0} ** PLANE;
    var ov = Overlay{ .data = &[_]u8{ 2, 0, 5, 0, 7 } };
    try std.testing.expect(!ov.play(&plane, 0));
    var off = Overlay{ .data = &[_]u8{ 1, 0, 0x80, 0xFA, 1 } }; // offset 64128 >= 64000
    try std.testing.expect(!off.play(&plane, 0));
    var odd = Overlay{ .data = &[_]u8{ 0, 0, 1 } }; // a stray byte after the last list
    try std.testing.expect(!odd.play(&plane, 1));
}
