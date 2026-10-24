// --------------------------------------------------------------------------
// tcb1_mirror.zig against the shifter itself: every row a TCB #1 frame has
// (both odd top lines, the 230-byte lines at all four starts mod 8, the intro's
// 160-byte lines) from each of the part's 16 bases, over memory that changes
// between frames, must be what st_show's conversion makes of the same bytes:
// a blank row, then st.groupToChunky of each group, clipped to [lo, hi).
// Run through apps/zig/scene_tests.zig.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("st.zig");
const rows_ = @import("st_rows.zig");
const M = @import("tcb1_mirror.zig");

const BASE: u32 = 0x8000;
const TOP: u32 = 0x80000;
const PW = rows_.PW;
const PH = rows_.PH;
// tcb1.zig BASES ($DF5E), as the disk has them
const BASES = [_]u32{ 0x70000, 0x70700, 0x70300, 0x70900, 0x70500, 0x70200, 0x70A00, 0x70100, 0x70600, 0x70F00, 0x70D00, 0x70800, 0x70E00, 0x70B00, 0x70400 };

var mem: [TOP - BASE]u8 align(4) = undefined;
var lend: [M.NEED]u8 align(4) = undefined;
var fb: [PW * PH]u8 align(4) = undefined;
var want: [PW]u8 = undefined;

/// What st_show.lineAt makes of `ln` in a blank row.
fn reference(r: *const st.Ram, ln: rows_.Row, out: *[PW]u8) void {
    @memset(out, 0);
    const g = rows_.groups(ln) orelse return;
    for (g.lo..g.hi + 1) |k| {
        var px: [16]u8 = undefined;
        st.groupToChunky(r.bytes(ln.addr + 8 * @as(u32, @intCast(k)), 8)[0..8], &px);
        for (px, 0..) |c, i| {
            const x = ln.x0 + 16 * @as(i32, @intCast(k)) + @as(i32, @intCast(i));
            if (x >= ln.lo and x < ln.hi) out[@intCast(x)] = c;
        }
    }
}

/// tcb1_show.zig's frames: fullscreen (rows 11..239) or the intro window.
fn frameRows(base: u32, full: bool, rows: *rows_.Rows) void {
    rows.* = [_]?rows_.Row{null} ** PH;
    if (!full) {
        for (0..200) |y| rows[40 + y] = .{ .addr = base + 160 * @as(u32, @intCast(y)), .x0 = 40, .lo = 40, .hi = 360 };
        return;
    }
    rows[11] = .{ .addr = base - 46, .x0 = -56, .lo = 26, .hi = 360 };
    rows[12] = .{ .addr = base + 136, .x0 = -60, .lo = 0, .hi = 355 };
    for (2..229) |k| rows[11 + k] = .{ .addr = base + 344 + 230 * @as(u32, @intCast(k - 2)), .x0 = -12, .lo = 0, .hi = 400 };
}

fn expectFrame(r: *const st.Ram, m: *const M.Mirror) !void {
    for (&m.rows, 0..) |*row, py| {
        if (row.*) |ln| reference(r, ln, &want) else @memset(&want, 0);
        try std.testing.expectEqualSlices(u8, &want, fb[py * PW ..][0..PW]);
    }
}

test "the mirror shows what the shifter makes of every TCB #1 row, as the bytes change" {
    var rng = std.Random.DefaultPrng.init(0x7583_1639);
    const rand = rng.random();
    rand.bytes(&mem);
    const r = st.Ram{ .base = BASE, .m = &mem };
    var m: M.Mirror = undefined;
    m.init(&lend);
    var had: [PH]bool = undefined;
    m.sync(&r);
    @memset(&fb, 0xAA); // what another screen left: the first present writes everything
    for (0..64) |f| {
        const full = f % 3 != 0;
        frameRows(BASES[f % BASES.len], full, &m.rows);
        try std.testing.expect(M.Mirror.covers(&m.rows));
        m.sync(&r);
        m.present(&fb, f == 0 or f == 33, &had);
        try expectFrame(&r, &m);
        // a VBL's writes: logo boxes (18 lines of 40 bytes, 230 apart), some at the ends
        for (0..4) |b| {
            const end = switch (b) {
                0 => M.R0 + 20,
                1 => M.R1 + 30,
                else => M.R0 + 18 * 230 + rand.uintLessThan(u32, M.BYTES - 18 * 230),
            };
            for (0..18) |k| {
                const hi = end - 230 * @as(u32, @intCast(k));
                for (hi - 40..hi) |a| if (a >= BASE and a < TOP) r.sb(@intCast(a), rand.int(u8));
            }
            m.touchBox(&r, end);
        }
    }
}

const T = @import("tcb1.zig");
const IMAGE = @embedFile("../../assets/screens/swedish_newyear/tcb_part.raw");

test "a TCB #1 VBL writes nothing in the region but the logo boxes touchBox follows" {
    @memset(&mem, 0);
    @memcpy(mem[0..IMAGE.len], IMAGE);
    const r = st.Ram{ .base = BASE, .m = &mem };
    var t: T.Tcb1 = undefined;
    t.init(&r);
    var m: M.Mirror = undefined;
    m.init(&lend);
    var had: [PH]bool = undefined;
    m.sync(&r);
    var full_seen = false;
    for (0..1500) |v| { // the intro, the fullscreen from VBL 605, the logo from 678
        const before = r.l(T.LAST_DRAW);
        t.vbl(&r);
        m.touchBox(&r, before);
        m.touchBox(&r, r.l(T.LAST_DRAW));
        try std.testing.expectEqualSlices(u8, r.bytes(M.R0, M.BYTES), m.shadow);
        if (v % 50 != 0 and v != 680) continue;
        full_seen = full_seen or t.fullscreen();
        frameRows(t.shown, t.fullscreen(), &m.rows);
        try std.testing.expect(M.Mirror.covers(&m.rows));
        m.present(&fb, true, &had);
        try expectFrame(&r, &m);
    }
    try std.testing.expect(full_seen and r.b(0xDF5D) != 0);
}

test "a row outside the region is refused" {
    var rows: rows_.Rows = [_]?rows_.Row{null} ** PH;
    rows[0] = .{ .addr = M.R1 - 64, .x0 = -12, .lo = 0, .hi = 400 };
    try std.testing.expect(!M.Mirror.covers(&rows));
    rows[0] = .{ .addr = M.R0 - 8, .x0 = 40, .lo = 40, .hi = 360 };
    try std.testing.expect(!M.Mirror.covers(&rows));
    rows[0] = null;
    try std.testing.expect(M.Mirror.covers(&rows));
}
