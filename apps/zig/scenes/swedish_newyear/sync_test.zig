// --------------------------------------------------------------------------
// SYNC #1 and #2 against the REAL demo, byte for byte. Every CRC32 below is of
// a region of a Hatari RAM dump of SNYD_89.MSA running (prototypes/snyd_re/
// hatari/*.bin, taken paused on a VBL):
//   sync1_it0    the first iteration, after the part's set-up
//   sync1_v1394  100 iterations later       sync1_v2794  1500 iterations later
//   sync2_start  SYNC #2 drawn, its VBL not yet run; sync2_v1648 300 VBLs later
// Run through apps/zig/scene_tests.zig.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("st.zig");
const sync1 = @import("sync1.zig");
const sync2 = @import("sync2.zig");

const IMAGE = @embedFile("../../assets/screens/swedish_newyear/sync_part.raw");

var mem: [sync1.TOP - sync1.BASE]u8 = undefined;

fn fresh() st.Ram {
    @memset(&mem, 0);
    @memcpy(mem[0..IMAGE.len], IMAGE);
    const r = st.Ram{ .base = sync1.BASE, .m = &mem };
    sync1.init(&r);
    return r;
}

fn crc(r: *const st.Ram, a: u32, n: usize) u32 {
    return std.hash.Crc32.hash(r.bytes(a, n));
}

const Expect = struct { a: u32, b: u32, rasters: u32, scroll: u32, letters: u32, logo: u32, banner: u32 };

fn check(r: *const st.Ram, e: Expect) !void {
    try std.testing.expectEqual(e.a, crc(r, 0x70000, st.SCREEN));
    try std.testing.expectEqual(e.b, crc(r, 0x78000, st.SCREEN));
    try std.testing.expectEqual(e.rasters, crc(r, sync1.RASTERS, 400));
    try std.testing.expectEqual(e.scroll, crc(r, 0x22800, 0x90));
    try std.testing.expectEqual(e.letters, crc(r, 0x22BC6, 0x40));
    try std.testing.expectEqual(e.logo, crc(r, 0x208C6, 24 * 0x30));
    try std.testing.expectEqual(e.banner, crc(r, 0x28534, 0x20));
}

test "SYNC #1's set-up leaves the preshifts and tables the original makes" {
    const r = fresh();
    try check(&r, .{ .a = 0x5bd12871, .b = 0x5bd12871, .rasters = 0xa4e909aa, .scroll = 0xd530512e, .letters = 0xec1126e9, .logo = 0xa15c5830, .banner = 0x7e4a2163 });
    try std.testing.expectEqual(@as(u32, 0x6d5e2136), crc(&r, 0x3C600, 51 * 0x840)); // font
    try std.testing.expectEqual(@as(u32, 0x43c49c30), crc(&r, 0x37FB0, 0x10E0 * 4)); // logo
    try std.testing.expectEqual(@as(u32, 0xbe8cdb3c), crc(&r, sync1.LINE_TAB, 402));
}

test "SYNC #1 after 100 and 1500 iterations is Hatari's RAM" {
    const r = fresh();
    for (0..100) |_| _ = sync1.iteration(&r);
    try check(&r, .{ .a = 0x21941463, .b = 0x58b5c3c3, .rasters = 0xea11d79a, .scroll = 0x79eaa3e2, .letters = 0x3e6dc6cb, .logo = 0xed7a4479, .banner = 0x6be12d4d });
    for (0..1400) |_| _ = sync1.iteration(&r);
    try check(&r, .{ .a = 0xaa02584f, .b = 0xbad4c784, .rasters = 0x0c20b7da, .scroll = 0x68b0b78f, .letters = 0xbdc49a43, .logo = 0xcd65dc62, .banner = 0x54fcd6d9 });
}

test "an iteration shows the buffer the previous one flipped to" {
    const r = fresh();
    _ = sync1.iteration(&r);
    const flipped = r.l(sync1.DRAW);
    const shown = sync1.iteration(&r);
    try std.testing.expectEqual(flipped, shown.screen);
    try std.testing.expect(r.l(sync1.DRAW) != flipped);
}

test "SYNC #2 draws the tiled screen and walks the sequencer as the original" {
    const r = fresh();
    for (0..50) |_| _ = sync1.iteration(&r);
    const scr = sync2.enter(&r);
    try std.testing.expectEqual(@as(u32, 0x526c1e8a), crc(&r, scr, st.SCREEN));
    var flashes: usize = 0;
    for (0..300) |_| {
        if (sync2.vbl(&r) != 0) flashes += 1;
    }
    try std.testing.expectEqual(@as(u32, 0x2C830), r.l(0x2D1AE));
    try std.testing.expectEqual(@as(u32, 0x2CADA), r.l(0x2D1BA));
    try std.testing.expectEqual(@as(u32, 0x2D066), r.l(0x2D1C6));
    try std.testing.expect(flashes > 0);
}
