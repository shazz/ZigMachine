// --------------------------------------------------------------------------
// The colour bank -- the Go's scrolling.GlyphWindow, transcribed.
//
// DCK paints 16 glyph slots down a 272-row stencil (17-row cells, advanced by
// 17, scrolled by the clock's Tick-1), then samples that stencil into a 100-row
// window with the perspective recurrence the Go hard-codes (phase += step from
// 20, emit whenever phase reaches 80, step++ each emit). Row 0 of each output
// row is left black -- the shader never samples index 0 of the bank.
//
// `colors` is what the plane HBL hands palette entries 1..15 on visible lines
// 100..199. Integer only: no float on the per-frame path.
// --------------------------------------------------------------------------
const std = @import("std");
const assets = @import("assets.zig");

fn glyphIndex(ch: u8) usize {
    if (ch == ' ') return 0;
    if (ch == '.') return 27;
    if (ch == ',') return 28;
    if (ch == '\'') return 29;
    const v: i32 = @as(i32, ch) - 64;
    return @intCast(std.math.clamp(v, 0, 26));
}

fn fontWord(glyph: usize, row: usize, col: usize) u16 {
    return assets.beWord(assets.font_colors, (glyph * 255 + row * 15 + col) * 2);
}

pub const Bank = struct {
    /// 100 rows x 16 entries (entry 0 always black), in Color.toRGBA order.
    colors: [100 * 16]u32 = [_]u32{0} ** (100 * 16),
    /// Module-scope scratch, fully rewritten every build (still cleared, because
    /// the 17-row cells do not cover the last rows when the sub-row offset is high).
    stencil: [272 * 15]u32 = undefined,

    pub fn clear(self: *Bank) void {
        @memset(&self.colors, 0);
    }

    pub fn build(self: *Bank, tick: u32) void {
        const msg = assets.message;
        const position: usize = @intCast(if (tick > 0) tick - 1 else 0);
        const current = (position / 17) % msg.len;
        const off = position % 17;

        @memset(&self.stencil, 0);
        var slot: usize = 0;
        while (slot < 16) : (slot += 1) {
            const ch: u8 = if (current + slot < msg.len) msg[current + slot] else ' ';
            const glyph = glyphIndex(ch);
            const top: i32 = @as(i32, @intCast(slot * 17)) - @as(i32, @intCast(off));
            var row: usize = 0;
            while (row < 17) : (row += 1) {
                const y = top + @as(i32, @intCast(row));
                if (y < 0 or y >= 272) continue;
                const base = @as(usize, @intCast(y)) * 15;
                var col: usize = 0;
                while (col < 15) : (col += 1)
                    self.stencil[base + col] = assets.rgbw(fontWord(glyph, row, col));
            }
        }

        @memset(&self.colors, 0);
        var out: usize = 0;
        var phase: i32 = 0;
        var stepv: i32 = 20;
        var row: usize = 0;
        while (out < 100 and row < 272) {
            phase += stepv;
            if (phase < 80) {
                row += 1;
                continue;
            }
            phase -= 80;
            stepv += 1;
            var col: usize = 0;
            while (col < 15) : (col += 1)
                self.colors[out * 16 + col + 1] = self.stencil[row * 15 + col];
            out += 1;
            row += 1;
        }
    }
};
