// --------------------------------------------------------------------------
// Music debug screen — a little demo in itself.
//
// Real hardware rasters (per-scanline palette[0] + border background) + a
// sine-distorted TRSI logo + a player-adaptive YM/MOD/sample oscilloscope +
// an 8x8-font menu + a 16x16-font bottom scrolltext. Three planes:
//   plane 0 = rasters + scope (behind)
//   plane 1 = menu + scrolltext (transparent bg)
//   plane 2 = TRSI logo (transparent bg, on top)
//
// Keys 1/2/3 (loader.js) play MOD / YM / sample; the audio state (mode, YM regs,
// per-channel scopes) is mirrored into zigos by JS for the scope.
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const Console = @import("../utils/debug.zig").Console;
const convertU8ArraytoColors = @import("../utils/loaders.zig").convertU8ArraytoColors;

const WIDTH: u16 = @import("../zigos.zig").WIDTH;
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const SCOPE_LEN: usize = @import("../zigos.zig").SCOPE_LEN;

// TRSI logo + bitmap fonts.
const trsi_raw = @embedFile("../assets/logo/trsi.raw");
const trsi_pal = convertU8ArraytoColors(@embedFile("../assets/logo/trsi_pal.dat"));
const LOGO_W: usize = 208;
const LOGO_H: usize = 109;
const font16_raw = @embedFile("../assets/fonts/font16.raw"); // 320x48, 20x3 cells of 16x16
const font8_raw = @embedFile("../assets/fonts/font8.raw"); // 320x16, 40x2 cells of 8x8

// plane 1 (text) palette entries
const CLEAR: u8 = 0;
const WHITE: u8 = 1;
const YELLOW: u8 = 2;
const GREEN: u8 = 3;
const CYAN: u8 = 4;
const DIM: u8 = 5;
// plane 0 (scope) palette entries (0 = raster, set per scanline)
const SCOPE = [4]u8{ 6, 7, 8, 9 };

const RASTER_STEP: u16 = 2;
const SCROLL_SPEED: f32 = 2.0;
const LOGO_AMP: f32 = 5.0;

const COPPER = blk: {
    @setEvalBranchQuota(4000);
    var t: [256]Color = undefined;
    for (&t, 0..) |*c, i| {
        const s = (@sin(@as(f32, @floatFromInt(i)) * 0.098) * 0.5 + 0.5);
        c.* = Color{
            .r = @intFromFloat(std.math.clamp(16.0 + s * 120.0, 0, 255)),
            .g = @intFromFloat(std.math.clamp(s * s * 44.0, 0, 255)),
            .b = @intFromFloat(std.math.clamp(24.0 + s * s * 60.0, 0, 255)),
            .a = 255,
        };
    }
    break :blk t;
};

const MESSAGE =
    "WELCOME TO THE ZIGMACHINE MUSIC DEBUG SCREEN ....   " ++
    "ZIG + WASM POWERED OLDSKOOL SOUND !   " ++
    "REAL HARDWARE RASTERS, PAULA SAMPLE CHANNELS AND A YM2149 EMULATION ....   " ++
    "PRESS 1 FOR MOD, 2 FOR YM CHIPTUNE, 3 FOR A DIGI SAMPLE STREAM ....   " ++
    "THE SCOPE FOLLOWS THE ACTIVE PLAYER ....   " ++
    "GREETINGS TO MATT AND ALL THE SCENERS OUT THERE ....   " ++
    "AND NOW... LET IT WRAP !                   ";

var raster_offset: u16 = 0;

fn rasterHandler(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    _ = zigos;
    _ = col;
    fb.setPaletteEntry(0, COPPER[(line + raster_offset) % 256]);
}

fn borderRasterHandler(zigos: *ZigOS, line: u16) void {
    // clear() runs before update(); +RASTER_STEP predicts this frame's offset.
    zigos.setBackgroundColor(COPPER[(line + raster_offset + RASTER_STEP) % 256]);
}

fn hashRand(x: usize, seed: u32) f32 {
    var h: u32 = @as(u32, @truncate(x)) *% 2654435761 +% seed *% 40503;
    h ^= h >> 13;
    return @as(f32, @floatFromInt((h >> 8) & 0xFF)) / 255.0;
}

