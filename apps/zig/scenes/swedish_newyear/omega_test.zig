// --------------------------------------------------------------------------
// OMEGA against the REAL demo, byte for byte (prototypes/snyd_re/omega/
// test_refs.py). `init` is Hatari's RAM at the part's first VBL; vN is the
// original 68000 code run N VBLs from there on Musashi (m68omega, which
// reproduces Hatari's own dumps after 1, 99 and 1099 VBLs), its reads of YM
// registers 8..10 forced to levels() below, as this test feeds the meters.
// Regions: A $8000..$8282, B $8286..$8BC4, C $9C64..$7F000 -- the part but the
// VBL vector it saves, the replay (played from its SNDH here) and the stack.
// Run through apps/zig/scene_tests.zig.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("st.zig");
const omega = @import("omega.zig");
const init_part = @import("omega_init.zig").init;
const vbl = @import("omega_vbl.zig").vbl;

const IMAGE = @embedFile("../../assets/screens/swedish_newyear/omega_part.raw");

var mem: [omega.TOP - omega.BASE]u8 = undefined;

fn fresh() st.Ram {
    @memset(&mem, 0);
    @memcpy(mem[0..IMAGE.len], IMAGE);
    const r = st.Ram{ .base = omega.BASE, .m = &mem };
    init_part(&r);
    return r;
}

/// test_refs.py's levels(k): registers 8, 9, 10 for VBL k.
fn levels(k: usize) [3]u8 {
    const a: u8 = if (k % 23 < 3) @intCast(k % 7 + 8) else 12;
    const b: u8 = if (k % 31 < 2) @intCast(15 - k % 5) else if (k % 37 == 0) 0 else 9;
    const c: u8 = if (k % 5 == 0) @intCast(2 + k % 14) else 3;
    return .{ a, b, c };
}

fn check(r: *const st.Ram, want: [3]u32) !void {
    const regions = [3][2]u32{ .{ 0x8000, 0x8282 }, .{ 0x8286, 0x8BC4 }, .{ 0x9C64, 0x7F000 } };
    for (regions, want) |reg, crc| {
        try std.testing.expectEqual(crc, std.hash.Crc32.hash(r.bytes(reg[0], reg[1] - reg[0])));
    }
}

test "OMEGA's set-up leaves the screen, panel and logo frames Hatari shows" {
    const r = fresh();
    try check(&r, .{ 0x9cda9e4f, 0xb573f731, 0x1183b37a });
}

test "OMEGA after 1, 2, 100 and 1100 VBLs is the original code's memory" {
    const r = fresh();
    const want = [_]struct { n: usize, crc: [3]u32 }{
        .{ .n = 1, .crc = .{ 0xa2c82175, 0xb573f731, 0x895b5a24 } },
        .{ .n = 2, .crc = .{ 0xe0ffe03b, 0xb573f731, 0x42cb0152 } },
        .{ .n = 100, .crc = .{ 0x649062a7, 0xb573f731, 0x119243e8 } },
        .{ .n = 1100, .crc = .{ 0x4f749d36, 0xb573f731, 0xa6872d21 } },
    };
    var k: usize = 0;
    for (want) |w| {
        while (k < w.n) : (k += 1) vbl(&r, levels(k));
        try check(&r, w.crc);
    }
}

test "a silent voice lights nothing and a loud one lights its meter" {
    const r = fresh();
    vbl(&r, .{ 0, 15, 14 });
    const right_a: u32 = 0x77DF6;
    try std.testing.expectEqual(@as(u16, 0), r.w(right_a)); // voice A: level 0
    try std.testing.expectEqual(@as(u16, 0xFFFF), r.w(0x782F6 + 6 * 8)); // B: 7 groups
    try std.testing.expectEqual(@as(u16, 0), r.w(0x782F6 + 7 * 8)); // odd: no half
    try std.testing.expectEqual(@as(u16, 0xFF00), r.w(0x787F6 + 7 * 8)); // C 14: +8 px
}
