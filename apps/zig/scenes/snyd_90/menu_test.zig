// --------------------------------------------------------------------------
// The menu against the REAL demo, byte for byte. Every CRC32 is of a region of
// a Hatari RAM dump of SNYD_90.MSA (prototypes/snyd90_re/hatari/menu_it*.bin,
// taken paused at $10A8, the main loop's `jsr $29E0`, of iteration N; N read
// from $29CA, which counts the idle iterations down from 500). Regions: both
// screens, the phase variables, the four walkers, the position ring, the
// scroller's variables and its four buffers, the clear lists.
// Iterations 530 (mid-slide) and 999 (after the swap to the SYNC letters)
// cover the whole phase machine. prototypes/snyd90_re/menu_expect.py prints these.
// Run through apps/zig/scene_tests.zig.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("../swedish_newyear/st.zig");
const menu = @import("menu.zig");

const IMAGE = @embedFile("../../assets/screens/snyd_90/menu.raw");

var mem: [menu.TOP - menu.BASE]u8 = undefined;

const Expect = struct { it: u32, a: u32, b: u32, phases: u32, walkers: u32, ring: u32, scroll: u32, bufs: u32, lists: u32 };

const EXPECT = [_]Expect{
    .{ .it = 0, .a = 0x5bd12871, .b = 0x5bd12871, .phases = 0xca372b0d, .walkers = 0x533130d1, .ring = 0x5ff6f7e2, .scroll = 0x3b393b16, .bufs = 0xec6c30a8, .lists = 0x2fe1c554 },
    .{ .it = 99, .a = 0xae7d2d4c, .b = 0x3b26541a, .phases = 0x15d5de9c, .walkers = 0x35314dba, .ring = 0xe6266cfe, .scroll = 0x17735a22, .bufs = 0x71c21240, .lists = 0x5da61deb },
    .{ .it = 530, .a = 0x805574c3, .b = 0x93554d28, .phases = 0xa3d81698, .walkers = 0x7a5f84b0, .ring = 0x7132e9ce, .scroll = 0x909ae0f9, .bufs = 0x79bde14a, .lists = 0x460c0c45 },
    .{ .it = 999, .a = 0xa2f21f53, .b = 0xba447b7c, .phases = 0x41bf0048, .walkers = 0x1442830e, .ring = 0x4f666d75, .scroll = 0x80db7d87, .bufs = 0x2eec9b11, .lists = 0x4f82a5a3 },
};

fn fresh() st.Ram {
    @memset(&mem, 0);
    @memcpy(mem[0..IMAGE.len], IMAGE);
    const r = st.Ram{ .base = menu.BASE, .m = &mem };
    menu.init(&r);
    return r;
}

fn crc(r: *const st.Ram, a: u32, n: usize) u32 {
    return std.hash.Crc32.hash(r.bytes(a, n));
}

fn check(r: *const st.Ram, e: Expect) !void {
    try std.testing.expectEqual(e.a, crc(r, menu.SCREEN_A, st.SCREEN));
    try std.testing.expectEqual(e.b, crc(r, menu.SCREEN_B, st.SCREEN));
    try std.testing.expectEqual(e.phases, crc(r, 0x29CA, 22));
    try std.testing.expectEqual(e.walkers, crc(r, 0x2F68, 0x78));
    try std.testing.expectEqual(e.ring, crc(r, 0x2D92, 0x6C));
    try std.testing.expectEqual(e.scroll, crc(r, 0x16F6, 0x22));
    try std.testing.expectEqual(e.bufs, crc(r, 0x38C4, 0x4100));
    try std.testing.expectEqual(e.lists, crc(r, 0x3818, 0x34));
}

test "the menu matches Hatari's RAM after 0, 99, 530 and 999 iterations" {
    const r = fresh();
    var done: u32 = 0;
    for (EXPECT) |e| {
        while (done < e.it) : (done += 1) _ = menu.iteration(&r);
        try check(&r, e);
    }
}

test "an iteration draws the other screen than the one before" {
    const r = fresh();
    const first = menu.iteration(&r);
    const second = menu.iteration(&r);
    try std.testing.expect(first != second);
    try std.testing.expect(first == menu.SCREEN_A or first == menu.SCREEN_B);
}
