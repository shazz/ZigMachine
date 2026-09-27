// --------------------------------------------------------------------------
// TCB #2 against the REAL demo, byte for byte. The references are the original
// 68000 code run on Musashi (prototypes/snyd_re/tcb/m68run) from the static
// load: its frame 474 / 475 are Hatari's RAM dumps tcb2_f3397 / f3398 (screens
// and data), so every CRC32 below is of the demo's own memory:
//   init    after TCB #1's exit and TCB #2's set-up (tcb/init2.bin)
//   kN      after N passes of the main loop (VBL + its seven routines)
//   keys    100 passes, F1, 50, F3, 50, F2, 30
// Regions: lo $8000..$10B00, mid $10D66..$50600, hi $52600..$80000 -- all of
// the part but the stack and the saved palette ($10B00..$10D66, which the
// Musashi run fills differently) and the Dugger replay ($50600..$52600, which
// plays from its SNDH here). `win` / `pal` are prototypes/snyd_re/
// tcb2_expect.py's hashes of what the machine must show (the display model
// of the VBL and the Timer B chain). Run through apps/zig/scene_tests.zig.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("st.zig");
const tcb2 = @import("tcb2.zig");
const vbl = @import("tcb2_vbl.zig");

const IMAGE = @embedFile("../../assets/screens/swedish_newyear/tcb_part.raw");

var mem: [tcb2.TOP - tcb2.BASE]u8 = undefined;

fn fresh() st.Ram {
    @memset(&mem, 0);
    @memcpy(mem[0..IMAGE.len], IMAGE);
    const r = st.Ram{ .base = tcb2.BASE, .m = &mem };
    tcb2.init(&r);
    tcb2.resetKeyboard();
    return r;
}

fn crc(r: *const st.Ram, a: u32, n: usize) u32 {
    return std.hash.Crc32.hash(r.bytes(a, n));
}

const Expect = struct { shown: u32, screen: u32, lo: u32, mid: u32, hi: u32 };

fn check(r: *const st.Ram, e: Expect) !void {
    try std.testing.expectEqual(e.shown, r.l(tcb2.DRAWN));
    try std.testing.expectEqual(e.screen, crc(r, e.shown, st.SCREEN));
    try std.testing.expectEqual(e.lo, crc(r, 0x8000, 0x10B00 - 0x8000));
    try std.testing.expectEqual(e.mid, crc(r, 0x10D66, 0x50600 - 0x10D66));
    try std.testing.expectEqual(e.hi, crc(r, 0x52600, 0x80000 - 0x52600));
}

fn run(r: *const st.Ram, n: usize) tcb2.Shown {
    var s: tcb2.Shown = undefined;
    for (0..n) |_| s = tcb2.frame(r);
    return s;
}

test "TCB #2's set-up builds the original's tables, preshifts and screens" {
    const r = fresh();
    try check(&r, .{ .shown = 0x78300, .screen = 0x3f434536, .lo = 0x21572963, .mid = 0x3279041a, .hi = 0x9aca033a });
}

test "TCB #2 after 1, 2, 10, 100, 475 and 1000 passes is the original's memory" {
    const r = fresh();
    _ = run(&r, 1);
    try check(&r, .{ .shown = 0x70600, .screen = 0xcfb96a18, .lo = 0x92efebfc, .mid = 0x38be19a2, .hi = 0xb0fb4eb4 });
    _ = run(&r, 1);
    try check(&r, .{ .shown = 0x78300, .screen = 0xbd6ddad2, .lo = 0x55afa0ec, .mid = 0x3279041a, .hi = 0x32d5d150 });
    _ = run(&r, 8);
    try check(&r, .{ .shown = 0x78300, .screen = 0xe6967cdf, .lo = 0x9138d372, .mid = 0x3279041a, .hi = 0x38eec04e });
    _ = run(&r, 90);
    try check(&r, .{ .shown = 0x78300, .screen = 0x4c0d2721, .lo = 0x6e699a29, .mid = 0x3279041a, .hi = 0xe8ce20ab });
    _ = run(&r, 375);
    try check(&r, .{ .shown = 0x70600, .screen = 0x27033f2c, .lo = 0x3f56e523, .mid = 0x38be19a2, .hi = 0x83fbc174 });
    _ = run(&r, 525);
    try check(&r, .{ .shown = 0x78300, .screen = 0x62c7ee9f, .lo = 0xf72da442, .mid = 0x3279041a, .hi = 0xc75df922 });
}

