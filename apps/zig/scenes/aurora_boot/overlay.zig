// --------------------------------------------------------------------------
// AURORA BOOT: the star plane played back pixel for pixel (tools/boot/aurora_overlay.py).
//
// The baker drew every 60 Hz frame of the star plane (the stars as one dot each, the falcon's wire, the name) with
// the cart's own integer drawing and kept, per frame, only the bytes that change: u16 LE count, then count x
// (u16 LE offset, u8 palette entry), once per 64 K SECTION of the plane (two for cart 161's 400x280 raster, one
// for a 320x200 window: an offset is u16 within its section). The cart writes them and nothing else: no clear, no lines, no seek. The
// colours (the wire's and the name's alpha, the fade) stay palette writes (colours.zig), from SCALARS.
// Byte loads only (embedded data is not aligned). No ZigOS import: it tests natively.
// --------------------------------------------------------------------------
const std = @import("std");

pub const PLANE: u32 = 320 * 200;

/// A u16 LE at any byte. The high byte is read through a volatile pointer so LLVM cannot merge the two byte loads
/// into one unaligned 16-bit load: half the records sit at odd addresses, and a misaligned load traps on the board
/// (~210 cycles; frame_cost counted 300 a frame at 400x280 before this).
inline fn le16(d: []const u8, i: u32) u32 {
    const hi: *const volatile u8 = &d[i + 1];
    return @as(u32, d[i]) | @as(u32, hi.*) << 8;
}

/// The 320x200 window's player (G2, cart 161 until 27 Nov; the tests below use it).
pub const Overlay = OverlayFor(PLANE);

/// The player for a plane of `plane_len` bytes: ceil(plane_len / 64 K) sections a frame.
pub fn OverlayFor(comptime plane_len: u32) type {
    const SECTIONS: u32 = (plane_len + 0xFFFF) >> 16;
    return struct {
        const Self = @This();
        data: []const u8,
        at: u32 = 0, // the next frame's list
        frame: u32 = 0, // the frame that list is for

        /// Apply frame `f`'s changes (the frames are played in order from 0; a frame already applied is a no-op).
        /// False when the list overruns the data or leaves the plane.
        pub fn play(self: *Self, plane: [*]u8, f: u32) bool {
            while (self.frame <= f) : (self.frame += 1) {
                if (self.at + 2 > self.data.len) return self.at == self.data.len; // past the last baked frame: nothing changes
                var s: u32 = 0;
                while (s < SECTIONS) : (s += 1) if (!self.section(plane, s << 16)) return false;
            }
            return true;
        }

        /// One section's list at `at`: u16 count, then (u16 offset from `base`, u8 entry) per byte.
        fn section(self: *Self, plane: [*]u8, base: u32) bool {
            const d = self.data;
            if (self.at + 2 > d.len) return false;
            const n = le16(d, self.at);
            const end = self.at + 2 + 3 * n;
            if (end > d.len) return false;
            var i = self.at + 2;
            while (i < end) : (i += 3) {
                const o: u32 = base + le16(d, i);
                if (o >= plane_len) return false;
                plane[o] = d[i + 2];
            }
            self.at = end;
            return true;
        }

        /// Back to frame 0: the caller clears the plane (the baked lists start from an empty one).
        pub fn restart(self: *Self) void {
            self.at = 0;
            self.frame = 0;
        }
    };
}

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

test "a two-section plane (cart 161's 400x280): the second list's offsets start at 64 K" {
    const BIG: u32 = 400 * 280;
    var plane = [_]u8{0} ** BIG;
    // f0: section 0 [5]=7, section 1 [65536 + 3]=9; f1: nothing, then section 1 [65536 + 46463 = BIG - 1]=1
    const data = [_]u8{ 1, 0, 5, 0, 7, 1, 0, 3, 0, 9, 0, 0, 1, 0, 0x7F, 0xB5, 1 };
    var ov = OverlayFor(BIG){ .data = &data };
    try std.testing.expect(ov.play(&plane, 1));
    try std.testing.expectEqual(@as(u8, 7), plane[5]);
    try std.testing.expectEqual(@as(u8, 9), plane[65536 + 3]);
    try std.testing.expectEqual(@as(u8, 1), plane[BIG - 1]);
    var past = OverlayFor(BIG){ .data = &[_]u8{ 0, 0, 1, 0, 0x80, 0xB5, 1 } }; // 65536 + 46464 = BIG: off the plane
    try std.testing.expect(!past.play(&plane, 0));
    var half = OverlayFor(BIG){ .data = &[_]u8{ 0, 0 } }; // the second section's count missing
    try std.testing.expect(!half.play(&plane, 0));
}
