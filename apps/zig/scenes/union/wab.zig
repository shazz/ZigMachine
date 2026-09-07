// --------------------------------------------------------------------------
// Union intro — WAB logo part. 33x33 tiles fly in from random positions WHILE
// ROTATING (~720deg over 110 vbl), assembling the logo; then it fades out.
// Faithful to eflogowabentry.js (isRotated=true) + eflogowab.js.
//
// Asset: eflogowab5.png (264x264 RGBA) quantized + scaled to 128x128 indexed,
// so 16x16 tiles (8x8 grid) divide cleanly. Rotation uses an inverse-mapped
// blit (iterate dest, sample source) so there are no gaps.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const WIDTH: i32 = @intCast(zg.WIDTH);
const HEIGHT: i32 = @intCast(zg.HEIGHT);

const LOGO: usize = 128; // wab.raw is 128x128
const TS: usize = 16; // tile size
const NX: usize = LOGO / TS; // 8
const NT: usize = NX * NX; // 64 tiles
const OX: i32 = (WIDTH - @as(i32, @intCast(LOGO))) >> 1; // 96
const OY: i32 = (HEIGHT - @as(i32, @intCast(LOGO))) >> 1; // 36
const MOVE: f32 = 110.0; // vbl a tile takes to reach home (generateTilesHelper speed)
const SPINS: f32 = 720.0; // degrees over the move (2 turns -> ends aligned)
const STAGGER: u16 = 40;
const ENTRY_END: u32 = 160; // STAGGER + MOVE + hold
const ALPHA_INCR: f32 = 0.005;
const DEG: f32 = std.math.pi / 180.0;

const wab_raw = @embedFile("../../assets/screens/union_intro/wab.raw");
const wab_pal = convertU8ArraytoColors(@embedFile("../../assets/screens/union_intro/wab_pal.dat"));
const BG = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

const Phase = enum { entry, fade };

pub const Part = struct {
    phase: Phase = .entry,
    t: u32 = 0,
    fade: f32 = 1.0,
    sx: [NT]f32 = undefined,
    sy: [NT]f32 = undefined,
    svbl: [NT]u16 = undefined,

    pub fn init(self: *Part, zigos: *ZigOS) void {
        self.* = .{};
        var prng = std.Random.DefaultPrng.init(0x77ab5);
        const rnd = prng.random();
        var i: usize = 0;
        while (i < NT) : (i += 1) {
            self.sx[i] = rnd.float(f32) * @as(f32, @floatFromInt(WIDTH));
            self.sy[i] = rnd.float(f32) * @as(f32, @floatFromInt(HEIGHT));
            self.svbl[i] = rnd.intRangeAtMost(u16, 0, STAGGER);
        }
        zigos.setBackgroundColor(BG);
        const p0: *LogicalFB = &zigos.lfbs[0];
        p0.is_enabled = true;
        p0.setPalette(wab_pal);
        p0.setPaletteEntry(0, BG);
    }

    pub fn update(self: *Part, zigos: *ZigOS, dt: f32) bool {
        _ = dt;
        switch (self.phase) {
            .entry => {
                self.t += 1;
                if (self.t >= ENTRY_END) self.phase = .fade;
            },
            .fade => {
                self.fade = @max(0.0, self.fade - ALPHA_INCR);
                self.applyFade(zigos);
                if (self.fade <= 0.0) return true;
            },
        }
        return false;
    }

    pub fn render(self: *Part, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const p0: *LogicalFB = &zigos.lfbs[0];
        p0.clearFrameBuffer(0);
        if (self.phase == .entry) self.drawEntry(p0) else drawWhole(p0);
    }

    fn drawEntry(self: *Part, fb: *LogicalFB) void {
        var i: usize = 0;
        while (i < NT) : (i += 1) {
            if (self.t <= self.svbl[i]) continue;
            const tx = i % NX;
            const ty = i / NX;
            const home_x: f32 = @floatFromInt(OX + @as(i32, @intCast(tx * TS)));
            const home_y: f32 = @floatFromInt(OY + @as(i32, @intCast(ty * TS)));
            var p: f32 = @as(f32, @floatFromInt(self.t - self.svbl[i])) / MOVE;
            if (p > 1.0) p = 1.0;
            const cx = self.sx[i] + (home_x - self.sx[i]) * p;
            const cy = self.sy[i] + (home_y - self.sy[i]) * p;
            drawTileRot(fb, tx, ty, cx, cy, SPINS * p * DEG);
        }
    }

    // Draw a 16x16 tile rotated `ang` radians about its centre at (cx,cy).
    fn drawTileRot(fb: *LogicalFB, tx: usize, ty: usize, cx: f32, cy: f32, ang: f32) void {
        const cs = std.math.cos(ang);
        const sn = std.math.sin(ang);
        const half: f32 = @floatFromInt(TS / 2);
        const ccx = cx + half;
        const ccy = cy + half;
        const R: i32 = 12; // dest bbox radius (16*sqrt2/2 ~ 11.3)
        var dy: i32 = -R;
        while (dy <= R) : (dy += 1) {
            var dx: i32 = -R;
            while (dx <= R) : (dx += 1) {
                const fdx: f32 = @floatFromInt(dx);
                const fdy: f32 = @floatFromInt(dy);
                const srx = cs * fdx + sn * fdy + half; // inverse rotation -> source
                const sry = -sn * fdx + cs * fdy + half;
                if (srx < 0 or srx >= @as(f32, @floatFromInt(TS)) or sry < 0 or sry >= @as(f32, @floatFromInt(TS))) continue;
                const sx: usize = @intFromFloat(srx);
                const sy: usize = @intFromFloat(sry);
                const idx = wab_raw[(ty * TS + sy) * LOGO + tx * TS + sx];
                if (idx == 0) continue;
                const px = @as(i32, @intFromFloat(ccx)) + dx;
                const py = @as(i32, @intFromFloat(ccy)) + dy;
                if (px < 0 or px >= WIDTH or py < 0 or py >= HEIGHT) continue;
                fb.setPixelValue(@intCast(px), @intCast(py), idx);
            }
        }
    }

    fn drawWhole(fb: *LogicalFB) void {
        var y: usize = 0;
        while (y < LOGO) : (y += 1) {
            const row = y * LOGO;
            var x: usize = 0;
            while (x < LOGO) : (x += 1) {
                const idx = wab_raw[row + x];
                if (idx == 0) continue;
                fb.setPixelValue(@intCast(OX + @as(i32, @intCast(x))), @intCast(OY + @as(i32, @intCast(y))), idx);
            }
        }
    }

    fn applyFade(self: *Part, zigos: *ZigOS) void {
        const p0: *LogicalFB = &zigos.lfbs[0];
        var i: usize = 1;
        while (i < 256) : (i += 1) {
            const c = wab_pal[i];
            p0.setPaletteEntry(@intCast(i), Color{
                .r = @intFromFloat(@as(f32, @floatFromInt(c.r)) * self.fade),
                .g = @intFromFloat(@as(f32, @floatFromInt(c.g)) * self.fade),
                .b = @intFromFloat(@as(f32, @floatFromInt(c.b)) * self.fade),
                .a = 255,
            });
        }
    }
};
