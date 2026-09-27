// --------------------------------------------------------------------------
// TCB #1 against the REAL demo. CRC32s of regions of Hatari RAM dumps of
// SNYD_89.MSA running TCB #1 (prototypes/snyd_re/hatari/): the delay-line
// counters give the VBL count since the set-up mod 400, so init + N VBLs must
// BE the dump:
//   tcb1_intro_a  N = 75, no logo yet
//   tcb1_main_b   N = 967, the logo drawn from VBL 938 on (mod 16: the only
//                 trace the first logo VBL leaves is which base it erased)
// Regions: the preshifts $49DCC (12 x $2D0), the noise $70000..$7EA62, the
// delay line and its counters $D8DA..$D96E, $DD30/$DD34, the base index.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("st.zig");
const T = @import("tcb1.zig");

const IMAGE = @embedFile("../../assets/screens/swedish_newyear/tcb_part.raw");

var mem: [T.TOP - T.BASE]u8 = undefined;

fn fresh(t: *T.Tcb1) st.Ram {
    @memset(&mem, 0);
    @memcpy(mem[0..IMAGE.len], IMAGE);
    const r = st.Ram{ .base = T.BASE, .m = &mem };
    t.init(&r);
    return r;
}

fn crc(r: *const st.Ram, a: u32, n: usize) u32 {
    return std.hash.Crc32.hash(r.bytes(a, n));
}

fn expectRegions(r: *const st.Ram, want: [5]u32) !void {
    try std.testing.expectEqual(want[0], crc(r, T.PRESHIFTS, 0x2D0 * 12));
    try std.testing.expectEqual(want[1], crc(r, T.NOISE, 0xEA62));
    try std.testing.expectEqual(want[2], crc(r, 0xD8DA, 0x94));
    try std.testing.expectEqual(want[3], crc(r, T.SHOWN, 8));
    try std.testing.expectEqual(want[4], crc(r, 0xDF9E, 4));
}

test "TCB #1: set-up + 75 VBLs is Hatari's intro" {
    var t: T.Tcb1 = undefined;
    const r = fresh(&t);
    for (0..75) |_| T.body(&r);
    try expectRegions(&r, .{ 0xe0b4080b, 0x896711c7, 0xd01a48ce, 0xd0c6a0af, 0x139cb3ff });
}

test "TCB #1: 967 VBLs, the logo on from 938, is Hatari's fullscreen" {
    var t: T.Tcb1 = undefined;
    const r = fresh(&t);
    for (1..968) |k| {
        r.sb(0xDF5D, if (k >= 938) 0xFF else 0);
        T.body(&r);
    }
    try expectRegions(&r, .{ 0xe0b4080b, 0x690e3232, 0x65449b22, 0xed5ea0a5, 0x35458353 });
}

test "TCB #1: at the SNDH's 315.08 samples a VBL, fullscreen from VBL 605, the logo from 678" {
    var t: T.Tcb1 = undefined;
    const r = fresh(&t);
    var full: ?usize = null;
    var logo: ?usize = null;
    for (1..800) |v| {
        t.vbl(&r);
        if (full == null and t.fullscreen()) full = v;
        if (logo == null and r.b(0xDF5D) != 0) logo = v;
    }
    try std.testing.expectEqual(@as(?usize, 605), full);
    try std.testing.expectEqual(@as(?usize, 678), logo);
    try std.testing.expectEqual(.top_sides, t.borders());
}

test "TCB #1: the speech loops ten times, then the music part for ever" {
    var t: T.Tcb1 = undefined;
    const r = fresh(&t);
    for (0..2000) |_| t.vbl(&r);
    try std.testing.expectEqual(@as(u32, 17), r.l(0xDF58));
    try std.testing.expectEqual(@as(u32, 0x33340), t.a4);
    try std.testing.expectEqual(@as(u32, 0x41234), r.l(0xEA9C));
}
