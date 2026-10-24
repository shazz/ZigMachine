// --------------------------------------------------------------------------
// present: the shader's index math (background, balls, text), one plane byte
// per pixel. Colour is the HBL's job.
//
// Only what changed is stored (perf_audit: the full redraw rewrote 64,000
// bytes a frame, 92 % of them unchanged, 1.3 Mc on the board). The plane
// keeps, between two presents, background + the balls and text drawn last
// time, so a 50 Hz tick:
//   * band rows 143..199: the words whose packed background differs from the
//     band frame last shown (~1,200 of 4,560);
//   * the old balls' boxes and the text rows 0..15 back to the background;
//   * the balls and text drawn as before (read-modify-write, the Go's rules).
// A host frame with no tick changes nothing, so it stores nothing.
// Background words are expanded 4 pixels a u32 store through EXPAND.
// reference.zig keeps the old full redraw; present_test.zig requires the same
// plane bytes on every tick.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");
const Clock = @import("clock.zig").Clock;
const textmod = @import("text.zig");

pub const W: usize = 320;
pub const H: usize = 200;
const WPR: usize = W / 4; // words a row = packed bytes a row
const BAND_TOP = assets.BAND_TOP;
const BAND_ROWS = assets.BAND_ROWS;
const BAND_FRAMES = assets.BAND_FRAMES;
const TEXT_ROWS: usize = 16;

/// A packed byte (4 two-bit pixels, LSB first) as 4 plane bytes of index * 4.
const EXPAND: [256]u32 = blk: {
    @setEvalBranchQuota(4000);
    var t: [256]u32 = undefined;
    for (0..256) |b| {
        var v: u32 = 0;
        for (0..4) |k| v |= @as(u32, ((b >> (2 * k)) & 3) * 4) << (8 * k);
        t[b] = v;
    }
    break :blk t;
};

/// The band frame shown on tick `tick` (the Go's (Tick-1+36)%36).
pub fn bandFrame(tick: u32) usize {
    return (tick + (BAND_FRAMES - 1)) % BAND_FRAMES;
}

/// The packed background byte of word `wx` on row `y` for band frame `frame`.
inline fn bgByte(frame: usize, y: usize, wx: usize) u8 {
    if (y < BAND_TOP) return assets.bg_static[y * WPR + wx];
    return assets.bg_band[frame * (BAND_ROWS * WPR) + (y - BAND_TOP) * WPR + wx];
}

/// A box of plane words: rows y0..y1, words wx0..wx1.
const Box = struct { y0: u16 = 0, y1: u16 = 0, wx0: u16 = 0, wx1: u16 = 0 };

pub const Presenter = struct {
    shown_frame: usize = 0,
    text_drawn: bool = false,
    boxes: [6]Box = [_]Box{.{}} ** 6,

    /// The whole picture once (init): every word from the background.
    pub fn full(self: *Presenter, out: [*]u32, c: *const Clock, stream: *const textmod.Stream, live: bool) void {
        const frame = bandFrame(c.tick);
        for (0..H) |y| restore(out, frame, .{ .y0 = @intCast(y), .y1 = @intCast(y + 1), .wx0 = 0, .wx1 = WPR });
        self.shown_frame = frame;
        self.text_drawn = false;
        self.boxes = [_]Box{.{}} ** 6;
        self.draw(out, c, stream, live);
    }

    /// One tick's changes onto the plane that holds the last present.
    pub fn update(self: *Presenter, out: [*]u32, c: *const Clock, stream: *const textmod.Stream, live: bool) void {
        const frame = bandFrame(c.tick);
        if (frame != self.shown_frame) bandDiff(out, self.shown_frame, frame);
        self.shown_frame = frame;
        if (self.text_drawn) restore(out, frame, .{ .y0 = 0, .y1 = TEXT_ROWS, .wx0 = 0, .wx1 = WPR });
        for (self.boxes) |b| restore(out, frame, b);
        self.boxes = [_]Box{.{}} ** 6;
        self.text_drawn = false;
        self.draw(out, c, stream, live);
    }

    fn draw(self: *Presenter, out: [*]u32, c: *const Clock, stream: *const textmod.Stream, live: bool) void {
        if (!live) return;
        const px: [*]u8 = @ptrCast(out);
        for (0..6) |i| self.boxes[i] = drawBall(px, c, i);
        for (0..textmod.CAP) |i| drawGlyph(px, stream, i);
        self.text_drawn = true;
    }
};

/// The box's words back to the background of band frame `frame`.
fn restore(out: [*]u32, frame: usize, b: Box) void {
    var y: usize = b.y0;
    while (y < b.y1) : (y += 1) {
        for (b.wx0..b.wx1) |wx| out[y * WPR + wx] = EXPAND[bgByte(frame, y, wx)];
    }
}