test "F1 / F2 set the scroller's speed and F3 restarts Dugger at subtune 2" {
    const r = fresh();
    _ = run(&r, 100);
    try std.testing.expectEqual(@as(?u8, null), tcb2.key(&r, 0));
    _ = run(&r, 50);
    try std.testing.expectEqual(@as(?u8, 2), tcb2.key(&r, 2));
    _ = run(&r, 50);
    try std.testing.expectEqual(@as(?u8, null), tcb2.key(&r, 1));
    _ = run(&r, 30);
    try check(&r, .{ .shown = 0x78300, .screen = 0x68c4415a, .lo = 0xff267bb4, .mid = 0x3279041a, .hi = 0xbdd730b5 });
    try std.testing.expectEqual(@as(u32, 0x4B0), r.l(0xC136));
}

test "a function key acts once until another one is pressed" {
    const r = fresh();
    _ = run(&r, 2);
    try std.testing.expectEqual(@as(?u8, 3), tcb2.key(&r, 3));
    _ = run(&r, 2);
    try std.testing.expectEqual(@as(?u8, null), tcb2.key(&r, 3));
}

/// tcb2_expect.py's `win` and `pal` of the frame `s` describes.
fn hashes(r: *const st.Ram, s: tcb2.Shown) [2][8]u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    var row: [320]u8 = undefined;
    for (0..200) |y| {
        st.lineToChunky(r.bytes(s.screen + st.LINE * @as(u32, @intCast(y)), st.LINE), &row);
        h.update(&row);
    }
    var out: [2][8]u8 = undefined;
    out[0] = h.finalResult()[0..8].*;
    var pal: [200][16]u16 = undefined;
    var top: u16 = undefined;
    var bottom: u16 = undefined;
    tcb2.palettes(r, s, &pal, &top, &bottom);
    var hp = std.crypto.hash.sha2.Sha256.init(.{});
    for (0..280) |py| {
        const y = @as(i32, @intCast(py)) - 40;
        for (0..16) |i| {
            const w = if (y < 0) top else if (y >= 200) bottom else pal[@intCast(y)][i];
            var b: [4]u8 = undefined;
            std.mem.writeInt(u32, &b, st.color(w), .little);
            hp.update(&b);
        }
    }
    out[1] = hp.finalResult()[0..8].*;
    return out;
}

fn expectHex(want: []const u8, got: [8]u8) !void {
    var buf: [16]u8 = undefined;
    _ = try std.fmt.bufPrint(&buf, "{x}", .{&got});
    try std.testing.expectEqualStrings(want, &buf);
}

test "the frames show the original's screen and colour registers (rasters, fade, chain)" {
    const r = fresh();
    const cases = [_]struct { n: usize, win: []const u8, pal: []const u8 }{
        .{ .n = 1, .win = "a00d54643c2275d7", .pal = "e8c612031a88791c" },
        .{ .n = 100, .win = "ddb4a7dfd31c04d2", .pal = "6a852db5a7479bd3" },
        .{ .n = 112, .win = "776a125ab8c55645", .pal = "1b0f3af63210151d" },
        .{ .n = 475, .win = "63cc71ce5464d354", .pal = "5d7595f3a11e3a9e" },
    };
    var done: usize = 0;
    for (cases) |c| {
        const s = run(&r, c.n - done);
        done = c.n;
        const h = hashes(&r, s);
        try expectHex(c.win, h[0]);
        try expectHex(c.pal, h[1]);
    }
}
