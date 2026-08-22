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
const Starfield3D = @import("../effects/starfield_3D.zig").Starfield3D;
const NB_STARS = 200;

const WIDTH: u16 = @import("../zigos.zig").WIDTH;
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const SCOPE_LEN: usize = @import("../zigos.zig").SCOPE_LEN;
// border geometry, for drawing the scrolltext into the borders ("fullscreen")
const HBORD: i32 = @import("../zigos.zig").HORIZONTAL_BORDERS_WIDTH; // 40
const VBORD: i32 = @import("../zigos.zig").VERTICAL_BORDERS_HEIGHT; // 40
const PW: i32 = @import("../zigos.zig").PHYSICAL_WIDTH; // 400
const PH: i32 = @import("../zigos.zig").PHYSICAL_HEIGHT; // 280

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
const SCROLL: u8 = 10; // scrolltext colour, raster-cycled per scanline
// plane 0 (scope) palette entries
const SCOPE = [4]u8{ 6, 7, 8, 9 };
const BGCOL = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

const RASTER_SPEED: f32 = 0.6; // scrolltext raster cycle speed (lower = slower)
const SCROLL_SPEED: f32 = 2.0;
const SCROLL_WAVE_AMP: f32 = 6.0; // vertical wobble of the scrolltext
const LOGO_AMP: f32 = 5.0;

