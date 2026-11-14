// The benchmark read-out under the picture, in the true-colour plane (rows 176..199):
//   177  the mode and where its maths runs, the pass (1..16)
//   185  the first picture's rate (pixels per second of tracing time) and the time to
//        converge (all 16 passes, tracing time, seconds; it runs until then): bench.zig
//   193  frames so far and the first picture's rays
// A host without a clock shows NO CLOCK: the frame count is then the only measure.
//
// Row 176 is a progress bar over all passes; row 199 carries the counters as binary
// strips (frames 16 bits, rays 24, done 1, pixels/s 24 from TAP_X; passes 6 bits at
// TAP_PASS_X; ms to converge 24 bits at TAP_CONV_X) so a headless harness reads them
// off the picture instead of trusting the text. The glyphs are the system font's,
// drawn here (zigos.printText writes 8-bit planes only).
const zg = @import("zigos");
const tc = zg.tc;

pub const BAR_ROW: u32 = 176;
pub const TAP_ROW: u32 = 199;
pub const TAP_X: u32 = 255;
pub const TAP_PASS_X: u32 = 232;
pub const TAP_CONV_X: u32 = 200; // right of line 193's text (25 columns)

// 565 colours that come back exactly through the machine's bit replication.
pub const PANEL: u16 = tc.rgb565(8, 8, 24);
const TEXT: u16 = 0xFFFF;
const BAR: u16 = tc.rgb565(255, 168, 112);
const BAR_DIM: u16 = tc.rgb565(52, 52, 96); // also a tap's 1 (red 49 > the harness's 30)

pub const Counters = struct {
    name: []const u8, // the mode and where its maths runs
    frames: u32,
    rays: u32,
    done: bool, // the first picture
    passes_done: u32,
    passes: u32,
    samples: u32, // all passes' samples so far, for the bar
    total: u32, // all passes' samples
    clocked: bool,
    px_per_s: u32,
    conv_ms: u32, // tracing time so far, all passes
};

fn putStr(buf: []u8, at: usize, s: []const u8) usize {
    @memcpy(buf[at..][0..s.len], s);
    return at + s.len;
}

/// Right-aligned decimal in `width` columns, zero padded.
fn putNum(buf: []u8, at: usize, width: usize, n: u32) usize {
    var v = n;
    var i = width;
    while (i > 0) : (i -= 1) {
        buf[at + i - 1] = '0' + @as(u8, @intCast(v % 10));
        v /= 10;
    }
    return at + width;
}

pub fn draw(zigos: *zg.ZigOS, fb: tc.Fb, c: Counters) void {
    var buf: [40]u8 = [_]u8{' '} ** 40;
    var n = putStr(&buf, 0, c.name);
    n = putStr(&buf, 28, "PASS ");
    n = putNum(&buf, n, 2, @min(c.passes_done + 1, c.passes));
    n = putStr(&buf, n, "/");
    _ = putNum(&buf, n, 2, c.passes);
    text(zigos, fb, &buf, 177);
    buf = [_]u8{' '} ** 40;
    if (c.clocked) {
        n = putStr(&buf, 0, "1ST PIC ");
        n = putNum(&buf, n, 7, c.px_per_s);
        n = putStr(&buf, n, " PX/S  CONV ");
        n = putNum(&buf, n, 4, c.conv_ms / 1000);
        n = putStr(&buf, n, ".");
        n = putNum(&buf, n, 1, c.conv_ms / 100 % 10);
        _ = putStr(&buf, n, " S");
    } else _ = putStr(&buf, 0, "PX/S NO CLOCK (FIXED WORK)");
    text(zigos, fb, &buf, 185);
    buf = [_]u8{' '} ** 40;
    n = putStr(&buf, 0, "FRAMES ");
    n = putNum(&buf, n, 5, c.frames);
    n = putStr(&buf, n, " RAYS ");
    _ = putNum(&buf, n, 7, c.rays);
    text(zigos, fb, buf[0..25], 193);
    bar(fb, c);
    tap(fb, c);
}

/// A line of 8x8 glyphs at (0, y), white on the panel.
fn text(zigos: *zg.ZigOS, fb: tc.Fb, s: []const u8, y: u32) void {
    for (0..8) |r| {
        const row = fb.row(y + r);
        for (s, 0..) |ch, k| {
            const g = zigos.system_font[@as(usize, ch) * 64 + r * 8 ..][0..8];
            inline for (0..8) |c| row[k * 8 + c] = if (g[c] == 1) TEXT else PANEL;
        }
    }
}

fn bar(fb: tc.Fb, c: Counters) void {
    const w: u32 = @intCast(@as(u64, c.samples) * 320 / c.total);
    const row = fb.row(BAR_ROW);
    for (row, 0..) |*p, x| p.* = if (x < w) BAR else BAR_DIM;
}

fn tap(fb: tc.Fb, c: Counters) void {
    const row = fb.row(TAP_ROW);
    bits(row, TAP_PASS_X, c.passes_done, 6);
    bits(row, TAP_CONV_X, c.conv_ms, 24);
    bits(row, TAP_X, c.frames, 16);
    bits(row, TAP_X + 16, c.rays, 24);
    bits(row, TAP_X + 40, @intFromBool(c.done), 1);
    bits(row, TAP_X + 41, c.px_per_s, 24);
}

fn bits(row: []u16, x0: u32, v: u32, comptime n: u32) void {
    inline for (0..n) |b| {
        const on = (v >> @intCast(n - 1 - b)) & 1 == 1;
        row[x0 + b] = if (on) BAR_DIM else PANEL;
    }
}
