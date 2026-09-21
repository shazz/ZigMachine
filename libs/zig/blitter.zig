// --------------------------------------------------------------------------
// ZigOS — OPEN blitter wrapper.
//
// A thin, typed front-end over the sealed blitter register block (hardware.zig
// BLIT_*) + the hwBlit() export. Effects and scenes drive the 2D coprocessor
// through these methods and never touch raw registers. Each call sets the
// register block for one primitive, then fires hwBlit() (synchronous in v1).
//
// Destinations are LogicalFB planes; a plane's pixel view is a byte offset into
// the shared video region, which is exactly what the blitter's BASE registers
// want, so plane->plane blits and cookie-cut bobs need no copying.
// --------------------------------------------------------------------------
const std = @import("std");
const hw = @import("hardware");
const LogicalFB = @import("zigos.zig").LogicalFB;

pub const Vec2 = struct { x: i16, y: i16 };

// Named minterms for the ops that combine sources; the raw byte stays reachable
// via `line(..., .{ .raw = 0x.. })` for the clever cases.
pub const Minterm = enum(u8) {
    copy = hw.MT_B, // draw COLOR straight
    xor = hw.MT_XOR_BC, // reversible (wireframe, feedback)
    glenz = hw.MT_OR_BC, // OR into dest — additive glenz-vector transparency
    _,
};

