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
// Keys 1/2/3/4 (loader.js) play MOD / YM / sample / SNDH; the audio state (mode, YM regs,
// per-channel scopes) is mirrored into zigos by JS for the scope.
// --------------------------------------------------------------------------
const std = @import("std");

const zg = @import("zigos"); // the open ZigOS library (named module)
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const Console = zg.Console;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;
const Starfield3D = zg.Starfield3D;
const NB_STARS = 200;

const WIDTH: u16 = zg.WIDTH;
const HEIGHT: u16 = zg.HEIGHT;
const SCOPE_LEN: usize = zg.SCOPE_LEN;
// border geometry, for drawing the scrolltext into the borders ("fullscreen")
const HBORD: i32 = zg.HORIZONTAL_BORDERS_WIDTH; // 40
const VBORD: i32 = zg.VERTICAL_BORDERS_HEIGHT; // 40
const PW: i32 = zg.PHYSICAL_WIDTH; // 400
const PH: i32 = zg.PHYSICAL_HEIGHT; // 280

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
const LOGO_AMP: f32 = 8.0;

// Scope "electron flow": every FLOW_PERIOD frames a gradient band sweeps the
// curves right->left, colouring them with the chrome/lava gradient as it passes.
const FLOW_BASE: u8 = 16; // first of FLOW_N gradient palette entries on the scope plane
const FLOW_N: usize = 48;
const FLOW_BAND: f32 = 24.0; // half-width of the moving band (~48px pulse)
const FLOW_PERIOD: u32 = 300; // ~5s at 60fps
const FLOW_PULSE: u32 = 45; // frames the band takes to cross (fast)

// The moving band's colour: a single black -> lava -> black pulse (no repeat).
const FLOWGRAD = blk: {
    @setEvalBranchQuota(20000);
    const lava = [_][3]u8{ .{ 0, 0, 0 }, .{ 120, 16, 4 }, .{ 210, 40, 6 }, .{ 235, 120, 30 }, .{ 255, 210, 90 }, .{ 255, 240, 180 } };
    var t: [FLOW_N]Color = undefined;
    for (&t, 0..) |*c, k| {
        const tt = @as(f32, @floatFromInt(k)) / @as(f32, FLOW_N - 1);
        c.* = ramp(&lava, @sin(tt * std.math.pi)); // brightness 0..1..0
    }
    break :blk t;
};

// Interpolate a colour ramp (dark..bright key colours) at t in 0..1.
fn ramp(keys: []const [3]u8, t: f32) Color {
    const maxf = @as(f32, @floatFromInt(keys.len - 1));
    var ft = t * maxf;
    if (ft < 0) ft = 0;
    if (ft > maxf) ft = maxf;
    const lo: usize = @intFromFloat(ft);
    const hi = @min(keys.len - 1, lo + 1);
    const f = ft - @as(f32, @floatFromInt(lo));
    const a = keys[lo];
    const b = keys[hi];
    return Color{
        .r = @intFromFloat(@as(f32, @floatFromInt(a[0])) * (1 - f) + @as(f32, @floatFromInt(b[0])) * f),
        .g = @intFromFloat(@as(f32, @floatFromInt(a[1])) * (1 - f) + @as(f32, @floatFromInt(b[1])) * f),
        .b = @intFromFloat(@as(f32, @floatFromInt(a[2])) * (1 - f) + @as(f32, @floatFromInt(b[2])) * f),
        .a = 255,
    };
}

// Scrolltext raster gradient matching the TRSI logo: alternating metallic
// (teal-chrome) and lava (fire) bars, each a dark->bright->dark raster bar.
const COPPER = blk: {
    @setEvalBranchQuota(40000);
    const metal = [_][3]u8{ .{ 12, 22, 22 }, .{ 57, 89, 90 }, .{ 146, 168, 166 }, .{ 250, 252, 251 } };
    const lava = [_][3]u8{ .{ 40, 6, 3 }, .{ 195, 26, 4 }, .{ 214, 93, 31 }, .{ 238, 187, 71 }, .{ 255, 233, 131 } };
    const PERIOD = 64; // 32 metal + 32 lava
    var t: [256]Color = undefined;
    for (&t, 0..) |*c, i| {
        const pos = i % PERIOD;
        if (pos < 32) {
            const b = @sin(@as(f32, @floatFromInt(pos)) / 31.0 * std.math.pi);
            c.* = ramp(&metal, b);
        } else {
            const b = @sin(@as(f32, @floatFromInt(pos - 32)) / 31.0 * std.math.pi);
            c.* = ramp(&lava, b);
        }
    }
    break :blk t;
};

