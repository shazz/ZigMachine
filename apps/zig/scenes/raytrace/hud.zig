// The benchmark read-out under the picture: frames so far, rays cast, and
// rays per second at the nominal 60 fps (rays * 60 / frames). On the FPGA the
// cart runs slower than 60 fps, so there the number to read is the wall time to
// "DONE"; the frame count is the cart's own, machine-independent work measure.
//
// Row 176 is a progress bar; row 199 carries the same numbers as a 41-pixel
// binary strip (frames 16 bits, rays 24, done 1) so a headless harness can read
// the counters straight off the picture instead of trusting the text.
const zg = @import("zigos");
const P = @import("palette.zig");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;

pub const BAR_ROW: u32 = 176;
pub const TAP_ROW: u32 = 199;
pub const TAP_X: u32 = 256;
pub const TAP_FRAMES_BITS = 16;
pub const TAP_RAYS_BITS = 24;

pub const Counters = struct { frames: u32, rays: u32, pixels: u32, total_pixels: u32, done: bool };

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
    n = putStr(&buf, n, if (c.done) "  DONE" else "  ...");
    line(zigos, fb, &buf, 177);
    buf = [_]u8{' '} ** 40;
    n = putStr(&buf, 0, "FRAMES ");
    n = putNum(&buf, n, 5, c.frames);
    n = putStr(&buf, n, "  RAYS ");
    n = putNum(&buf, n, 7, c.rays);
    line(zigos, fb, &buf, 185);
    buf = [_]u8{' '} ** 40;
    n = putStr(&buf, 0, "RAYS/S @60FPS ");
    const rps: u64 = if (c.frames == 0) 0 else @as(u64, c.rays) * 60 / c.frames;
    n = putNum(&buf, n, 7, @intCast(@min(rps, 9999999)));
    line(zigos, fb, &buf, 193);
    bar(fb, c);
    tap(fb, c);
}

fn bar(fb: *LogicalFB, c: Counters) void {
    const w: u32 = @intCast(@as(u64, c.pixels) * 320 / c.total_pixels);
    for (0..320) |x| fb.fb[BAR_ROW * fb.stride + x] = if (x < w) P.BAR else P.BAR_DIM;
}

fn tap(fb: *LogicalFB, c: Counters) void {
    var x: u32 = TAP_X;
    inline for (.{ .{ c.frames, TAP_FRAMES_BITS }, .{ c.rays, TAP_RAYS_BITS }, .{ @as(u32, @intFromBool(c.done)), 1 } }) |f| {
        var b: u32 = 0;
        while (b < f[1]) : (b += 1) {
            const bit: u5 = @intCast(f[1] - 1 - b);
            fb.fb[TAP_ROW * fb.stride + x] = if ((f[0] >> bit) & 1 == 1) P.BAR_DIM else P.PANEL;
            x += 1;
        }
    }
}