// One bitmap glyph from a 320-wide sheet of `cell`x`cell` cells (`per_row` cells
// per row), ASCII starting at space. Non-zero pixels drawn in `color`, clipped.
fn drawGlyph(sheet: []const u8, per_row: usize, cell: usize, char: u8, x0: i32, y0: i32, color: u8, fb: *LogicalFB) void {
    const rows = (sheet.len / 320) / cell; // sheet is 320 wide
    const count = per_row * rows;
    const idx: usize = if (char >= 32 and char < 32 + count) char - 32 else 0;
    const cx = (idx % per_row) * cell;
    const cy = (idx / per_row) * cell;
    var gy: usize = 0;
    while (gy < cell) : (gy += 1) {
        var gx: usize = 0;
        while (gx < cell) : (gx += 1) {
            if (sheet[(cy + gy) * 320 + cx + gx] == 0) continue;
            const px = x0 + @as(i32, @intCast(gx));
            const py = y0 + @as(i32, @intCast(gy));
            if (px < 0 or px >= WIDTH or py < 0 or py >= HEIGHT) continue;
            fb.setPixelValue(@intCast(px), @intCast(py), color);
        }
    }
}

fn drawText8(fb: *LogicalFB, text: []const u8, x: i32, y: i32, color: u8) void {
    for (text, 0..) |c, i| drawGlyph(font8_raw, 40, 8, c, x + @as(i32, @intCast(i * 8)), y, color, fb);
}

