// --------------------------------------------------------------------------
// Union intro — TRSI logo part. Fly-in tiles assemble the logo (they tile the
// TURN animation's frame 0, so the assembled logo IS frame 0 — no jump), then a
// pre-rendered turning animation plays, then it fades out.
// Faithful to eflogoentry.js + eflogo.js + lib/codef_animatedtiles.js.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const WIDTH: i32 = @intCast(zg.WIDTH);
const HEIGHT: i32 = @intCast(zg.HEIGHT);

const FW: usize = 180;
const FH: usize = 42;
const FRAMES: usize = 26;
const FRAME_HOLD: u32 = 8;
const ALPHA_INCR: f32 = 0.02; // faster logo fade-out (author's call; JS base is 0.005)
// The turn animation ships ZX0-packed (build.zig packs it, with the RASTERS depack
// effect). union_intro.zig depacks it into free cart RAM before the part starts
// and points `turn_raw` at the result. A static buffer would not save anything:
// with imported memory the linker writes .bss out as a zero segment.
pub const turn_packed = @import("packed_assets").trsi_turn;
pub const TURN_LEN = FW * FH * FRAMES;
pub var turn_raw: []const u8 = &.{};
const turn_pal = convertU8ArraytoColors(@embedFile("../../assets/screens/union_intro/trsi_turn_pal.dat"));

const OX: i32 = (WIDTH - @as(i32, @intCast(FW))) >> 1;
const OY: i32 = (HEIGHT - @as(i32, @intCast(FH))) >> 1;

const TW: usize = 6;
const TH: usize = 6;
const NX: usize = FW / TW;
const NY: usize = FH / TH;
const NT: usize = NX * NY; // 210
// Faithful to codef_animatedtiles.js: every tile arrives at endvbl (= aSpeed),
// so a tile that starts late (bigger svbl) has a shorter travel window and a
// bigger per-frame step — the blocks visibly accelerate and snap into place
// together at ENDVBL, instead of each drifting a fixed MOVE frames.
const ENDVBL: f32 = 60.0;
const STAGGER: u16 = 40; // ~ Math.ceil(40*Math.random())
const ENTRY_END: u32 = 60; // all tiles home by ENDVBL -> straight into the turn

const BG = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

const Phase = enum { entry, turn };

pub const Part = struct {
    phase: Phase = .entry,
    t: u32 = 0,
    turn_tick: u32 = 0,
    turn_idx: usize = 0,
    fade: f32 = 1.0,
    sx: [NT]f32 = undefined,
    sy: [NT]f32 = undefined,
    svbl: [NT]u16 = undefined,

    pub fn init(self: *Part, zigos: *ZigOS) void {
        self.* = .{};
        var prng = std.Random.DefaultPrng.init(0x2b1c9f);
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
        p0.setPalette(turn_pal);
        p0.setPaletteEntry(0, BG);
    }

    // Returns true when the part is finished (faded out).
    pub fn update(self: *Part, zigos: *ZigOS, dt: f32) bool {
        _ = dt;
        switch (self.phase) {
            .entry => {
                self.t += 1;
                if (self.t >= ENTRY_END) self.phase = .turn;
            },
            .turn => {
                self.turn_tick += 1;
                if (self.turn_idx + 1 < FRAMES) {
                    if (self.turn_tick % FRAME_HOLD == 0) self.turn_idx += 1;
                } else if (self.fade > 0.0) {
                    self.fade = @max(0.0, self.fade - ALPHA_INCR);
                    self.applyFade(zigos);
                    if (self.fade <= 0.0) return true;
                }
            },
        }
        return false;
    }

    pub fn render(self: *Part, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const p0: *LogicalFB = &zigos.lfbs[0];
        p0.clearFrameBuffer(0);
        switch (self.phase) {
            .entry => self.drawEntry(p0),
            .turn => drawFrame(p0, self.turn_idx),
        }
    }

    fn drawEntry(self: *Part, fb: *LogicalFB) void {
        var i: usize = 0;
        while (i < NT) : (i += 1) {
            if (self.t <= self.svbl[i]) continue;
            const tx = i % NX;
            const ty = i / NX;
            const home_x: f32 = @floatFromInt(OX + @as(i32, @intCast(tx * TW)));
            const home_y: f32 = @floatFromInt(OY + @as(i32, @intCast(ty * TH)));
            var p: f32 = @as(f32, @floatFromInt(self.t - self.svbl[i])) / (ENDVBL - @as(f32, @floatFromInt(self.svbl[i])));
            if (p > 1.0) p = 1.0;
            const cx: i32 = @intFromFloat(self.sx[i] + (home_x - self.sx[i]) * p);
            const cy: i32 = @intFromFloat(self.sy[i] + (home_y - self.sy[i]) * p);
            var yy: usize = 0;
            while (yy < TH) : (yy += 1) {
                const dy = cy + @as(i32, @intCast(yy));
                if (dy < 0 or dy >= HEIGHT) continue;
                const src = (ty * TH + yy) * FW + tx * TW;
                var xx: usize = 0;
                while (xx < TW) : (xx += 1) {
                    const idx = turn_raw[src + xx];
                    if (idx == 0) continue;
                    const dx = cx + @as(i32, @intCast(xx));
                    if (dx < 0 or dx >= WIDTH) continue;
                    fb.setPixelValue(@intCast(dx), @intCast(dy), idx);
                }
            }
        }
    }

    fn drawFrame(fb: *LogicalFB, n: usize) void {
        const base: usize = n * FH * FW;
        var py: usize = 0;
        while (py < FH) : (py += 1) {
            const row = base + py * FW;
            var px: usize = 0;
            while (px < FW) : (px += 1) {
                const idx = turn_raw[row + px];
                if (idx == 0) continue;
                fb.setPixelValue(@intCast(OX + @as(i32, @intCast(px))), @intCast(OY + @as(i32, @intCast(py))), idx);
            }
        }
    }

    fn applyFade(self: *Part, zigos: *ZigOS) void {
        const p0: *LogicalFB = &zigos.lfbs[0];
        var i: usize = 1;
        while (i < 256) : (i += 1) {
            const c = turn_pal[i];
            p0.setPaletteEntry(@intCast(i), Color{
                .r = @intFromFloat(@as(f32, @floatFromInt(c.r)) * self.fade),
                .g = @intFromFloat(@as(f32, @floatFromInt(c.g)) * self.fade),
                .b = @intFromFloat(@as(f32, @floatFromInt(c.b)) * self.fade),
                .a = 255,
            });
        }
    }
};
