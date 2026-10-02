// The parts' native tests against prototypes/snyd90_re/oracle_expect.py: the
// CRC32 of a part's memory with its holes zeroed (what the port does not
// keep: the music, the VBL's flags), of the two screens, of the palette.
const std = @import("std");
const st = @import("../swedish_newyear/st.zig");

pub const Expect = struct { vbl: u32, mem: u32, a: u32, b: u32, pal: u32 };

/// [$1000, $70000) with every [lo, hi) of `holes` (ascending) read as zeros.
pub fn kept(r: *const st.Ram, holes: []const [2]u32) u32 {
    var h = std.hash.Crc32.init();
    var a: u32 = 0x1000;
    const zeros = [_]u8{0} ** 0x2000;
    for (holes) |hole| {
        h.update(r.bytes(a, hole[0] - a));
        var n = hole[1] - hole[0];
        while (n > 0) {
            const k = @min(n, zeros.len);
            h.update(zeros[0..k]);
            n -= k;
        }
        a = hole[1];
    }
    h.update(r.bytes(a, 0x70000 - a));
    return h.final();
}

pub fn check(r: *const st.Ram, e: Expect, holes: []const [2]u32, pal: [16]u16) !void {
    try std.testing.expectEqual(e.a, std.hash.Crc32.hash(r.bytes(0x70000, st.SCREEN)));
    try std.testing.expectEqual(e.b, std.hash.Crc32.hash(r.bytes(0x78000, st.SCREEN)));
    try std.testing.expectEqual(e.mem, kept(r, holes));
    var big: [16]u16 = undefined;
    for (&big, pal) |*o, c| o.* = std.mem.nativeToBig(u16, c);
    try std.testing.expectEqual(e.pal, std.hash.Crc32.hash(std.mem.sliceAsBytes(&big)));
}
