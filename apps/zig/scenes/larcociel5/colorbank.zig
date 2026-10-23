// --------------------------------------------------------------------------
// The colour bank -- the Go's scrolling.GlyphWindow.
//
// DCK paints 16 glyph slots down a 272-row stencil (17-row cells, advanced by
// 17, scrolled by the clock's Tick-1), then samples that stencil into a 100-row
// window with the perspective recurrence the Go hard-codes (phase += step from
// 20, emit whenever phase reaches 80, step++ each emit). Row 0 of each output
// row is left black -- the shader never samples index 0 of the bank.
//
// The recurrence never reads the tick, so which stencil row each output row
// samples is a comptime table (ROWS), and a stencil row is a pure function of
// the tick: slot (row + off) / 17, glyph row (row + off) % 17, or black past
// the 16th slot. `build` therefore computes each of the 1500 words straight
// from the font and stores only the ones that changed -- no 272-row stencil
// rebuilt (and cleared) every tick. reference.zig keeps the Go's two-pass
// transcription; larcociel5/chunky_test.zig requires the same words every tick.
//
// `colors` is what the plane HBL hands palette entries 1..15 on visible lines
// 100..199. Integer only: no float on the per-frame path.
// --------------------------------------------------------------------------
const std = @import("std");
const assets = @import("assets.zig");

pub fn glyphIndex(ch: u8) usize {
    if (ch == ' ') return 0;
    if (ch == '.') return 27;
    if (ch == ',') return 28;
    if (ch == '\'') return 29;
    const v: i32 = @as(i32, ch) - 64;
    return @intCast(std.math.clamp(v, 0, 26));
}

pub fn fontWord(glyph: usize, row: usize, col: usize) u16 {
    return assets.beWord(assets.font_colors, (glyph * 255 + row * 15 + col) * 2);
}

/// The stencil row each output row samples (the Go's perspective recurrence).
pub const ROWS: []const u16 = blk: {
    var rows: [100]u16 = undefined;
    var out: usize = 0;
    var phase: i32 = 0;
    var stepv: i32 = 20;
    var row: usize = 0;
    while (out < 100 and row < 272) {
        phase += stepv;
        if (phase >= 80) {
            phase -= 80;
            stepv += 1;
            rows[out] = row;
            out += 1;
        }
        row += 1;
    }
    const final = rows[0..out].*;
    break :blk &final;
};

pub const Bank = struct {
    /// 100 rows x 16 entries (entry 0 always black), in Color.toRGBA order.
    colors: [100 * 16]u32 = [_]u32{0} ** (100 * 16),

    pub fn clear(self: *Bank) void {
        @memset(&self.colors, 0);
    }

    pub fn build(self: *Bank, tick: u32) void {
        const msg = assets.message;
        const position: usize = @intCast(if (tick > 0) tick - 1 else 0);
        const current = (position / 17) % msg.len;
        const off = position % 17;
        for (ROWS, 0..) |row, out| {
            const y = row + off;
            const slot = y / 17;
            const ch: u8 = if (current + slot < msg.len) msg[current + slot] else ' ';
            const glyph = glyphIndex(ch);
            const dst = self.colors[out * 16 + 1 ..][0..15];
            for (dst, 0..) |*c, col| {
                const v: u32 = if (slot < 16) assets.rgbw(fontWord(glyph, y % 17, col)) else 0;
                if (c.* != v) c.* = v;
            }
        }
    }
};
