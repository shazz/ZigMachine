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
const ALPHA_INCR = emu.of(0.02); // faster logo fade-out (author's call; JS base is 0.005)
// The turn animation ships ZX0-packed (build.zig packs it, with the RASTERS depack
// effect). union_intro.zig depacks it into a zg.mem block before the part starts
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
const ENDVBL: i32 = 60;
const STAGGER: u16 = 40; // ~ Math.ceil(40*Math.random())
const ENTRY_END: u32 = 60; // all tiles home by ENDVBL -> straight into the turn

const BG = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

const pal_fade = @import("pal_fade.zig");
const emu = @import("f32emu.zig");

const Phase = enum { entry, turn };

pub const Part = struct {
    blitter: zg.Blitter = .{},
    phase: Phase = .entry,
    t: u32 = 0,
    turn_tick: u32 = 0,
    turn_idx: usize = 0,
    // Integers since 2026-10-25 (no float a frame on ZIGGY): the fade an f32 kept by
    // f32emu.zig, the tiles' random start points in Q16 (drawn as floats once, at init).
    fade: emu.Value = emu.ONE,
    sx: [NT]i32 = undefined,
    sy: [NT]i32 = undefined,
    svbl: [NT]u16 = undefined,

    pub fn init(self: *Part, zigos: *ZigOS) void {
        self.* = .{};
        self.blitter.init();
        var prng = std.Random.DefaultPrng.init(0x2b1c9f);
        const rnd = prng.random();
        var i: usize = 0;
        while (i < NT) : (i += 1) {
            self.sx[i] = @intFromFloat(rnd.float(f32) * @as(f32, @floatFromInt(WIDTH)) * 65536.0);
            self.sy[i] = @intFromFloat(rnd.float(f32) * @as(f32, @floatFromInt(HEIGHT)) * 65536.0);
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
                } else if (self.fade > 0) {
                    self.fade = emu.add(self.fade, -@as(i64, @intCast(ALPHA_INCR)));
                    self.applyFade(zigos);
                    if (self.fade == 0) return true;
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
            .turn => self.drawFrame(p0, self.turn_idx),
        }
    }

    fn drawEntry(self: *Part, fb: *LogicalFB) void {
        var i: usize = 0;
        while (i < NT) : (i += 1) {
            if (self.t <= self.svbl[i]) continue;
            const tx = i % NX;
            const ty = i / NX;
            const home_x: i32 = (OX + @as(i32, @intCast(tx * TW))) << 16;
            const home_y: i32 = (OY + @as(i32, @intCast(ty * TH))) << 16;
            // s + (home - s) * p, p = (t - svbl) / (ENDVBL - svbl) at most 1, in Q16
            const num: i32 = @min(@as(i32, @intCast(self.t - self.svbl[i])), ENDVBL - self.svbl[i]);
            const den: i32 = ENDVBL - self.svbl[i];
            const cx: i32 = (self.sx[i] + @divTrunc((home_x - self.sx[i]) * num, den)) >> 16;
            const cy: i32 = (self.sy[i] + @divTrunc((home_y - self.sy[i]) * num, den)) >> 16;
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

    fn drawFrame(self: *Part, fb: *LogicalFB, n: usize) void {
        self.blitter.blitImage(fb, @intCast(OX), @intCast(OY), turn_raw, @intCast(FW), 0, @intCast(n * FH), @intCast(FW), @intCast(FH), 0);
    }

    // CODEF fades by canvas alpha; over black that is the palette's RGB scaled
    // from the base turn_pal every frame (never a compounding re-scale).
    fn applyFade(self: *Part, zigos: *ZigOS) void {
        const p0: *LogicalFB = &zigos.lfbs[0];
        pal_fade.scaleRange(p0, &turn_pal, 1, 255, self.fade);
    }
};
