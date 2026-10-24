// --------------------------------------------------------------------------
// The player-adaptive oscilloscope: three YM voices drawn from the PSG
// registers (YM dump, SNDH), or the MOD/sample channels' captured samples,
// with an "electron flow" gradient band sweeping right->left every
// FLOW_PERIOD frames. The host mirrors the audio state into zigos: the
// browser's loader, and on the board the firmware from BARD's state
// (fpga/cycles/aud_state.h, mode + YM registers; the board has no per-channel
// captures, Paula is RTL, so MOD/sample curves stay flat there).
//
// Integer only (Matt, 2026-10-24): the square waves step a fixtrig Angle a
// column, amplitudes are Q8, the flow band is in 1/FLOW_PULSE pixels, and the
// host's f32 samples are read as Q8 straight from their bits.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const wave = @import("wave.zig");
const View = @import("view.zig").View;
const palette = @import("palette.zig");
const FLOW_N: i32 = palette.FLOW_N;

const WIDTH: u16 = zg.WIDTH;
const HEIGHT: u16 = zg.HEIGHT;
const SCOPE_LEN: usize = zg.SCOPE_LEN;

pub const SCOPE = [4]u8{ 42, 43, 44, 45 }; // palette entries of the curves
pub const FLOW_BASE: u8 = 48; // first of FLOW_N gradient palette entries
const FLOW_BAND: i32 = 24; // half-width of the moving band (~48px pulse)
const FLOW_PERIOD: u32 = 300; // ~5s at 60fps
const FLOW_PULSE: i32 = 45; // frames the band takes to cross (fast)

// The scope's entries: medium-dark grey curves, and the flow gradient for the sweeping pulse.
pub fn setPalette(fb: *LogicalFB) void {
    for (SCOPE) |e| fb.setPaletteEntry(e, zg.Color{ .r = 90, .g = 90, .b = 96, .a = 255 });
    for (palette.FLOWGRAD, 0..) |c, k| fb.setPaletteEntry(FLOW_BASE + @as(u8, @intCast(k)), c);
}

/// A noise byte 0..255 for column x.
fn hashByte(x: usize, seed: u32) i32 {
    var h: u32 = @as(u32, @truncate(x)) *% 2654435761 +% seed *% 40503;
    h ^= h >> 13;
    return @intCast((h >> 8) & 0xFF);
}

/// trunc(f * 256) for |f| < 2^23, from the f32's bits (no float op).
fn q8(f: f32) i32 {
    const b: u32 = @bitCast(f);
    const e: i32 = @intCast((b >> 23) & 0xFF);
    const m: i32 = @intCast((b & 0x7FFFFF) | 0x800000);
    const sh = 142 - e; // value * 256 = m * 2^(e - 142)
    const mag: i32 = if (e == 0 or sh >= 24) 0 else if (sh >= 0) m >> @intCast(sh) else m << @intCast(-sh);
    return if (b >> 31 != 0) -mag else mag;
}

// One column's vertical stroke from the previous sample to this one.
// Clipped once, then a pointer walk down the column (x is always on the window).
fn stroke(v: View, x: usize, prev: i32, yy: i32, col: u8) void {
    const yl = @max(@min(prev, yy), 0);
    const yh = @min(@max(prev, yy), HEIGHT - 1);
    if (yl > yh) return;
    var p: [*]u8 = v.px + @as(usize, @intCast(yl * v.stride)) + x;
    var n = yh - yl;
    while (true) : (n -= 1) {
        p[0] = col;
        if (n == 0) break;
        p += @as(usize, @intCast(v.stride));
    }
}