const MESSAGE =
    "WELCOME TO THE ZIGMACHINE MUSIC DEBUG SCREEN ....   " ++
    "ZIG + WASM POWERED OLDSKOOL SOUND !   " ++
    "REAL HARDWARE RASTERS, PAULA SAMPLE CHANNELS AND A YM2149 EMULATION ....   " ++
    "PRESS 1 FOR MOD, 2 FOR YM CHIPTUNE, 3 FOR A 12517 HZ DIGI SAMPLE STREAM, 4 FOR AN SNDH PLAYED BY ITS OWN 68000 ....   " ++
    "THE SCOPE FOLLOWS THE ACTIVE PLAYER ....   " ++
    "GREETINGS TO ALL TRSI MEMBERS AND ALL THE SCENERS OUT THERE ....   " ++
    "AND NOW... LET IT WRAP !                   ";

var raster_offset: u16 = 0;
var raster_phase: f32 = 0.0;

// Per-scanline HBL handler on the text plane: cycles the scrolltext colour
// through the copper gradient so the letters are raster-filled. Merged with
// the overscan trick: the scroller spills past 320px into the borders, so
// they must stay open every line too — both are per-scanline palette/latch
// writes with no pixel-column sensitivity, so they share this one HBL slot,
// registered at OVERSCAN_MAGIC_X (see docs/HW_API.md "Opening the borders").
fn scrollRasterHandler(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    _ = zigos;
    _ = col;
    fb.setPaletteEntry(SCROLL, COPPER[(line + raster_offset) % 256]);
    fb.flickerBorder();
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
            if (px < 0 or px >= fb.fb_w or py < 0 or py >= fb.fb_h) continue;
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
    flow_frame: u32 = 0, // scope electron-flow timer
    flow_pos: f32 = 0.0,
    flow_active: bool = false,
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
        // scope curves: medium-dark grey
        const scope_grey = Color{ .r = 90, .g = 90, .b = 96, .a = 255 };
        p1.setPaletteEntry(SCOPE[0], scope_grey);
        p1.setPaletteEntry(SCOPE[1], scope_grey);
        p1.setPaletteEntry(SCOPE[2], scope_grey);
        p1.setPaletteEntry(SCOPE[3], scope_grey);
        // flow gradient (chrome/lava, sampled from COPPER) for the sweeping pulse
        var k: usize = 0;
        while (k < FLOW_N) : (k += 1) {
            p1.setPaletteEntry(FLOW_BASE + @as(u8, @intCast(k)), FLOWGRAD[k]);
        }
        p1.clearFrameBuffer(0);

        // plane 2: menu + FULLSCREEN scroll text (its border columns hold the
        // scroller that spills past the 320px screen — real Option-B overscan,
        // no physical-framebuffer poke). Coordinates on this plane are PHYSICAL.
        var p2: *LogicalFB = &zigos.lfbs[2];
        p2.is_enabled = true;
        p2.setOverscanBuffer();
        p2.setPaletteEntry(CLEAR, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        p2.setPaletteEntry(WHITE, Color{ .r = 245, .g = 245, .b = 250, .a = 255 });
        p2.setPaletteEntry(YELLOW, Color{ .r = 255, .g = 220, .b = 90, .a = 255 });
        p2.setPaletteEntry(GREEN, Color{ .r = 130, .g = 240, .b = 150, .a = 255 });
        p2.setPaletteEntry(CYAN, Color{ .r = 130, .g = 210, .b = 250, .a = 255 });
        p2.setPaletteEntry(DIM, Color{ .r = 190, .g = 190, .b = 210, .a = 255 });
        p2.setPaletteEntry(SCROLL, COPPER[0]);
        p2.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, scrollRasterHandler); // raster-fill + overscan flicker
        p2.clearFrameBuffer(CLEAR);

        // plane 3: TRSI logo (its own palette, index 0 transparent), on top
        var p3: *LogicalFB = &zigos.lfbs[3];
        p3.is_enabled = true;
        p3.setPalette(trsi_pal);
        p3.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        // dimmed copies of the logo palette for the 3 darkening trail frames
        const trail_bases = [3]u8{ 32, 64, 96 };
        const trail_fac = [3]f32{ 0.5, 0.28, 0.14 };
        for (trail_bases, trail_fac) |base, f| {
            var i: u8 = 1;
            while (i < 32) : (i += 1) {
                const c = trsi_pal[i];
                p3.setPaletteEntry(base + i, Color{
                    .r = @intFromFloat(@as(f32, @floatFromInt(c.r)) * f),
                    .g = @intFromFloat(@as(f32, @floatFromInt(c.g)) * f),
                    .b = @intFromFloat(@as(f32, @floatFromInt(c.b)) * f),
                    .a = 255,
                });
            }
        }
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
        self.flow_frame +%= 1;
        raster_phase += RASTER_SPEED;
        if (raster_phase >= 4096.0) raster_phase -= 4096.0;
        raster_offset = @intFromFloat(raster_phase);
        self.starfield.update();
    }

    // Keys 1/2/3/4 pick MOD / YM / sample / SNDH — request BY NAME (host plays
    // it, no per-scene playlist in the glass). Files live under docs/music/.
    //
    // The SNDH is the odd one out and the point of having it here: the other
    // three are DATA the players interpret, while an SNDH is a PROGRAM — the
    // cart depacks it (Pack-Ice) and runs its 68000 code on Musashi, and the
    // scope below is then watching a real replay routine drive the chip.
    const TUNES = [_][]const u8{
        "lollapalooza.mod", "concerto.ymraw", "smp1.raw", "crystallized.sndh",
    };
    pub fn setShadeMode(self: *Demo, mode: u32) void {
        _ = self;
        if (mode < TUNES.len) zg.requestSong(TUNES[mode]);
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

        // plane 2 is FULLSCREEN, so coordinates are physical: the visible screen
        // sits at +HBORD,+VBORD (40,40), so menu text keeps its on-screen place.
        var p2: *LogicalFB = &zigos.lfbs[2];
        p2.clearFrameBuffer(CLEAR);
        const mx: i32 = 44 + HBORD; // = 84
        drawText8(p2, "1  MOD     LOLLAPALOOZA", mx, 92 + VBORD, WHITE, 2.5, self.phase);
        drawText8(p2, "2  YM2149  CONCERTO", mx, 106 + VBORD, WHITE, 2.5, self.phase + 0.4);
        drawText8(p2, "3  SAMPLE  DIGI 12517HZ", mx, 120 + VBORD, WHITE, 2.5, self.phase + 0.8);
        drawText8(p2, "4  SNDH    CRYSTALLIZED", mx, 134 + VBORD, WHITE, 2.5, self.phase + 1.2);
        drawText8(p2, "PRESS 1  2  3  4", mx, 154 + VBORD, WHITE, 2.5, self.phase + 1.6);
        self.drawScroller(zigos, p2);

        // plane 3: logo with a 3-frame darkening trail (oldest/darkest first)
        var p3: *LogicalFB = &zigos.lfbs[3];
        p3.clearFrameBuffer(0);
        self.drawTrsiLogo(p3, self.logo_phase - 2.4, 96);
        self.drawTrsiLogo(p3, self.logo_phase - 1.6, 64);
        self.drawTrsiLogo(p3, self.logo_phase - 0.8, 32);
        self.drawTrsiLogo(p3, self.logo_phase, 0);
    }

    // Draw the logo at distortion phase `lphase`, with palette entries offset by
    // `pal_base` (0 = full colour, 32/64/96 = the dimmer trail copies).
    fn drawTrsiLogo(self: *Demo, fb: *LogicalFB, lphase: f32, pal_base: u8) void {
        _ = self;
        const start_x: i32 = @intCast((WIDTH - LOGO_W) / 2);
        const base_y: i32 = -22; // crop the logo's ~25px top padding to sit near the top

        // horizontal distortion amplitude breathes over time (progress/regress)
        const hamp: f32 = (@sin(lphase * 0.7) * 0.5 + 0.5) * 10.0;
        var hoff: [LOGO_H]i32 = undefined;
        var r: usize = 0;
        while (r < LOGO_H) : (r += 1) {
            hoff[r] = @intFromFloat(@sin(@as(f32, @floatFromInt(r)) * 0.06 + lphase * 1.3) * hamp);
        }

        var px: usize = 0;
        while (px < LOGO_W) : (px += 1) {
            const dy: i32 = @intFromFloat(@sin(@as(f32, @floatFromInt(px)) * 0.03 + lphase) * LOGO_AMP);
            var py: usize = 0;
            while (py < LOGO_H) : (py += 1) {
                const idx = trsi_raw[py * LOGO_W + px];
                if (idx == 0) continue;
                const sx = start_x + @as(i32, @intCast(px)) + hoff[py];
                const sy = base_y + @as(i32, @intCast(py)) + dy;
                if (sx < 0 or sx >= WIDTH or sy < 0 or sy >= HEIGHT) continue;
                fb.setPixelValue(@intCast(sx), @intCast(sy), pal_base + idx);
            }
        }
    }

    // Fullscreen scroller, the SANCTIONED way (Option B): plane 2 is a fullscreen
    // (400×280) plane, so the scroller is just drawn across the full physical
    // width — the machine composites its border columns into the borders. No
    // physical-framebuffer poke. Coordinates are physical; the SCROLL palette
    // entry is raster-recoloured per scanline by scrollRasterHandler.
    fn drawScroller(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        _ = zigos;
        const y0: i32 = (HEIGHT - 28) + VBORD; // physical baseline
        const base_x: i32 = @as(i32, @intFromFloat(self.scroll_x)) + HBORD; // visible-space -> physical
        for (MESSAGE, 0..) |char, i| {
            const cx: i32 = base_x + @as(i32, @intCast(i * 16));
            if (cx <= -16 or cx >= PW) continue;
            self.drawScrollGlyph(fb, char, cx, y0);
        }
    }

    fn drawScrollGlyph(self: *Demo, fb: *LogicalFB, char: u8, x0: i32, y0: i32) void {
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
                if (lx < 0 or lx >= PW or ly < 0 or ly >= PH) continue;
                fb.setPixelValue(@intCast(lx), @intCast(ly), SCROLL);
            }
        }
    }

    fn drawScopes(self: *Demo, zigos: *ZigOS, fb: *LogicalFB) void {
        // update the sweeping "electron flow" band
        const inp = self.flow_frame % FLOW_PERIOD;
        self.flow_active = inp < FLOW_PULSE;
        if (self.flow_active) {
            const p = @as(f32, @floatFromInt(inp)) / @as(f32, FLOW_PULSE);
            // right -> left across the full width plus a band margin on each side
            self.flow_pos = (@as(f32, WIDTH) + FLOW_BAND) - p * (@as(f32, WIDTH) + 2 * FLOW_BAND);
        }
        switch (zigos.audio_mode) {
            2, 4 => self.drawYmScopes(zigos, fb), // YM dump and SNDH both drive the PSG
            1 => self.drawWaveScopes(zigos, fb, 4),
            3 => self.drawWaveScopes(zigos, fb, 1),
            else => {},
        }
    }

    // Palette entry for a scope column: grey normally, or the flowing gradient
    // where the sweeping band currently is.
    fn scopeColor(self: *Demo, ch: usize, x: usize) u8 {
        if (!self.flow_active) return SCOPE[ch];
        const d = @as(f32, @floatFromInt(x)) - self.flow_pos;
        if (@abs(d) > FLOW_BAND) return SCOPE[ch];
        const gi: usize = @intFromFloat((d + FLOW_BAND) / (2 * FLOW_BAND) * @as(f32, FLOW_N - 1));
        return FLOW_BASE + @as(u8, @intCast(gi));
    }

    fn drawWaveScopes(self: *Demo, zigos: *ZigOS, fb: *LogicalFB, n: usize) void {
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
                const col = self.scopeColor(ch, x);
                var yl = @min(prev, yy);
                const yh = @max(prev, yy);
                while (yl <= yh) : (yl += 1) {
                    if (yl >= 0 and yl < HEIGHT) fb.setPixelValue(@intCast(x), @intCast(yl), col);
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
                const col = self.scopeColor(ch, x);
                var yl = @min(prev, yy);
                const yh = @max(prev, yy);
                while (yl <= yh) : (yl += 1) {
                    if (yl >= 0 and yl < HEIGHT) fb.setPixelValue(@intCast(x), @intCast(yl), col);
                }
                prev = yy;
            }
        }
    }
};
