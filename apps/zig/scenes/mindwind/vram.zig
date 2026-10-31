// --------------------------------------------------------------------------
// Where Mind Rewind's line sources live in VRAM (LBASE reads only VRAM), and
// filling them at start-up. One byte a pixel; the ST's planar rows become
// chunky rows of the same width in pixels, so the demo's byte arithmetic maps
// to pixels x2 and its wrap-arounds (a 416-px line reading on into the next
// 320-px picture row) happen the same way.
//
//   plane 0 (the overscan plane, 112,000 B, never shown as itself):
//     a blank line, the scroller ring (48 x 896), the rewind band ring (42 x 896)
//   planes 1-3's idle 320x200 buffers (contiguous): the picture (+ its padding),
//     later the end screen
//   the pool: the stripe rows (640 x 416), the three rainbow images (448 x 207)
// --------------------------------------------------------------------------
const zg = @import("zigos");
const data = @import("data.zig");
const stripes_gen = @import("stripes_gen.zig");
const rainbow_gen = @import("rainbow_gen.zig");

pub const RING_W: usize = 896; // the demo's $1C0-byte ring rows
pub const RING_ROWS: usize = 48;
pub const BAND_ROWS: usize = 42;
pub const PIC_W: usize = 320;
pub const PIC_PAD: usize = 1280; // the demo zeroes row 199 and what follows ($8ACC)
pub const END_W: usize = zg.PHYSICAL_WIDTH;

pub var region: [*]u8 = undefined; // byte 0 = region offset 0
pub var blank: u32 = 0;
pub var ring: u32 = 0; // scroller ring row 0 (16 px of margin before it)
pub var band: u32 = 0;
pub var pic: u32 = 0;
pub var end_pic: u32 = 0;
pub var stripes: u32 = 0; // row r (0..127 the workspace, 128.. the bank) at + r * 416
pub var rainbow: [3]u32 = .{ 0, 0, 0 };

fn offsetOf(p: [*]u8) u32 {
    return @intCast(@intFromPtr(p) - @intFromPtr(region));
}

fn take(bytes: usize) u32 {
    const v = zg.vramWords((bytes + 3) / 4) orelse @panic("mindwind: VRAM pool full");
    region = @ptrFromInt(@intFromPtr(v.words.ptr) - v.off);
    return v.off;
}

pub fn bytes(off: u32, n: usize) []u8 {
    return region[off..][0..n];
}

/// Allocate and fill everything; `zigos.lfbs[0]` is already the overscan plane.
pub fn init(zigos: *zg.ZigOS) void {
    stripes = take(stripes_gen.ROWS * stripes_gen.ROW_PX + 32);
    for (&rainbow) |*r| r.* = take(rainbow_gen.IMAGE_BYTES);
    const p0 = offsetOf(zigos.lfbs[0].fb);
    blank = p0;
    ring = p0 + 1024 + 16;
    band = ring + RING_ROWS * RING_W + 1024;
    pic = offsetOf(zigos.lfbs[1].fb);
    end_pic = pic + PIC_W * 200 + PIC_PAD;
    @memset(bytes(p0, zg.OVERSCAN_FB_BYTES), 0);

    const m = zg.mem.mark();
    defer zg.mem.release(m);
    const w = zg.mem.mustAlloc(u16, stripes_gen.PLANAR_WORDS);
    stripes_gen.generate(w, data.stripe_patterns, bytes(stripes, stripes_gen.ROWS * stripes_gen.ROW_PX));
    for (rainbow, 0..) |r, k| rainbow_gen.generate(@enumFromInt(k), data.sin_271c8, bytes(r, rainbow_gen.IMAGE_BYTES));

    planarRows(data.girl, 160, 200, bytes(pic, PIC_W * 200), PIC_W, 0);
    @memset(bytes(pic + PIC_W * 199, PIC_W + PIC_PAD), 0);
    // the band image: 192 px of each 320-px row, at 0 and at 448 of an 896-px ring row ($17052)
    for (0..BAND_ROWS) |r| {
        const row = bytes(band + @as(u32, @intCast(r * RING_W)), RING_W);
        @memset(row, 0);
        var tmp: [320]u8 = undefined;
        planarRows(data.band[r * 160 ..][0..160], 160, 1, &tmp, 320, 0);
        @memcpy(row[0..192], tmp[0..192]);
        @memcpy(row[448..][0..192], tmp[0..192]);
    }
}

/// The end screen: the 320x200 logo in the middle of 400-px rows (borders as colour 0).
pub fn initEnd() void {
    const out = bytes(end_pic, END_W * 200);
    @memset(out, 0);
    planarRows(data.rg_end, 160, 200, out, END_W, 40);
}

/// ST low-res planar rows (`row_bytes` each) to chunky rows of `out_w` px, at column `x0`.
pub fn planarRows(src: []const u8, row_bytes: usize, rows: usize, out: []u8, out_w: usize, x0: usize) void {
    for (0..rows) |y| {
        for (0..row_bytes / 8) |g| {
            const o = y * row_bytes + g * 8;
            var p: [4]u16 = undefined;
            for (0..4) |k| p[k] = data.be16(src[o..], k);
            for (0..16) |b| {
                const bit: u4 = @intCast(15 - b);
                var c: u8 = 0;
                for (0..4) |k| c |= @as(u8, @intCast((p[k] >> bit) & 1)) << @intCast(k);
                out[y * out_w + x0 + g * 16 + b] = c;
            }
        }
    }
}