pub const Blitter = struct {
    base: usize = 0,

    pub fn init(self: *Blitter) void {
        self.base = @intCast(hw.hwVideoBase());
    }

    // --- register writers (region-relative offsets) ---
    inline fn w8(self: *Blitter, off: usize, v: u8) void {
        @as(*u8, @ptrFromInt(self.base + off)).* = v;
    }
    inline fn w16(self: *Blitter, off: usize, v: u16) void {
        std.mem.writeInt(u16, @as(*[2]u8, @ptrFromInt(self.base + off)), v, .little);
    }
    inline fn wi16(self: *Blitter, off: usize, v: i16) void {
        std.mem.writeInt(i16, @as(*[2]u8, @ptrFromInt(self.base + off)), v, .little);
    }
    inline fn w32(self: *Blitter, off: usize, v: u32) void {
        std.mem.writeInt(u32, @as(*[4]u8, @ptrFromInt(self.base + off)), v, .little);
    }

    // Byte offset of a plane's pixel buffer within the video region.
    inline fn fbOffset(self: *Blitter, fb: *LogicalFB) u32 {
        return @intCast(@intFromPtr(fb.fb) - self.base);
    }

    inline fn setDest(self: *Blitter, fb: *LogicalFB) void {
        self.w32(hw.BLIT_D_BASE, self.fbOffset(fb));
        self.w16(hw.BLIT_D_STRIDE, fb.stride);
    }

    // What a FILL may do beyond writing `color` straight into the destination.
    // Every field defaults to the pre-1.5.0 behaviour, so `fill()` is unchanged:
    //  - `bg` null leaves BG_COLOR alone (a solid fill never reads it; a halftone
    //    fill that wants a defined background must say which),
    //  - `mt` null writes the colour straight (FILL ignores MINTERM), non-null
    //    combines source and destination the way triangleEx does,
    //  - `halftone` true makes the loaded pattern authoritative, so an ALL-ZERO
    //    pattern is density 0 (every pixel `bg`) instead of "no halftone at all".
    //    Leave it false and the machine sniffs the pattern; to turn a halftone
    //    off, clearHalftone().
    pub const FillOpts = struct {
        bg: ?u8 = null,
        mt: ?Minterm = null,
        halftone: bool = false,
    };

    // --- primitives ---
    pub fn fill(self: *Blitter, fb: *LogicalFB, x: i16, y: i16, w: u16, h: u16, color: u8) void {
        self.fillEx(fb, x, y, w, h, color, .{});
    }

    pub fn fillEx(self: *Blitter, fb: *LogicalFB, x: i16, y: i16, w: u16, h: u16, color: u8, opts: FillOpts) void {
        self.setDest(fb);
        self.w8(hw.BLIT_CON, 0);
        var con2: u8 = 0;
        if (opts.mt) |m| {
            self.w8(hw.BLIT_MINTERM, @intFromEnum(m));
            con2 |= hw.CON2_FILL_MT;
        }
        if (opts.bg) |b| self.w8(hw.BLIT_BG_COLOR, b);
        if (opts.halftone) con2 |= hw.CON2_HALFTONE_EN;
        self.w8(hw.BLIT_CON2, con2); // never stale: SRC_ABS from an earlier blit must not leak in
        self.w8(hw.BLIT_COLOR, color);
        self.wi16(hw.BLIT_X0, x);
        self.wi16(hw.BLIT_Y0, y);
        self.w16(hw.BLIT_W, w);
        self.w16(hw.BLIT_H, h);
        self.w8(hw.BLIT_COMMAND, hw.BLIT_CMD_FILL);
        hw.hwBlit();
    }

    pub fn clear(self: *Blitter, fb: *LogicalFB, color: u8) void {
        self.fill(fb, 0, 0, fb.fb_w, fb.fb_h, color);
    }

    pub fn line(self: *Blitter, fb: *LogicalFB, x0: i16, y0: i16, x1: i16, y1: i16, color: u8, mt: Minterm) void {
        self.setDest(fb);
        self.w8(hw.BLIT_CON, 0);
        self.w8(hw.BLIT_MINTERM, @intFromEnum(mt));
        self.w8(hw.BLIT_COLOR, color);
        self.wi16(hw.BLIT_X0, x0);
        self.wi16(hw.BLIT_Y0, y0);
        self.wi16(hw.BLIT_X1, x1);
        self.wi16(hw.BLIT_Y1, y1);
        self.w8(hw.BLIT_COMMAND, hw.BLIT_CMD_LINE);
        hw.hwBlit();
    }

    // Flat solid triangle (COLOR straight into dest).
    pub fn triangle(self: *Blitter, fb: *LogicalFB, v0: Vec2, v1: Vec2, v2: Vec2, color: u8) void {
        self.triangleEx(fb, v0, v1, v2, color, 0, .copy);
    }

    // General triangle: fill with `fg` combined into the destination via `mt`
    // (`.copy` = flat, `.glenz` = OR transparency). When a halftone pattern is
    // loaded (setHalftone), pixels alternate `fg`/`bg` for dithered shading.
    pub fn triangleEx(self: *Blitter, fb: *LogicalFB, v0: Vec2, v1: Vec2, v2: Vec2, fg: u8, bg: u8, mt: Minterm) void {
        self.setDest(fb);
        self.w8(hw.BLIT_CON, 0);
        self.w8(hw.BLIT_MINTERM, @intFromEnum(mt));
        self.w8(hw.BLIT_COLOR, fg);
        self.w8(hw.BLIT_BG_COLOR, bg);
        self.wi16(hw.BLIT_X0, v0.x);
        self.wi16(hw.BLIT_Y0, v0.y);
        self.wi16(hw.BLIT_X1, v1.x);
        self.wi16(hw.BLIT_Y1, v1.y);
        self.wi16(hw.BLIT_X2, v2.x);
        self.wi16(hw.BLIT_Y2, v2.y);
        self.w8(hw.BLIT_COMMAND, hw.BLIT_CMD_TRIANGLE);
        hw.hwBlit();
    }

    // Load / clear the 16x16 1-bit halftone pattern (bit set -> COLOR, clear -> BG_COLOR).
    pub fn setHalftone(self: *Blitter, pattern: [16]u16) void {
        for (pattern, 0..) |row, i| self.w16(hw.BLIT_HALFTONE + i * 2, row);
    }
    pub fn clearHalftone(self: *Blitter) void {
        var i: usize = 0;
        while (i < 16) : (i += 1) self.w16(hw.BLIT_HALFTONE + i * 2, 0);
    }

    // Plain block copy of a w×h region of `src` at (sx,sy) onto `dst` at (dx,dy),
    // no colour key. Firing this once per row with a per-row `dx` is the classic
    // strip-blit deformation (sine wobble / rubber / shear).
    pub fn blitCopy(self: *Blitter, dst: *LogicalFB, dx: i16, dy: i16, src: *LogicalFB, sx: i16, sy: i16, w: u16, h: u16) void {
        self.setDest(dst);
        self.w8(hw.BLIT_CON2, 0); // plane sources are video-region offsets
        const src_off: u32 = @intCast(@intFromPtr(src.fb) - self.base + @as(usize, @intCast(sy)) * src.stride + @as(usize, @intCast(sx)));
        self.w32(hw.BLIT_B_BASE, src_off);
        self.w16(hw.BLIT_B_STRIDE, src.stride);
        self.w8(hw.BLIT_CON, hw.CON_USEB);
        self.w8(hw.BLIT_MINTERM, hw.MT_B);
        self.wi16(hw.BLIT_X0, dx);
        self.wi16(hw.BLIT_Y0, dy);
        self.w16(hw.BLIT_W, w);
        self.w16(hw.BLIT_H, h);
        self.w8(hw.BLIT_COMMAND, hw.BLIT_CMD_BLIT);
        hw.hwBlit();
    }

    // Cookie-cut bob: copy a w×h region of `src` at (sx,sy) onto `dst` at
    // (dx,dy), skipping pixels equal to `key` (the chunky one-channel cookie-cut).
    pub fn bob(self: *Blitter, dst: *LogicalFB, dx: i16, dy: i16, src: *LogicalFB, sx: i16, sy: i16, w: u16, h: u16, key: u8) void {
        self.setDest(dst);
        self.w8(hw.BLIT_CON2, 0); // plane sources are video-region offsets
        const src_off: u32 = @intCast(@intFromPtr(src.fb) - self.base + @as(usize, @intCast(sy)) * src.stride + @as(usize, @intCast(sx)));
        self.w32(hw.BLIT_B_BASE, src_off);
        self.w16(hw.BLIT_B_STRIDE, src.stride);
        self.w8(hw.BLIT_CON, hw.CON_USEB | hw.CON_KEY_EN);
        self.w8(hw.BLIT_MINTERM, hw.MT_B);
        self.w8(hw.BLIT_COLOR_KEY, key);
        self.wi16(hw.BLIT_X0, dx);
        self.wi16(hw.BLIT_Y0, dy);
        self.w16(hw.BLIT_W, w);
        self.w16(hw.BLIT_H, h);
        self.w8(hw.BLIT_COMMAND, hw.BLIT_CMD_BLIT);
        hw.hwBlit();
    }

    // Copy a w×h region at (sx,sy) of a raw 8bpp image held ANYWHERE in the
    // cart's RAM (an @embedFile asset, a scratch buffer), `src_w` pixels per
    // row, onto `dst` at (dx,dy). `key` skips that index (cookie-cut); null
    // copies every pixel. The rectangle is clamped to `pixels`, so it never reads
    // past the slice; the machine (HW 1.4.0, CON2.SRC_ABS) refuses a source
    // outside the readable windows and draws nothing.
    pub fn blitImage(self: *Blitter, dst: *LogicalFB, dx: i16, dy: i16, pixels: []const u8, src_w: u16, sx: u16, sy: u16, w: u16, h: u16, key: ?u8) void {
        if (src_w == 0 or sx >= src_w) return;
        const rows = pixels.len / src_w;
        if (sy >= rows) return;
        const cw = @min(w, src_w - sx);
        const ch: u16 = @intCast(@min(h, rows - sy));
        if (cw == 0 or ch == 0) return;
        const addr = @intFromPtr(pixels.ptr) + @as(usize, sy) * src_w + sx;
        self.setDest(dst);
        self.w8(hw.BLIT_CON2, hw.CON2_SRC_ABS);
        self.w32(hw.BLIT_B_BASE, @intCast(addr));
        self.w16(hw.BLIT_B_STRIDE, src_w);
        self.w8(hw.BLIT_CON, if (key != null) hw.CON_USEB | hw.CON_KEY_EN else hw.CON_USEB);
        self.w8(hw.BLIT_MINTERM, hw.MT_B);
        self.w8(hw.BLIT_COLOR_KEY, key orelse 0);
        self.wi16(hw.BLIT_X0, dx);
        self.wi16(hw.BLIT_Y0, dy);
        self.w16(hw.BLIT_W, cw);
        self.w16(hw.BLIT_H, ch);
        self.w8(hw.BLIT_COMMAND, hw.BLIT_CMD_BLIT);
        hw.hwBlit();
    }

    // Estimated cost of the last op (pixels touched + setup), for VBL budgeting.
    pub fn cycles(self: *Blitter) u32 {
        return std.mem.readInt(u32, @as(*[4]u8, @ptrFromInt(self.base + hw.BLIT_CYCLES)), .little);
    }
};
