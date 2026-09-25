// --------------------------------------------------------------------------
// REPS layers: the colours per scanline of the bouncing rasterbars and of the
// "CRACKING IS..." mask (raster.zig plays them), the wobbly THE REPLICANTS
// sprites and theunion.png's soft edges (screen.js:143-175 update, 242-285 draw).
//
// Halving rule, the same for every layer: ST pixel (X, Y) shows canvas pixel
// (2X+1, 2Y+1). Even canvas coordinates halve exactly; a fractional sprite
// position takes floor(round(c)/2), the texel nearest that canvas sample.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");

pub fn halve(c: f64) i32 {
    return @divFloor(@as(i32, @intFromFloat(@floor(c + 0.5))), 2);
}

/// Six 640-wide raster images, three over each window, bouncing 2 canvas px a
/// frame inside [94,160] and [204,270] (screen.js:77-91, 152-168).
pub const Bars = struct {
    y: [6]i32, // canvas rows: pink, green, brown on top; brown, green, pink below
    dir: [6]i32,

    const Band = struct { min: i32, max: i32 };
    const TOP = Band{ .min = 94, .max = 160 };
    const BOTTOM = Band{ .min = 204, .max = 270 };

    pub fn init(self: *Bars) void {
        for (0..3) |i| {
            const k: i32 = @intCast(i);
            self.y[i] = 94 + 30 * k;
            self.dir[i] = 2;
            self.y[3 + i] = 204 + 30 * k;
            self.dir[3 + i] = -2;
        }
    }

    pub fn update(self: *Bars) void {
        for (&self.y, &self.dir, 0..) |*y, *dir, i| {
            const band = if (i < 3) TOP else BOTTOM;
            y.* += dir.*;
            if (y.* < band.min or y.* > band.max) dir.* = -dir.*;
        }
    }

    /// Each row of a bar is ONE colour right across the raster, so a bar is not
    /// pixels at all: it is colour 0 rewritten on each of its scanlines. `rows`
    /// is colour 0 for every visible line, black where no bar is.
    pub fn paint(self: *const Bars, rows: *[zg.HEIGHT]u32, img: *const A.Images) void {
        const colours = [6][]const u8{ img.pink, img.green, img.brown, img.brown, img.green, img.pink };
        @memset(rows, A.rgba(A.BLACK));
        for (self.y, colours) |y, bar| {
            const top = @divFloor(y, 2); // bars start and step on even rows
            for (bar, 0..) |c, r| {
                const row = top + @as(i32, @intCast(r));
                if (row < 0 or row >= zg.HEIGHT) continue;
                rows[@intCast(row)] = A.rgba(c);
            }
        }
    }
};

/// rastersOverlay.png filled 'source-atop' by rasters.png drawn at
/// posColorRasterY1 and posColorRasterY2 (screen.js:243-247), then drawn at
/// canvas row 146. Both positions step 1 and wrap 168 -> -168, so Y2 is always
/// Y1 +- 168: between them they cover the 108 rows, and every row shows
/// rasters.png's row (row - Y1) mod 168. Per ST row that is one colour, so the
/// mask is drawn in ONE ink and that ink's register is rewritten per scanline.
pub const Rasters = struct {
    pos: i32, // posColorRasterY1

    const Y = 73;
    const PERIOD = 168; // rasters.png height

    pub fn init(self: *Rasters) void {
        self.pos = -PERIOD;
    }

    pub fn update(self: *Rasters) void {
        self.pos += 1;
        if (self.pos >= PERIOD) self.pos = -PERIOD;
    }

    /// The mask in MASK_INK, and that ink's colour for each of its lines.
    pub fn draw(self: *const Rasters, dst: blit.Dst, mask: blit.Image, rasters: []const u8, ink: *[zg.HEIGHT]u32) void {
        for (0..mask.h) |r| {
            const canvas_row = 2 * @as(i32, @intCast(r)) + 1;
            const src_row: usize = @intCast(@mod(canvas_row - self.pos, PERIOD));
            ink[Y + r] = A.rgba(rasters[src_row / 2]);
        }
        blit.blit(dst, mask, null, 0, Y, 0, .{ .flat = A.MASK_INK });
    }
};

/// THE REPLICANTS: sprite i circles (40+40i, 180) with radius 30, its phase
/// starting at i*0.5 and gaining 0.08 a frame (screen.js:36, 170-175).
pub const Sprites = struct {
    counter: [LETTERS.len]f64,

    const LETTERS = "THE REPLICANTS"; // screen.js:62-75
    const STEP = 0.08;
    const SHEET: [LETTERS.len]?usize = blk: {
        var t: [LETTERS.len]?usize = undefined;
        for (LETTERS, 0..) |ch, i| t[i] = std.mem.indexOfScalar(u8, A.SPRITE_LETTERS, ch);
        break :blk t;
    };

    pub fn init(self: *Sprites) void {
        for (&self.counter, 0..) |*c, i| c.* = @as(f64, @floatFromInt(i)) * 0.5;
    }

    pub fn update(self: *Sprites) void {
        for (&self.counter) |*c| c.* += STEP;
    }

    /// In index order, so a later letter overlaps an earlier one.
    pub fn draw(self: *const Sprites, dst: blit.Dst, sheet: []const blit.Image) void {
        for (self.counter, SHEET, 0..) |c, sprite, i| {
            const s = sprite orelse continue; // the space
            const fi: f64 = @floatFromInt(i);
            const x = halve((40 + fi * 40) + 30 * @cos(c));
            const y = halve(180 + 30 * @sin(c));
            blit.blit(dst, sheet[s], null, x, y, 0, .copy);
        }
    }
};

/// Where each BLEND_UNDER index sits in its blend row.
const UNDER_RANK: [256]u8 = blk: {
    var t = [_]u8{0} ** 256;
    for (A.BLEND_UNDER, 0..) |u, i| t[u] = @intCast(i);
    break :blk t;
};

/// theunion.png over the scrollers (screen.js:284-285): opaque pixels copy, a
/// soft pixel takes its blend with the index under it. Only BLEND_UNDER can be
/// under one (the harness checks every soft pixel against that).
pub fn drawUnion(dst: blit.Dst, img: blit.Image, y0: usize) void {
    if (img.w != dst.w or y0 + img.h > dst.h) return;
    for (0..img.h) |r| {
        const src = img.data[r * img.w ..][0..img.w];
        const out = dst.buf[(y0 + r) * dst.stride ..][0..img.w];
        for (src, out) |s, *d| {
            if (s == 0) continue;
            d.* = if (s >= A.BLEND_BASE and s < A.BLEND_END) s + UNDER_RANK[d.*] else s;
        }
    }
}