// Full-spectrum rainbow, cycling ~every 24 entries, for the scrolltext rasters.
const COPPER = blk: {
    @setEvalBranchQuota(6000);
    var t: [256]Color = undefined;
    for (&t, 0..) |*c, i| {
        const a = @as(f32, @floatFromInt(i)) * 0.2618; // 2*pi/24
        c.* = Color{
            .r = @intFromFloat((@sin(a) * 0.5 + 0.5) * 255.0),
            .g = @intFromFloat((@sin(a + 2.0944) * 0.5 + 0.5) * 255.0),
            .b = @intFromFloat((@sin(a + 4.1888) * 0.5 + 0.5) * 255.0),
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
var raster_phase: f32 = 0.0;

// Per-scanline HBL handler on the text plane: cycles the scrolltext colour
// through the copper gradient so the letters are raster-filled.
fn scrollRasterHandler(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    _ = zigos;
    _ = col;
    fb.setPaletteEntry(SCROLL, COPPER[(line + raster_offset) % 256]);
}

fn hashRand(x: usize, seed: u32) f32 {
    var h: u32 = @as(u32, @truncate(x)) *% 2654435761 +% seed *% 40503;
    h ^= h >> 13;
    return @as(f32, @floatFromInt((h >> 8) & 0xFF)) / 255.0;
}

// One bitmap glyph from a 320-wide sheet of `cell`x`cell` cells (`per_row` cells
// per row), ASCII starting at space. Non-zero pixels drawn in `color`, clipped.
// Draw a glyph; `wave_amp`/`wave_phase` add a per-column vertical sine offset
// (0 for static text).
fn drawGlyph(sheet: []const u8, per_row: usize, cell: usize, char: u8, x0: i32, y0: i32, color: u8, wave_amp: f32, wave_phase: f32, fb: *LogicalFB) void {
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
            var py = y0 + @as(i32, @intCast(gy));
            if (wave_amp != 0) {
                py += @intFromFloat(@sin(@as(f32, @floatFromInt(px)) * 0.05 + wave_phase) * wave_amp);
            }
            if (px < 0 or px >= WIDTH or py < 0 or py >= HEIGHT) continue;
            fb.setPixelValue(@intCast(px), @intCast(py), color);
        }
    }
}

fn drawText8(fb: *LogicalFB, text: []const u8, x: i32, y: i32, color: u8, amp: f32, phase: f32) void {
    for (text, 0..) |c, i| drawGlyph(font8_raw, 40, 8, c, x + @as(i32, @intCast(i * 8)), y, color, amp, phase, fb);
}

pub const Demo = struct {
    scroll_x: f32 = @floatFromInt(WIDTH),
    phase: f32 = 0.0,
    logo_phase: f32 = 0.0, // slow, drives the logo distortion
    starfield: Starfield3D(NB_STARS) = undefined,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("music debug init", .{});
        self.scroll_x = @floatFromInt(WIDTH);
        self.phase = 0.0;
        raster_offset = 0;
        raster_phase = 0.0;
        zigos.setBackgroundColor(BGCOL); // black borders

        // plane 0: 3D starfield (back). init() sets its own brightness palette.
        var p0: *LogicalFB = &zigos.lfbs[0];
        p0.is_enabled = true;
        self.starfield = Starfield3D(NB_STARS).init(p0.getRenderTarget(), WIDTH, HEIGHT, 2, false);
        p0.setPaletteEntry(0, BGCOL); // black background
        p0.clearFrameBuffer(0);

        // plane 1: scope (transparent bg so the starfield shows through)
        var p1: *LogicalFB = &zigos.lfbs[1];
        p1.is_enabled = true;
        p1.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        p1.setPaletteEntry(SCOPE[0], Color{ .r = 250, .g = 250, .b = 255, .a = 255 });
        p1.setPaletteEntry(SCOPE[1], Color{ .r = 150, .g = 255, .b = 130, .a = 255 });
        p1.setPaletteEntry(SCOPE[2], Color{ .r = 120, .g = 220, .b = 255, .a = 255 });
        p1.setPaletteEntry(SCOPE[3], Color{ .r = 255, .g = 200, .b = 120, .a = 255 });
        p1.clearFrameBuffer(0);

        // plane 2: menu + scroll text
        var p2: *LogicalFB = &zigos.lfbs[2];
        p2.is_enabled = true;
        p2.setPaletteEntry(CLEAR, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        p2.setPaletteEntry(WHITE, Color{ .r = 245, .g = 245, .b = 250, .a = 255 });
        p2.setPaletteEntry(YELLOW, Color{ .r = 255, .g = 220, .b = 90, .a = 255 });
        p2.setPaletteEntry(GREEN, Color{ .r = 130, .g = 240, .b = 150, .a = 255 });
        p2.setPaletteEntry(CYAN, Color{ .r = 130, .g = 210, .b = 250, .a = 255 });
        p2.setPaletteEntry(DIM, Color{ .r = 190, .g = 190, .b = 210, .a = 255 });
        p2.setPaletteEntry(SCROLL, COPPER[0]);
        p2.setFrameBufferHBLHandler(0, scrollRasterHandler); // raster-fill the scroller
        p2.clearFrameBuffer(CLEAR);

        // plane 3: TRSI logo (its own palette, index 0 transparent), on top
        var p3: *LogicalFB = &zigos.lfbs[3];
        p3.is_enabled = true;
        p3.setPalette(trsi_pal);
        p3.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        p3.clearFrameBuffer(0);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {
        _ = zigos;
        _ = time_elapsed;
        self.scroll_x -= SCROLL_SPEED;
        const total: f32 = @floatFromInt(MESSAGE.len * 16);
        if (self.scroll_x < -total) self.scroll_x = @floatFromInt(WIDTH);
        self.phase += 0.15;
        self.logo_phase += 0.045; // slower logo movement
        raster_phase += RASTER_SPEED;
        if (raster_phase >= 4096.0) raster_phase -= 4096.0;
        raster_offset = @intFromFloat(raster_phase);
        self.starfield.update();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, time_elapsed: f32) void {
        _ = time_elapsed;

        // plane 0: starfield
        var p0: *LogicalFB = &zigos.lfbs[0];
        p0.clearFrameBuffer(0);
        self.starfield.render();

        // plane 1: scope
        var p1: *LogicalFB = &zigos.lfbs[1];
        p1.clearFrameBuffer(0);
        self.drawScopes(zigos, p1);

        // plane 2: menu (vertically centred block) + scroll text
        var p2: *LogicalFB = &zigos.lfbs[2];
        p2.clearFrameBuffer(CLEAR);
        drawText8(p2, "1  MOD     LOLLAPALOOZA", 44, 92, WHITE, 2.5, self.phase);
        drawText8(p2, "2  YM2149  CONCERTO", 44, 106, WHITE, 2.5, self.phase + 0.4);
        drawText8(p2, "3  SAMPLE  DIGI STREAM", 44, 120, WHITE, 2.5, self.phase + 0.8);
        drawText8(p2, "PRESS 1  2  3", 108, 140, GREEN, 2.5, self.phase + 1.2);
        self.drawScroller(zigos, p2);

        // plane 3: logo (top)
        var p3: *LogicalFB = &zigos.lfbs[3];
        p3.clearFrameBuffer(0);
        self.drawTrsiLogo(p3);
    }

    fn drawTrsiLogo(self: *Demo, fb: *LogicalFB) void {
        const start_x: i32 = @intCast((WIDTH - LOGO_W) / 2);
        const base_y: i32 = -22; // crop the logo's ~25px top padding to sit near the top

        // horizontal distortion amplitude breathes over time (progress/regress)
        const hamp: f32 = (@sin(self.logo_phase * 0.7) * 0.5 + 0.5) * 10.0;
        var hoff: [LOGO_H]i32 = undefined;
        var r: usize = 0;
        while (r < LOGO_H) : (r += 1) {
            hoff[r] = @intFromFloat(@sin(@as(f32, @floatFromInt(r)) * 0.06 + self.logo_phase * 1.3) * hamp);
        }

        var px: usize = 0;
        while (px < LOGO_W) : (px += 1) {
            const dy: i32 = @intFromFloat(@sin(@as(f32, @floatFromInt(px)) * 0.03 + self.logo_phase) * LOGO_AMP);
            var py: usize = 0;
            while (py < LOGO_H) : (py += 1) {
                const idx = trsi_raw[py * LOGO_W + px];
                if (idx == 0) continue;
                const sx = start_x + @as(i32, @intCast(px)) + hoff[py];
                const sy = base_y + @as(i32, @intCast(py)) + dy;
                if (sx < 0 or sx >= WIDTH or sy < 0 or sy >= HEIGHT) continue;
                fb.setPixelValue(@intCast(sx), @intCast(sy), idx);
            }
        }
    }

    // "Fullscreen" scroller: the visible span is drawn on the text plane (rainbow
    // via the HBL palette), while the parts that spill into the left/right borders
    // are written straight into the physical framebuffer (which the per-plane
    // render never touches) — a border-overscan hack of the machine.
    fn drawScroller(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        const y0: i32 = HEIGHT - 18;
        const base_x: i32 = @intFromFloat(self.scroll_x);
        for (MESSAGE, 0..) |char, i| {
            const cx: i32 = base_x + @as(i32, @intCast(i * 16));
            if (cx <= -HBORD - 16 or cx >= WIDTH + HBORD) continue;
            self.drawScrollGlyph(zigos, fb, char, cx, y0);
        }
    }

    fn drawScrollGlyph(self: *Demo, zigos: *ZigOS, fb: *LogicalFB, char: u8, x0: i32, y0: i32) void {
        const count = 20 * ((font16_raw.len / 320) / 16);
        const gidx: usize = if (char >= 32 and char < 32 + count) char - 32 else 0;
        const scx = (gidx % 20) * 16;
        const scy = (gidx / 20) * 16;
        var gy: usize = 0;
        while (gy < 16) : (gy += 1) {
            var gx: usize = 0;
            while (gx < 16) : (gx += 1) {
                if (font16_raw[(scy + gy) * 320 + scx + gx] == 0) continue;
                const lx = x0 + @as(i32, @intCast(gx));
                const ly = y0 + @as(i32, @intCast(gy)) +
                    @as(i32, @intFromFloat(@sin(@as(f32, @floatFromInt(lx)) * 0.05 + self.phase) * SCROLL_WAVE_AMP));
                if (ly < 0 or ly >= HEIGHT) continue;
                if (lx >= 0 and lx < WIDTH) {
                    fb.setPixelValue(@intCast(lx), @intCast(ly), SCROLL); // visible: plane
                } else if (lx >= -HBORD and lx < WIDTH + HBORD) {
                    const phx = lx + HBORD; // borders: straight to the physical framebuffer
                    const phy = ly + VBORD;
                    if (phx >= 0 and phx < PW and phy >= 0 and phy < PH) {
                        const col = COPPER[(@as(usize, @intCast(phy)) + raster_offset) % 256];
                        zigos.physical_framebuffer[@intCast(phy)][@intCast(phx)] = col.toRGBA();
                    }
                }
            }
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
