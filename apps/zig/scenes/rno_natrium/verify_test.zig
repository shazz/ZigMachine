// --------------------------------------------------------------------------
// NATRIUM, checked byte for byte. Run through apps/zig/scene_tests.zig (the
// embeds resolve from apps/zig/). Every CRC32 below was produced by
// tools/private_tools/rno_natrium_expect.py from either
//   * the bit-exact Python reference models (re/*/ in the RE workspace), each
//     of which reproduced a Hatari RAM snapshot, or
//   * the RAM snapshots THEMSELVES: both 32000-byte screens at eight counters,
//     masking only what the snapshot caught half-drawn.
// --------------------------------------------------------------------------
const std = @import("std");
const A = @import("assets.zig");
const st = @import("st.zig");
const dots = @import("tunnel_dots.zig");
const box = @import("chunky_box.zig");
const envmap = @import("envmap.zig");
const twister = @import("twister.zig");
const T = @import("timeline.zig");

fn crc(b: []const u8) u32 {
    return std.hash.Crc32.hash(b);
}

fn crcWords(comptime N: usize, t: [N]u16) u32 {
    var b: [2 * N]u8 = undefined;
    for (t, 0..) |w, i| std.mem.writeInt(u16, b[2 * i ..][0..2], w, .big);
    return crc(&b);
}

var scratch: st.Screen = undefined;

test "generated tables equal the program's ($B751A, $B771A, $13D38)" {
    try std.testing.expectEqual(@as(u32, 0xF04A39A0), crcWords(256, A.pix_double));
    try std.testing.expectEqual(@as(u32, 0xDF3FB350), crcWords(256, A.pix_mirror));
    var r: [256]u16 = undefined;
    for (A.recip, 0..) |v, i| r[i] = @intCast(v);
    try std.testing.expectEqual(@as(u32, 0x3A629D54), crcWords(256, r));
}

test "dot tunnel: one pass, F = 20, odd field" {
    st.clear(&scratch);
    dots.pass(&scratch, 20, 1);
    try std.testing.expectEqual(@as(u32, 0xD00E8BA1), crc(&scratch));
}

test "chunky box: tunnel, wobble, rotozoom fields" {
    const cases = [_]struct { f: u16, p: u1, which: u8, want: u32 }{
        .{ .f = 203, .p = 0, .which = 0, .want = 0xB6CF7B5F },
        .{ .f = 236, .p = 0, .which = 1, .want = 0x11CFDE33 },
        .{ .f = 235, .p = 1, .which = 1, .want = 0x544C7BE9 },
        .{ .f = 187, .p = 0, .which = 2, .want = 0x1686A1A5 },
        .{ .f = 188, .p = 1, .which = 2, .want = 0xC5487D52 },
    };
    for (cases) |c| {
        st.clear(&scratch);
        switch (c.which) {
            0 => box.tunnel(&scratch, c.f, c.p),
            1 => box.wobble(&scratch, c.f, c.p),
            else => box.rotozoom(&scratch, c.f, c.p),
        }
        try std.testing.expectEqual(c.want, crc(&scratch));
    }
}

test "env objects: cube f 201, prism f 153 (chunky and planes)" {
    const cases = [_]struct { obj: []const u8, f: u16, chunky: u32, planes: u32 }{
        .{ .obj = A.cube, .f = 201, .chunky = 0xC06360CB, .planes = 0x8CDAB626 },
        .{ .obj = A.prism, .f = 153, .chunky = 0x5C0607C3, .planes = 0x860B939E },
    };
    for (cases) |c| {
        @memset(&envmap.chunky, 0);
        envmap.render(envmap.object(c.obj), c.f);
        try std.testing.expectEqual(c.chunky, crc(&envmap.chunky));
        st.clear(&scratch);
        envmap.c2p(&scratch, 0);
        try std.testing.expectEqual(c.planes, crc(&scratch));
    }
}

test "twister: 768 frames into two buffers, f 766 and 767" {
    var bufs: [2]st.Screen = undefined;
    for (&bufs) |*b| st.fillWhite(b);
    for (0..768) |f| {
        twister.greeting(&bufs[f & 1], 0x1201 + @as(u32, @intCast(f)));
        twister.draw(&bufs[f & 1], @intCast(f));
    }
    try std.testing.expectEqual(@as(u32, 0xD6D2A17C), crc(&bufs[0]));
    try std.testing.expectEqual(@as(u32, 0xBB59FD87), crc(&bufs[1]));
}

// The whole sequencer from counter 0, compared with Hatari's RAM at each
// snapshot counter: both screens, which one $CA5C points at, and $144A0.
const Snap = struct { counter: u32, a: u32, b: u32, front_is_b: bool, f: u16 };
const SNAPS = [_]Snap{
    .{ .counter = 0x435, .a = 0x765ED383, .b = 0xF35D3616, .front_is_b = false, .f = 885 },
    .{ .counter = 0x700, .a = 0xF3A13273, .b = 0x42576FEC, .front_is_b = false, .f = 204 },
    .{ .counter = 0xA00, .a = 0x393CC217, .b = 0x42576FEC, .front_is_b = false, .f = 237 },
    .{ .counter = 0xD00, .a = 0xFF3BB794, .b = 0xAD611824, .front_is_b = false, .f = 204 },
    .{ .counter = 0x1100, .a = 0x685261C1, .b = 0x4C265D01, .front_is_b = false, .f = 460 },
    .{ .counter = 0x1500, .a = 0xBB59FD87, .b = 0xD6D2A17C, .front_is_b = true, .f = 767 },
    .{ .counter = 0x1900, .a = 0x639F2AE9, .b = 0x6F7FC940, .front_is_b = false, .f = 156 },
    .{ .counter = 0x1C00, .a = 0xF32A5757, .b = 0x7C452920, .front_is_b = false, .f = 189 },
};

/// The same masks the expect script applies to the snapshot.
fn masked(s: *const st.Screen, counter: u32, is_front: bool) u32 {
    scratch = s.*;
    for (&scratch, 0..) |*b, i| {
        const line = i / st.LINE;
        const keep = switch (counter) {
            0x435 => if (is_front) (i % 8) >= 2 or line & 1 == 1 else line >= 72 and line < 128,
            0x700 => !is_front or !(line & 1 == 1 and line >= 20 and line < 180),
            else => true,
        };
        if (!keep) b.* = 0;
    }
    return crc(&scratch);
}

var seq: T.Seq = undefined;

test "the timeline reproduces all eight RAM snapshots" {
    seq.reset();
    for (SNAPS) |snap| {
        while (seq.counter < snap.counter) seq.tick();
        const front_is_b = seq.front == 1;
        errdefer std.debug.print("snapshot ${X}: f {d} front_is_b {}\n", .{ snap.counter, seq.f, front_is_b });
        try std.testing.expectEqual(snap.f, seq.f);
        try std.testing.expectEqual(snap.front_is_b, front_is_b);
        try std.testing.expectEqual(snap.a, masked(&T.screens[0], snap.counter, !front_is_b));
        try std.testing.expectEqual(snap.b, masked(&T.screens[1], snap.counter, front_is_b));
    }
}

test "the timeline ends at $1E00" {
    seq.reset();
    while (!seq.finished) {
        seq.tick();
        try std.testing.expect(seq.counter <= T.END);
    }
    try std.testing.expectEqual(T.END, seq.counter);
}