pub const Demo = struct {
    scroll_x: f32 = @floatFromInt(WIDTH),
    phase: f32 = 0.0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("music debug init", .{});
        self.scroll_x = @floatFromInt(WIDTH);
        self.phase = 0.0;
        raster_offset = 0;

        // plane 0: rasters + scope
        var p0: *LogicalFB = &zigos.lfbs[0];
        p0.is_enabled = true;
        p0.setFrameBufferHBLHandler(0, rasterHandler);
        zigos.setHBLHandler(borderRasterHandler);
        p0.setPaletteEntry(0, COPPER[0]);
        p0.setPaletteEntry(SCOPE[0], Color{ .r = 250, .g = 250, .b = 255, .a = 255 });
        p0.setPaletteEntry(SCOPE[1], Color{ .r = 150, .g = 255, .b = 130, .a = 255 });
        p0.setPaletteEntry(SCOPE[2], Color{ .r = 120, .g = 220, .b = 255, .a = 255 });
        p0.setPaletteEntry(SCOPE[3], Color{ .r = 255, .g = 200, .b = 120, .a = 255 });
        p0.clearFrameBuffer(0);

        // plane 1: menu + scroll text
        var p1: *LogicalFB = &zigos.lfbs[1];
        p1.is_enabled = true;
        p1.setPaletteEntry(CLEAR, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        p1.setPaletteEntry(WHITE, Color{ .r = 245, .g = 245, .b = 250, .a = 255 });
        p1.setPaletteEntry(YELLOW, Color{ .r = 255, .g = 220, .b = 90, .a = 255 });
        p1.setPaletteEntry(GREEN, Color{ .r = 130, .g = 240, .b = 150, .a = 255 });
        p1.setPaletteEntry(CYAN, Color{ .r = 130, .g = 210, .b = 250, .a = 255 });
        p1.setPaletteEntry(DIM, Color{ .r = 190, .g = 190, .b = 210, .a = 255 });
        p1.clearFrameBuffer(CLEAR);

        // plane 2: TRSI logo (its own palette, index 0 transparent)
        var p2: *LogicalFB = &zigos.lfbs[2];
        p2.is_enabled = true;
        p2.setPalette(trsi_pal);
        p2.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        p2.clearFrameBuffer(0);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {
        _ = zigos;
        _ = time_elapsed;
        self.scroll_x -= SCROLL_SPEED;
        const total: f32 = @floatFromInt(MESSAGE.len * 16);
        if (self.scroll_x < -total) self.scroll_x = @floatFromInt(WIDTH);
        self.phase += 0.15;
        raster_offset +%= RASTER_STEP;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {
        _ = time_elapsed;

        var p0: *LogicalFB = &zigos.lfbs[0];
        p0.clearFrameBuffer(0);
        self.drawScopes(zigos, p0);

        var p1: *LogicalFB = &zigos.lfbs[1];
        p1.clearFrameBuffer(CLEAR);
        drawText8(p1, "1  MOD     LOLLAPALOOZA", 44, 122, WHITE);
        drawText8(p1, "2  YM2149  CONCERTO", 44, 134, WHITE);
        drawText8(p1, "3  SAMPLE  DIGI STREAM", 44, 146, WHITE);
        drawText8(p1, "PRESS 1  2  3", 108, 162, GREEN);
        self.drawScroller(p1);

        var p2: *LogicalFB = &zigos.lfbs[2];
        p2.clearFrameBuffer(0);
        self.drawTrsiLogo(p2);
    }

    fn drawTrsiLogo(self: *Demo, fb: *LogicalFB) void {
        const start_x: i32 = @intCast((WIDTH - LOGO_W) / 2);
        const base_y: i32 = 6;
        var px: usize = 0;
        while (px < LOGO_W) : (px += 1) {
            const wob: f32 = @sin(@as(f32, @floatFromInt(px)) * 0.03 + self.phase) * LOGO_AMP;
            const dy: i32 = @intFromFloat(wob);
            var py: usize = 0;
            while (py < LOGO_H) : (py += 1) {
                const idx = trsi_raw[py * LOGO_W + px];
                if (idx == 0) continue;
                const sx = start_x + @as(i32, @intCast(px));
                const sy = base_y + @as(i32, @intCast(py)) + dy;
                if (sx < 0 or sx >= WIDTH or sy < 0 or sy >= HEIGHT) continue;
                fb.setPixelValue(@intCast(sx), @intCast(sy), idx);
            }
        }
    }

    fn drawScroller(self: *Demo, fb: *LogicalFB) void {
        const y0: i32 = HEIGHT - 18;
        const base_x: i32 = @intFromFloat(self.scroll_x);
        for (MESSAGE, 0..) |char, i| {
            const cx: i32 = base_x + @as(i32, @intCast(i * 16));
            if (cx <= -16 or cx >= WIDTH) continue;
            drawGlyph(font16_raw, 20, 16, char, cx, y0, CYAN, fb);
        }
    }

    fn drawScopes(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        switch (zigos.audio_mode) {
            2 => self.drawYmScopes(zigos, fb),
            1 => drawWaveScopes(zigos, fb, 4),
            3 => drawWaveScopes(zigos, fb, 1),
            else => {},
        }
    }

    fn drawWaveScopes(zigos: *ZigOS, fb: *LogicalFB, n: usize) void {
        const top: i32 = 42;
        const band: i32 = @divTrunc(@as(i32, HEIGHT - 60), @as(i32, @intCast(n)));
        const amp: f32 = if (n == 1) 46.0 else @as(f32, @floatFromInt(band)) * 0.42;
        var ch: usize = 0;
        while (ch < n) : (ch += 1) {
            const cy: i32 = top + band * @as(i32, @intCast(ch)) + @divTrunc(band, 2);
            const samples = &zigos.scopes[ch];
            var prev: i32 = cy;
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const idx = x * SCOPE_LEN / WIDTH;
                const yy: i32 = cy + @as(i32, @intFromFloat(samples[idx] * amp));
                var yl = @min(prev, yy);
                const yh = @max(prev, yy);
                while (yl <= yh) : (yl += 1) {
                    if (yl >= 0 and yl < HEIGHT) fb.setPixelValue(@intCast(x), @intCast(yl), SCOPE[ch]);
                }
                prev = yy;
            }
        }
    }

    fn drawYmScopes(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        const cy = [3]u16{ 66, 108, 150 };
        const regs = &zigos.ym_regs;
        var ch: usize = 0;
        while (ch < 3) : (ch += 1) {
            const period: u16 = (@as(u16, regs[ch * 2 + 1] & 0x0F) << 8) | regs[ch * 2];
            const vreg = regs[8 + ch];
            const vol: f32 = if (vreg & 0x10 != 0) 13.0 else @floatFromInt(vreg & 0x0F);
            const amp = vol / 15.0 * 20.0;
            const tone_on = (regs[7] >> @intCast(ch)) & 1 == 0;
            const noise_on = (regs[7] >> @intCast(ch + 3)) & 1 == 0;
            const wl = std.math.clamp(@as(f32, @floatFromInt(if (period == 0) 1 else period)) / 14.0, 3.0, 130.0);
            const seed: u32 = @intFromFloat(self.phase * 7.0);

            var prev: i32 = cy[ch];
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                var v: f32 = 0;
                if (tone_on) {
                    const s = @sin(@as(f32, @floatFromInt(x)) / wl * 6.2831853 + self.phase * 3.0);
                    v = if (s >= 0) amp else -amp;
                }
                if (noise_on) {
                    const nz = (hashRand(x, seed) * 2.0 - 1.0) * amp;
                    v = if (tone_on) v + nz * 0.4 else nz;
                }
                const yy: i32 = @as(i32, cy[ch]) + @as(i32, @intFromFloat(v));
                var yl = @min(prev, yy);
                const yh = @max(prev, yy);
                while (yl <= yh) : (yl += 1) {
                    if (yl >= 0 and yl < HEIGHT) fb.setPixelValue(@intCast(x), @intCast(yl), SCOPE[ch]);
                }
                prev = yy;
            }
        }
    }
};