/// Band rows: the words whose packed background differs between two band frames,
/// compared 4 words (one aligned u32 of packed bytes) at a time.
fn bandDiff(out: [*]u32, from: usize, to: usize) void {
    const band: [*]const u32 = @ptrCast(@alignCast(assets.bg_band));
    const n = BAND_ROWS * WPR / 4;
    const a = band[from * n ..][0..n];
    const b = band[to * n ..][0..n];
    const dst = out + BAND_TOP * WPR;
    for (a, b, 0..) |old, new, q| {
        if (old == new) continue;
        inline for (0..4) |k| dst[q * 4 + k] = EXPAND[(new >> (8 * k)) & 0xFF];
    }
}

// --------------------------------------------------------------------------
// The projected ball slots: geometry.ProjectWordPoint, word for word.
// --------------------------------------------------------------------------
pub const Projection = struct { x: i16, y: i16, image: usize, visible: bool };
fn divide(n: i32, depth: i16) i16 {
    // Go: q := int64(n)/int64(depth); out of int16 range keeps the LOW word.
    const q = @divTrunc(@as(i64, n), @as(i64, depth));
    if (q < -32768 or q > 32767) return @bitCast(@as(u16, @truncate(@as(u32, @bitCast(n)))));
    return @intCast(q);
}

pub fn project(hx: i16, hy: i16, hz: i16) Projection {
    const x: i32 = @as(i16, hx -% 160); // WrappedPoint X - centre
    const y: i32 = @as(i16, hy -% 80);
    const px: i32 = 205 * x; // pose.Matrix[0] = 205
    const py: i32 = 205 * y; // pose.Matrix[4] = 205
    const depth: i16 = hz +% 205; // pz(=z)>>0 + DepthBias(205) + pose.Depth(0)
    if (depth == 0) return .{ .x = 0, .y = 0, .image = 0, .visible = false };
    const a = divide(px, depth);
    const b = divide(py, depth);
    const zs: i32 = hz >> 5;
    const img: usize = @intCast(@max(0, @min(15, zs)));
    return .{ .x = a +% 160, .y = b +% 80, .image = img, .visible = true }; // + Center
}

/// Ball slot `slot` (i = (i/4)*4 + shade); returns the plane words it may touch.
pub fn drawBall(px: [*]u8, c: *const Clock, slot: usize) Box {
    const p = c.history[slot * 11];
    const pr = project(p[0], p[1], p[2]);
    if (!pr.visible) return .{};
    const x0: i32 = @max(0, @as(i32, pr.x));
    const x1: i32 = @min(@as(i32, W), @as(i32, pr.x) + 32);
    const y0: i32 = @max(0, @as(i32, pr.y));
    const y1: i32 = @min(@as(i32, H), @as(i32, pr.y) + 32);
    if (x0 >= x1 or y0 >= y1) return .{};
    const bbase = pr.image * 1024;
    var sy: i32 = y0;
    while (sy < y1) : (sy += 1) {
        const yy: usize = @intCast(sy - pr.y);
        var sx: i32 = x0;
        while (sx < x1) : (sx += 1) {
            const shade = assets.p2(assets.balls, bbase + yy * 32 + @as(usize, @intCast(sx - pr.x)));
            if (shade == 0) continue;
            const o = @as(usize, @intCast(sy)) * W + @as(usize, @intCast(sx));
            px[o] = (px[o] & ~@as(u8, 3)) | shade;
        }
    }
    return .{ .y0 = @intCast(y0), .y1 = @intCast(y1), .wx0 = @intCast(@divTrunc(x0, 4)), .wx1 = @intCast(@divTrunc(x1 + 3, 4)) };
}

/// Text slot `slot` (text.a > 0 -> i = i % 8 + 8), rows 0..15.
pub fn drawGlyph(px: [*]u8, stream: *const textmod.Stream, slot: usize) void {
    const s = stream.slot(slot);
    if (s.glyph < 0) return;
    const g: usize = @intCast(s.glyph);
    const x0: usize = 16 + 8 * slot;
    for (0..TEXT_ROWS) |yy| {
        // the glyph's 8 columns are one byte of the MSB-first mask (index*8 is byte-aligned)
        const m = assets.font[(g * 512 + yy * 32 + @as(usize, s.index) * 8) >> 3];
        if (m == 0) continue;
        for (0..8) |k| {
            if ((m >> @intCast(7 - k)) & 1 == 0) continue;
            const o = yy * W + x0 + k;
            px[o] = (px[o] & 7) | 8;
        }
    }
}
