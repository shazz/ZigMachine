// The GFA PUNCH modes' read-out (keys 4 and 5), in rows the listing never draws: text
// at rows 16, 24 and 32 (under PTST's rows 0..15, above the sphere's top at row 46) and
// a tap strip on row 199, the counters as bits for apps/harness/gfa_punch_headless.mjs:
//   x 0  frames (16 bits)    x 16 finished (1)    x 17 pass (6)
//   x 23 tracing ms (24)     x 47 mode key (3)
// A 1 bit is colour 15 (&H772), a 0 black, in either plane.
//
//   16  <mode name>       TIME <s at 60 Hz>
//   24  NUCLEUS, ST Magazine GfA Punch
//   32  LINE nnn/153 | PASS nn/16      TRACE <s of tracing, the host's clock>
const zg = @import("zigos");
const gfa = @import("gfa.zig");

pub const TAP_ROW: u32 = 199;
pub const CREDIT = "NUCLEUS, ST Magazine GfA Punch";

pub const Target = union(enum) { st: *zg.LogicalFB, tc: zg.tc.Fb };

pub const Counters = struct {
    key: u32, // 4 or 5
    name: []const u8,
    frames: u32,
    finished: bool,
    pass: u32, // key 5: passes done; key 4: 0, then 1
    line: u32, // key 4: the loop's row 1..153
    trace_ms: u32, // 0 without the host's clock
    clocked: bool,
};

fn putStr(buf: []u8, at: usize, s: []const u8) usize {
    @memcpy(buf[at..][0..s.len], s);
    return at + s.len;
}

fn putNum(buf: []u8, at: usize, width: usize, n: u32) usize {
    var v = n;
    var i = width;
    while (i > 0) : (i -= 1) {
        buf[at + i - 1] = '0' + @as(u8, @intCast(v % 10));
        v /= 10;
    }
    return at + width;
}

/// Seconds with a tenth, from milliseconds: "0012.3".
fn putSecs(buf: []u8, at: usize, ms: u32) usize {
    var n = putNum(buf, at, 4, ms / 1000 % 10000);
    n = putStr(buf, n, ".");
    return putNum(buf, n, 1, ms / 100 % 10);
}

pub fn draw(zigos: *zg.ZigOS, t: Target, c: Counters) void {
    var buf: [40]u8 = [_]u8{' '} ** 40;
    _ = putStr(&buf, 0, c.name);
    var n = putStr(&buf, 27, "T ");
    _ = putSecs(&buf, n, c.frames * 50 / 3); // 16.67 ms a frame
    text(zigos, t, &buf, 16);
    buf = [_]u8{' '} ** 40;
    _ = putStr(&buf, 0, CREDIT);
    text(zigos, t, &buf, 24);
    buf = [_]u8{' '} ** 40;
    if (c.key == 4) {
        n = putStr(&buf, 0, "LINE ");
        n = putNum(&buf, n, 3, c.line);
        _ = putStr(&buf, n, "/153");
    } else {
        n = putStr(&buf, 0, "PASS ");
        n = putNum(&buf, n, 2, @min(c.pass + 1, 16));
        _ = putStr(&buf, n, "/16");
    }
    n = putStr(&buf, 19, "TRACE ");
    if (c.clocked) {
        n = putSecs(&buf, n, c.trace_ms);
        _ = putStr(&buf, n, " S");
    } else _ = putStr(&buf, n, "NO CLOCK");
    text(zigos, t, &buf, 32);
    tap(t, c);
}

fn text(zigos: *zg.ZigOS, t: Target, s: []const u8, y: u32) void {
    switch (t) {
        .st => |lfb| zigos.printText(lfb, s, 0, @intCast(y), 15, 0),
        .tc => |fb| {
            const ink = ink565();
            for (0..8) |r| {
                const row = fb.row(y + r);
                for (s, 0..) |ch, k| {
                    const g = zigos.system_font[@as(usize, ch) * 64 + r * 8 ..][0..8];
                    inline for (0..8) |b| row[k * 8 + b] = if (g[b] == 1) ink else 0;
                }
            }
        },
    }
}

fn ink565() u16 {
    const c = gfa.stRgb(gfa.PALETTE[15]);
    return zg.tc.rgb565(c[0], c[1], c[2]);
}

fn tap(t: Target, c: Counters) void {
    bits(t, 0, c.frames, 16);
    bits(t, 16, @intFromBool(c.finished), 1);
    bits(t, 17, c.pass, 6);
    bits(t, 23, c.trace_ms, 24);
    bits(t, 47, c.key, 3);
}

fn bits(t: Target, x0: u32, v: u32, comptime n: u32) void {
    inline for (0..n) |b| {
        const on = (v >> @intCast(n - 1 - b)) & 1 == 1;
        switch (t) {
            .st => |lfb| lfb.fb[TAP_ROW * lfb.stride + x0 + b] = if (on) 15 else 0,
            .tc => |fb| fb.row(TAP_ROW)[x0 + b] = if (on) ink565() else 0,
        }
    }
}
