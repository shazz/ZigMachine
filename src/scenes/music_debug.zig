// --------------------------------------------------------------------------
// Music debug screen — a little demo in itself.
//
// Copper rasters + sine-distorted logo + a 3-trace YM oscilloscope + menu +
// bottom scrolltext. Playback is triggered from JS (loader.js keydown 1/2/3 ->
// playMod/playYm/playRaw); the YM registers are mirrored into zigos.ym_regs by
// JS each frame so the scope reflects the live chip.
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const Console = @import("../utils/debug.zig").Console;

const WIDTH: u16 = @import("../zigos.zig").WIDTH;
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;

// palette entries
const BG: u8 = 0;
const WHITE: u8 = 1;
const YELLOW: u8 = 2;
const GREEN: u8 = 3;
const CYAN: u8 = 4;
const DIM: u8 = 5;
const SCOPE = [3]u8{ 6, 7, 8 };
const COPPER_BASE: u8 = 100; // 16-entry copper gradient at 100..115
const COPPER_N: u8 = 16;

const SCROLL_SPEED: f32 = 1.5;
const LOGO = "ZIGMACHINE";
const LOGO_SCALE: usize = 3;
const LOGO_AMP: f32 = 6.0;
const RASTER_H: u16 = 46;

const MESSAGE =
    "WELCOME TO THE ZIGMACHINE MUSIC DEBUG SCREEN ....   " ++
    "ZIG + WASM POWERED OLDSKOOL SOUND !   " ++
    "PAULA SAMPLE CHANNELS AND A YM2149 EMULATION RUNNING IN AN AUDIOWORKLET ....   " ++
    "PRESS 1 FOR MOD, 2 FOR YM CHIPTUNE, 3 FOR A DIGI SAMPLE STREAM ....   " ++
    "WATCH THE THREE CURVES DANCE TO THE YM CHANNELS ....   " ++
    "GREETINGS TO MATT AND ALL THE SCENERS OUT THERE ....   " ++
    "AND NOW... LET IT WRAP !                   ";

fn hashRand(x: usize, seed: u32) f32 {
    var h: u32 = @as(u32, @truncate(x)) *% 2654435761 +% seed *% 40503;
    h ^= h >> 13;
    return @as(f32, @floatFromInt((h >> 8) & 0xFF)) / 255.0;
}

