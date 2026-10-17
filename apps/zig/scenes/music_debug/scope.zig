// --------------------------------------------------------------------------
// The player-adaptive oscilloscope: three YM voices drawn from the PSG
// registers (YM dump, SNDH), or the MOD/sample channels' captured samples,
// with an "electron flow" gradient band sweeping right->left every
// FLOW_PERIOD frames. The host mirrors the audio state into zigos (the
// browser does; the board's firmware leaves audio_mode at 0, no scope).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const fsin = @import("fsin.zig");
const palette = @import("palette.zig");
const FLOW_N = palette.FLOW_N;

const WIDTH: u16 = zg.WIDTH;
const HEIGHT: u16 = zg.HEIGHT;
const SCOPE_LEN: usize = zg.SCOPE_LEN;

pub const SCOPE = [4]u8{ 6, 7, 8, 9 }; // palette entries of the curves
pub const FLOW_BASE: u8 = 16; // first of FLOW_N gradient palette entries
const FLOW_BAND: f32 = 24.0; // half-width of the moving band (~48px pulse)
const FLOW_PERIOD: u32 = 300; // ~5s at 60fps
const FLOW_PULSE: u32 = 45; // frames the band takes to cross (fast)

// The scope plane: transparent background (the starfield shows through),
// medium-dark grey curves, and the flow gradient for the sweeping pulse.
pub fn setPalette(p1: *LogicalFB) void {
    p1.setPaletteEntry(0, zg.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
    for (SCOPE) |e| p1.setPaletteEntry(e, zg.Color{ .r = 90, .g = 90, .b = 96, .a = 255 });
    for (palette.FLOWGRAD, 0..) |c, k| p1.setPaletteEntry(FLOW_BASE + @as(u8, @intCast(k)), c);
}

fn hashRand(x: usize, seed: u32) f32 {
    var h: u32 = @as(u32, @truncate(x)) *% 2654435761 +% seed *% 40503;
    h ^= h >> 13;
    return @as(f32, @floatFromInt((h >> 8) & 0xFF)) / 255.0;
}

// One column's vertical stroke from the previous sample to this one.
fn stroke(fb: *LogicalFB, x: usize, prev: i32, yy: i32, col: u8) void {
    var yl = @min(prev, yy);
    const yh = @max(prev, yy);
    while (yl <= yh) : (yl += 1) {
        if (yl >= 0 and yl < HEIGHT) fb.setPixelValue(@intCast(x), @intCast(yl), col);
    }
}

pub const Scope = struct {
    flow_pos: f32 = 0.0,
    flow_active: bool = false,

    pub fn draw(self: *Scope, zigos: *ZigOS, fb: *LogicalFB, flow_frame: u32, phase: f32) void {
        // update the sweeping "electron flow" band
        const inp = flow_frame % FLOW_PERIOD;
        self.flow_active = inp < FLOW_PULSE;
        if (self.flow_active) {
            const p = @as(f32, @floatFromInt(inp)) / @as(f32, FLOW_PULSE);
            // right -> left across the full width plus a band margin on each side
            self.flow_pos = (@as(f32, WIDTH) + FLOW_BAND) - p * (@as(f32, WIDTH) + 2 * FLOW_BAND);
        }
        switch (zigos.audio_mode) {
            2, 4 => self.drawYm(zigos, fb, phase), // YM dump and SNDH both drive the PSG
            1 => self.drawWaves(zigos, fb, 4),
            3 => self.drawWaves(zigos, fb, 1),
            else => {},
        }
    }

    // Palette entry for a scope column: grey normally, or the flowing gradient
    // where the sweeping band currently is.
    fn color(self: *const Scope, ch: usize, x: usize) u8 {
        if (!self.flow_active) return SCOPE[ch];
        const d = @as(f32, @floatFromInt(x)) - self.flow_pos;
        if (@abs(d) > FLOW_BAND) return SCOPE[ch];
        const gi: usize = @intFromFloat((d + FLOW_BAND) / (2 * FLOW_BAND) * @as(f32, FLOW_N - 1));
        return FLOW_BASE + @as(u8, @intCast(gi));
    }

    fn drawWaves(self: *const Scope, zigos: *ZigOS, fb: *LogicalFB, n: usize) void {
        const top: i32 = 42;
        const band: i32 = @divTrunc(@as(i32, HEIGHT - 60), @as(i32, @intCast(n)));
        const amp: f32 = if (n == 1) 46.0 else @as(f32, @floatFromInt(band)) * 0.42;
        for (0..n) |ch| {
            const cy: i32 = top + band * @as(i32, @intCast(ch)) + @divTrunc(band, 2);
            const samples = &zigos.scopes[ch];
            var prev: i32 = cy;
            for (0..WIDTH) |x| {
                const yy: i32 = cy + @as(i32, @intFromFloat(samples[x * SCOPE_LEN / WIDTH] * amp));
                stroke(fb, x, prev, yy, self.color(ch, x));
                prev = yy;
            }
        }
    }

    fn drawYm(self: *const Scope, zigos: *ZigOS, fb: *LogicalFB, phase: f32) void {
        const cy = [3]i32{ 66, 108, 150 };
        const regs = &zigos.ym_regs;
        const seed: u32 = @intFromFloat(phase * 7.0);
        for (0..3) |ch| {
            const period: u16 = (@as(u16, regs[ch * 2 + 1] & 0x0F) << 8) | regs[ch * 2];
            const vreg = regs[8 + ch];
            const vol: f32 = if (vreg & 0x10 != 0) 13.0 else @floatFromInt(vreg & 0x0F);
            const amp = vol / 15.0 * 20.0;
            const tone_on = (regs[7] >> @intCast(ch)) & 1 == 0;
            const noise_on = (regs[7] >> @intCast(ch + 3)) & 1 == 0;
            const wl = std.math.clamp(@as(f32, @floatFromInt(if (period == 0) 1 else period)) / 14.0, 3.0, 130.0);
            var prev: i32 = cy[ch];
            for (0..WIDTH) |x| {
                var v: f32 = 0;
                if (tone_on) {
                    const s = fsin.sin(@as(f32, @floatFromInt(x)) / wl * 6.2831853 + phase * 3.0);
                    v = if (s >= 0) amp else -amp;
                }
                if (noise_on) {
                    const nz = (hashRand(x, seed) * 2.0 - 1.0) * amp;
                    v = if (tone_on) v + nz * 0.4 else nz;
                }
                const yy: i32 = cy[ch] + @as(i32, @intFromFloat(v));
                stroke(fb, x, prev, yy, self.color(ch, x));
                prev = yy;
            }
        }
    }
};
