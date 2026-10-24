// The benchmark read-out under the picture: frames so far, rays cast, and the
// measured rate, pixels per second and nanoseconds per pixel of tracing time
// (bench.zig). Cycles per pixel on a board = NS/PX x its clock in GHz. A host
// without a clock shows NO CLOCK: the frame count is then the only measure.
//
// Row 176 is a progress bar; row 199 carries the counters as a 65-pixel binary
// strip (frames 16 bits, rays 24, done 1, pixels/s 24) so a headless harness
// can read them straight off the picture instead of trusting the text.
const zg = @import("zigos");
const P = @import("palette.zig");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;

pub const BAR_ROW: u32 = 176;
pub const TAP_ROW: u32 = 199;
pub const TAP_X: u32 = 255;
pub const TAP_FRAMES_BITS = 16;
pub const TAP_RAYS_BITS = 24;
pub const TAP_RATE_BITS = 24;
// Passes complete (0..63), right of the rate line's text: only the f32 cart
// refines, the fixed one reads 0 then 1.
pub const TAP_PASS_X: u32 = 232;
pub const TAP_PASS_BITS = 6;

pub const Counters = struct {
    frames: u32,
    rays: u32,
    pixels: u32,
    total_pixels: u32,
    done: bool,
    passes_done: u32,
    passes: u32,
    samples: u32, // all passes' samples so far, for the bar
    clocked: bool,
    px_per_s: u32,
    ns_per_px: u32,
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

fn line(zigos: *ZigOS, fb: *LogicalFB, text: []const u8, row: i16) void {
    zigos.printText(fb, text, 0, row, P.TEXT, P.PANEL);
}

pub fn draw(zigos: *ZigOS, fb: *LogicalFB, name: []const u8, c: Counters) void {
    var buf: [40]u8 = [_]u8{' '} ** 40;
    var n = putStr(&buf, 0, "SDF RAYTRACER ");
    n = putStr(&buf, n, name);
    if (c.passes > 1) {
        n = putStr(&buf, n, "  PASS ");
        n = putNum(&buf, n, 2, @min(c.passes_done + 1, c.passes));
        n = putStr(&buf, n, "/");
        n = putNum(&buf, n, 2, c.passes);
        if (c.passes_done == c.passes) n = putStr(&buf, n, " DONE");
    } else n = putStr(&buf, n, if (c.done) "  DONE" else "  ...");
    line(zigos, fb, &buf, 177);
    buf = [_]u8{' '} ** 40;
    n = putStr(&buf, 0, "FRAMES ");
    n = putNum(&buf, n, 5, c.frames);
    n = putStr(&buf, n, "  RAYS ");
    n = putNum(&buf, n, 7, c.rays);
    line(zigos, fb, &buf, 185);
    buf = [_]u8{' '} ** 40;
    if (c.clocked) {
        n = putStr(&buf, 0, "PX/S ");
        n = putNum(&buf, n, 8, c.px_per_s);
        n = putStr(&buf, n, "  NS/PX ");
        n = putNum(&buf, n, 6, c.ns_per_px);
    } else n = putStr(&buf, 0, "PX/S NO CLOCK (FIXED WORK)");
    line(zigos, fb, &buf, 193);
    bar(fb, c);
    tap(fb, c);
}

fn bar(fb: *LogicalFB, c: Counters) void {
    const w: u32 = @intCast(@as(u64, c.samples) * 320 / (@as(u64, c.total_pixels) * c.passes));
    for (0..320) |x| fb.fb[BAR_ROW * fb.stride + x] = if (x < w) P.BAR else P.BAR_DIM;
}

fn tap(fb: *LogicalFB, c: Counters) void {
    bits(fb, TAP_PASS_X, c.passes_done, TAP_PASS_BITS);
    var x: u32 = TAP_X;
    inline for (.{ .{ c.frames, TAP_FRAMES_BITS }, .{ c.rays, TAP_RAYS_BITS }, .{ @as(u32, @intFromBool(c.done)), 1 }, .{ c.px_per_s, TAP_RATE_BITS } }) |f| {
        var b: u32 = 0;
        while (b < f[1]) : (b += 1) {
            const bit: u5 = @intCast(f[1] - 1 - b);
            fb.fb[TAP_ROW * fb.stride + x] = if ((f[0] >> bit) & 1 == 1) P.BAR_DIM else P.PANEL;
            x += 1;
        }
    }
}

fn bits(fb: *LogicalFB, x0: u32, v: u32, comptime n: u32) void {
    inline for (0..n) |b| {
        const on = (v >> @intCast(n - 1 - b)) & 1 == 1;
        fb.fb[TAP_ROW * fb.stride + x0 + b] = if (on) P.BAR_DIM else P.PANEL;
    }
}