pub const Scope = struct {
    flow_pos: i32 = 0, // band centre, in 1/FLOW_PULSE pixels
    flow_active: bool = false,

    pub fn draw(self: *Scope, zigos: *ZigOS, v: View, flow_frame: u32, phase: wave.Angle) void {
        // update the sweeping "electron flow" band, right -> left across the full
        // width plus a band margin on each side
        const inp = flow_frame % FLOW_PERIOD;
        self.flow_active = inp < FLOW_PULSE;
        if (self.flow_active) self.flow_pos = (WIDTH + FLOW_BAND) * FLOW_PULSE - @as(i32, @intCast(inp)) * (WIDTH + 2 * FLOW_BAND);
        switch (zigos.audio_mode) {
            2, 4 => self.drawYm(zigos, v, phase, flow_frame), // YM dump and SNDH both drive the PSG
            1 => self.drawWaves(zigos, v, 4),
            3 => self.drawWaves(zigos, v, 1),
            else => {},
        }
    }

    // Palette entry for a scope column: grey normally, or the flowing gradient
    // where the sweeping band currently is.
    fn color(self: *const Scope, ch: usize, x: usize) u8 {
        if (!self.flow_active) return SCOPE[ch];
        const d = @as(i32, @intCast(x)) * FLOW_PULSE - self.flow_pos;
        if (@abs(d) > FLOW_BAND * FLOW_PULSE) return SCOPE[ch];
        const gi = @divTrunc((d + FLOW_BAND * FLOW_PULSE) * (FLOW_N - 1), 2 * FLOW_BAND * FLOW_PULSE);
        return FLOW_BASE + @as(u8, @intCast(gi));
    }

    fn drawWaves(self: *const Scope, zigos: *ZigOS, v: View, n: usize) void {
        const top: i32 = 42;
        const band: i32 = @divTrunc(@as(i32, HEIGHT - 60), @as(i32, @intCast(n)));
        const amp8: i32 = if (n == 1) 46 * 256 else @divTrunc(band * 42 * 256, 100); // band * 0.42
        for (0..n) |ch| {
            const cy: i32 = top + band * @as(i32, @intCast(ch)) + @divTrunc(band, 2);
            const samples = &zigos.scopes[ch];
            var prev: i32 = cy;
            for (0..WIDTH) |x| {
                // sample x * SCOPE_LEN / WIDTH = x * 2 / 5 (exact for x < 320), no divide
                comptime if (SCOPE_LEN * 5 != @as(usize, WIDTH) * 2) @compileError("scope sampling assumes 128 / 320");
                const yy: i32 = cy + wave.truncShift(q8(samples[(x * 26215) >> 16]) * amp8, 16);
                stroke(v, x, prev, yy, self.color(ch, x));
                prev = yy;
            }
        }
    }

    /// Angle step a column of a tone of `period`: one cycle every period / 14
    /// columns, clamped to 3..130 columns.
    fn toneStep(period: u16) wave.Angle {
        const p: u64 = if (period == 0) 1 else period;
        const step: u64 = (@as(u64, 14) << 32) / p;
        return @intCast(@min(@as(u64, 1 << 32) / 3, @max(@as(u64, 1 << 32) / 130, step)));
    }

    fn drawYm(self: *const Scope, zigos: *ZigOS, view: View, phase: wave.Angle, frame: u32) void {
        const cy = [3]i32{ 66, 108, 150 };
        const regs = &zigos.ym_regs;
        const seed: u32 = frame *% 21 / 20; // the noise moves ~1.05 a frame, as phase * 7 did
        for (0..3) |ch| {
            const vreg = regs[8 + ch];
            const vol: i32 = if (vreg & 0x10 != 0) 13 else vreg & 0x0F;
            const amp8 = @divTrunc(vol * 20 * 256, 15); // vol / 15 * 20 pixels
            const tone_on = (regs[7] >> @intCast(ch)) & 1 == 0;
            const noise_on = (regs[7] >> @intCast(ch + 3)) & 1 == 0;
            const step = toneStep((@as(u16, regs[ch * 2 + 1] & 0x0F) << 8) | regs[ch * 2]);
            var a = wave.scale(phase, 3);
            var prev: i32 = cy[ch];
            for (0..WIDTH) |x| {
                var v8: i32 = 0;
                if (tone_on) v8 = if (wave.positive(a)) amp8 else -amp8;
                if (noise_on) { // (h / 255 * 2 - 1) * amp, and 0.4 of it over a tone: shifts, no divide
                    const nz = ((hashByte(x, seed) * 2 - 255) * amp8 * 257) >> 16;
                    v8 = if (tone_on) v8 + ((nz * 26) >> 6) else nz;
                }
                const yy: i32 = cy[ch] + wave.truncShift(v8, 8);
                stroke(view, x, prev, yy, self.color(ch, x));
                prev = yy;
                a +%= step;
            }
        }
    }
};
