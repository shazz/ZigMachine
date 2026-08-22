// --------------------------------------------------------------------------
// Music debug screen — a little demo in itself.
//
// Real hardware-style rasters (per-scanline palette[0] change via an HBL
// handler) + sine-distorted logo + a 3-trace YM oscilloscope + menu + bottom
// scrolltext. Two planes: plane 0 = rasters + scope (behind), plane 1 = the
// logo/menu/scroll text on top (transparent background).
//
// Keys 1/2/3 (handled in loader.js) play MOD / YM / sample; the YM registers
// are mirrored into zigos.ym_regs by JS so the scope reflects the live chip.
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const Console = @import("../utils/debug.zig").Console;

const WIDTH: u16 = @import("../zigos.zig").WIDTH;
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;

// plane 1 (text) palette entries
const CLEAR: u8 = 0;
const WHITE: u8 = 1;
const YELLOW: u8 = 2;
const GREEN: u8 = 3;
const CYAN: u8 = 4;
const DIM: u8 = 5;
// plane 0 (scope) palette entries (0 = raster, set per scanline)
const SCOPE = [3]u8{ 6, 7, 8 };

const SCROLL_SPEED: f32 = 1.5;
const LOGO = "ZIGMACHINE";
const LOGO_SCALE: usize = 3;
const LOGO_AMP: f32 = 6.0;

// Copper gradient table (dark warm bars, so the bright scope stays readable),
// indexed per scanline for the raster effect.
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
    "WATCH THE THREE CURVES DANCE TO THE YM CHANNELS ....   " ++
    "GREETINGS TO MATT AND ALL THE SCENERS OUT THERE ....   " ++
    "AND NOW... LET IT WRAP !                   ";

// Animated raster scroll offset — read by the (static) HBL handler.
var raster_offset: u16 = 0;

// Per-plane HBL handler: rasters in the visible area (plane 0 background).
fn rasterHandler(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    _ = zigos;
    _ = col;
    fb.setPaletteEntry(0, COPPER[(line + raster_offset) % 256]);
}

// Global HBL handler: same rasters in the borders (physical background color).
fn borderRasterHandler(zigos: *ZigOS, line: u16) void {
    zigos.setBackgroundColor(COPPER[(line + raster_offset) % 256]);
}

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
        raster_offset = 0;

        // plane 0: rasters (palette[0] set per scanline) + scope
        var p0: *LogicalFB = &zigos.lfbs[0];
        p0.is_enabled = true;
        p0.setFrameBufferHBLHandler(0, rasterHandler); // visible-area rasters
        zigos.setHBLHandler(borderRasterHandler); // border rasters
        p0.setPaletteEntry(0, COPPER[0]);
        p0.setPaletteEntry(SCOPE[0], Color{ .r = 250, .g = 250, .b = 255, .a = 255 }); // white
        p0.setPaletteEntry(SCOPE[1], Color{ .r = 150, .g = 255, .b = 130, .a = 255 }); // green
        p0.setPaletteEntry(SCOPE[2], Color{ .r = 120, .g = 220, .b = 255, .a = 255 }); // cyan
        p0.clearFrameBuffer(0);

        // plane 1: text/logo on a transparent background
        var p1: *LogicalFB = &zigos.lfbs[1];
        p1.is_enabled = true;
        p1.setPaletteEntry(CLEAR, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        p1.setPaletteEntry(WHITE, Color{ .r = 245, .g = 245, .b = 250, .a = 255 });
        p1.setPaletteEntry(YELLOW, Color{ .r = 255, .g = 220, .b = 90, .a = 255 });
        p1.setPaletteEntry(GREEN, Color{ .r = 130, .g = 240, .b = 150, .a = 255 });
        p1.setPaletteEntry(CYAN, Color{ .r = 130, .g = 210, .b = 250, .a = 255 });
        p1.setPaletteEntry(DIM, Color{ .r = 180, .g = 180, .b = 200, .a = 255 });
        p1.clearFrameBuffer(CLEAR);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {
        _ = zigos;
        _ = time_elapsed;
        self.scroll_x -= SCROLL_SPEED;
        const total: f32 = @floatFromInt(MESSAGE.len * 8);
        if (self.scroll_x < -total) self.scroll_x = @floatFromInt(WIDTH);
        self.phase += 0.15;
        raster_offset +%= 2;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {
        _ = time_elapsed;

        // plane 0: raster background (palette[0]) + scope behind everything
        var p0: *LogicalFB = &zigos.lfbs[0];
        p0.clearFrameBuffer(0);
        self.drawScopes(zigos, p0);

        // plane 1: logo + menu + scroll on transparent background
        var p1: *LogicalFB = &zigos.lfbs[1];
        p1.clearFrameBuffer(CLEAR);
        self.drawLogo(zigos, p1);
        zigos.printText(p1, "M U S I C   D E B U G", 80, 46, DIM, CLEAR);
        zigos.printText(p1, "1  MOD     LOLLAPALOOZA", 56, 64, WHITE, CLEAR);
        zigos.printText(p1, "2  YM2149  CONCERTO", 56, 80, WHITE, CLEAR);
        zigos.printText(p1, "3  SAMPLE  DIGI STREAM", 56, 96, WHITE, CLEAR);
        zigos.printText(p1, "PRESS  1   2   3", 88, 116, GREEN, CLEAR);
        self.drawScroller(zigos, p1);
    }

    // Three oscilloscope traces (one per YM tone channel), spread over the screen
    // behind the text: square for tone, jitter for noise, amplitude from volume.
    fn drawScopes(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
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

    fn drawScroller(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        const y0: u16 = HEIGHT - 12;
        const base_x: i32 = @intFromFloat(self.scroll_x);
        for (MESSAGE, 0..) |char, i| {
            const cx: i32 = base_x + @as(i32, @intCast(i)) * 8;
            if (cx <= -8 or cx >= WIDTH) continue;
            drawGlyph(zigos, fb, char, cx, y0, CYAN);
        }
    }

    // Sine-distorted logo: each pixel column shifted vertically by a travelling wave.
    fn drawLogo(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        const glyph_w = 8 * LOGO_SCALE;
        const start_x: i32 = @intCast((WIDTH - LOGO.len * glyph_w) / 2);
        const base_y: i32 = 8;
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

    fn drawGlyph(zigos: *ZigOS, fb: *LogicalFB, char: u8, x0: i32, y0: u16, color: u8) void {
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