pub const Demo = struct {
    scroll_x: f32 = @floatFromInt(WIDTH),
    phase: f32 = 0.0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("music debug init", .{});
        self.scroll_x = @floatFromInt(WIDTH);
        self.phase = 0.0;

        zigos.setBackgroundColor(Color{ .r = 8, .g = 10, .b = 24, .a = 255 });

        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(BG, Color{ .r = 8, .g = 10, .b = 24, .a = 255 });
        fb.setPaletteEntry(WHITE, Color{ .r = 235, .g = 235, .b = 245, .a = 255 });
        fb.setPaletteEntry(YELLOW, Color{ .r = 250, .g = 210, .b = 70, .a = 255 });
        fb.setPaletteEntry(GREEN, Color{ .r = 120, .g = 230, .b = 140, .a = 255 });
        fb.setPaletteEntry(CYAN, Color{ .r = 110, .g = 200, .b = 245, .a = 255 });
        fb.setPaletteEntry(DIM, Color{ .r = 120, .g = 120, .b = 150, .a = 255 });
        fb.setPaletteEntry(SCOPE[0], Color{ .r = 240, .g = 100, .b = 110, .a = 255 });
        fb.setPaletteEntry(SCOPE[1], Color{ .r = 110, .g = 230, .b = 130, .a = 255 });
        fb.setPaletteEntry(SCOPE[2], Color{ .r = 120, .g = 160, .b = 245, .a = 255 });

        // copper gradient: dark-warm -> red -> orange -> yellow -> white
        var i: u8 = 0;
        while (i < COPPER_N) : (i += 1) {
            const t: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(COPPER_N - 1));
            const r: u8 = @intFromFloat(std.math.clamp(90.0 + t * 165.0, 0, 255));
            const g: u8 = @intFromFloat(std.math.clamp(t * t * 230.0, 0, 255));
            const b: u8 = @intFromFloat(std.math.clamp(t * t * t * 255.0, 0, 255));
            fb.setPaletteEntry(COPPER_BASE + i, Color{ .r = r, .g = g, .b = b, .a = 255 });
        }
        fb.clearFrameBuffer(BG);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {
        _ = zigos;
        _ = time_elapsed;
        self.scroll_x -= SCROLL_SPEED;
        const total: f32 = @floatFromInt(MESSAGE.len * 8);
        if (self.scroll_x < -total) self.scroll_x = @floatFromInt(WIDTH);
        self.phase += 0.15;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {
        _ = time_elapsed;
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.clearFrameBuffer(BG);

        self.drawRasters(fb);
        self.drawScopes(zigos, fb);
        self.drawLogo(zigos, fb);

        zigos.printText(fb, "M U S I C   D E B U G", 80, 54, DIM, BG);
        zigos.printText(fb, "1  MOD     LOLLAPALOOZA", 56, 72, WHITE, BG);
        zigos.printText(fb, "2  YM2149  CONCERTO", 56, 88, WHITE, BG);
        zigos.printText(fb, "3  SAMPLE  DIGI STREAM", 56, 104, WHITE, BG);
        zigos.printText(fb, "PRESS  1   2   3", 88, 122, GREEN, BG);

        self.drawScroller(zigos, fb);
    }

    // Copper raster bars behind the logo (top band), scrolling vertically.
    fn drawRasters(self: *Demo, fb: *LogicalFB) void {
        var y: u16 = 0;
        while (y < RASTER_H) : (y += 1) {
            const s = @sin(@as(f32, @floatFromInt(y)) * 0.20 + self.phase * 1.3);
            const idx: u8 = COPPER_BASE + @as(u8, @intFromFloat((s * 0.5 + 0.5) * @as(f32, COPPER_N - 1)));
            var x: u16 = 0;
            while (x < WIDTH) : (x += 1) fb.setPixelValue(x, y, idx);
        }
    }

    // Three oscilloscope traces (one per YM tone channel) driven by the live
    // registers: square for tone, jitter for noise, amplitude from volume.
    fn drawScopes(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        const cy = [3]u16{ 140, 154, 168 };
        const regs = &zigos.ym_regs;
        var ch: usize = 0;
        while (ch < 3) : (ch += 1) {
            const period: u16 = (@as(u16, regs[ch * 2 + 1] & 0x0F) << 8) | regs[ch * 2];
            const vreg = regs[8 + ch];
            const vol: f32 = if (vreg & 0x10 != 0) 12.0 else @floatFromInt(vreg & 0x0F);
            const amp = vol / 15.0 * 9.0;
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
                // connect to the previous sample so the trace is continuous
                var yl = @min(prev, yy);
                const yh = @max(prev, yy);
                while (yl <= yh) : (yl += 1) {
                    if (yl >= 0 and yl < HEIGHT) fb.setPixelValue(@intCast(x), @intCast(yl), SCOPE[ch]);
                }
                prev = yy;
            }
        }
    }

    fn drawScroller(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        const y0: u16 = HEIGHT - 12;
        const base_x: i32 = @intFromFloat(self.scroll_x);
        for (MESSAGE, 0..) |char, i| {
            const cx: i32 = base_x + @as(i32, @intCast(i)) * 8;
            if (cx <= -8 or cx >= WIDTH) continue;
            drawGlyph(zigos, fb, char, cx, y0, 1, CYAN);
        }
    }

    // Sine-distorted logo: each pixel column shifted vertically by a travelling wave.
    fn drawLogo(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        const glyph_w = 8 * LOGO_SCALE;
        const start_x: i32 = @intCast((WIDTH - LOGO.len * glyph_w) / 2);
        const base_y: i32 = 10;
        for (LOGO, 0..) |char, ci| {
            const glyph = @as(usize, char) * 64;
            var row: usize = 0;
            while (row < 8) : (row += 1) {
                var col: usize = 0;
                while (col < 8) : (col += 1) {
                    if (zigos.system_font[glyph + row * 8 + col] != 1) continue;
                    const gx: i32 = start_x + @as(i32, @intCast(ci * glyph_w + col * LOGO_SCALE));
                    const wob: f32 = @sin(@as(f32, @floatFromInt(gx)) * 0.045 + self.phase) * LOGO_AMP;
                    const gy: i32 = base_y + @as(i32, @intCast(row * LOGO_SCALE)) + @as(i32, @intFromFloat(wob));
                    plotBlock(fb, gx, gy, LOGO_SCALE, if (row < 3) YELLOW else CYAN);
                }
            }
        }
    }

    fn plotBlock(fb: *LogicalFB, x0: i32, y0: i32, scale: usize, color: u8) void {
        var sy: usize = 0;
        while (sy < scale) : (sy += 1) {
            var sx: usize = 0;
            while (sx < scale) : (sx += 1) {
                const px = x0 + @as(i32, @intCast(sx));
                const py = y0 + @as(i32, @intCast(sy));
                if (px < 0 or px >= WIDTH or py < 0 or py >= HEIGHT) continue;
                fb.setPixelValue(@intCast(px), @intCast(py), color);
            }
        }
    }

    fn drawGlyph(zigos: *ZigOS, fb: *LogicalFB, char: u8, x0: i32, y0: u16, scale: usize, color: u8) void {
        _ = scale;
        const glyph = @as(usize, char) * 64;
        var row: usize = 0;
        while (row < 8) : (row += 1) {
            var col: usize = 0;
            while (col < 8) : (col += 1) {
                if (zigos.system_font[glyph + row * 8 + col] != 1) continue;
                const px: i32 = x0 + @as(i32, @intCast(col));
                if (px < 0 or px >= WIDTH) continue;
                fb.setPixelValue(@intCast(px), y0 + @as(u16, @intCast(row)), color);
            }
        }
    }
};
