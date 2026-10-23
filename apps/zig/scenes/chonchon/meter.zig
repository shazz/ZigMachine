// --------------------------------------------------------------------------
// The three music meters -- internal/demo/game.go's Update: the YM2149 volume
// registers 8/9/10 select a height from volume-curve.bin, and the meter-raw.bin
// mask ORs PLANE-3 bits into the screen at row 147 downward, so the three bars
// show up in the shader's index>=8 colour zone (a REAL raster colour on rows
// 144..199, not a fixed palette word).
//
// x/channel: ch0 x=96 width 48, ch1 x=144 width 32, ch2 x=176 width 48, mask
// columns 0, 48, 80. Every x and mask column is a multiple of 16 and screen x
// = mask x + 96, so the Go's per-pixel loop is exactly a plane-3 WORD OR of
// mask words 0..2 / 3..4 / 5..7 into groups 6..8 / 9..10 / 11..13 (the
// per-pixel transcription is reference.zig's meterApply; the native test runs
// both).
// --------------------------------------------------------------------------
const assets = @import("assets.zig");
const dirty = @import("dirty.zig");

const MASK_WORD = [3]usize{ 0, 3, 5 };

pub fn apply(screen: []u8, regs: [14]u8) void {
    const heights = dirty.meterHeights(regs);
    for (0..3) |ch| {
        const height: usize = heights[ch];
        if (height == 0) continue;
        for (0..@min(height, 51) + 1) |row| {
            for (0..dirty.METER_GROUPS[ch]) |j| {
                const m = row * 160 + (MASK_WORD[ch] + j) * 8;
                const p = (dirty.METER_ROW + row) * 160 + (dirty.METER_GROUP[ch] + j) * 8 + 6;
                const hi = assets.meter_raw[m];
                const lo = assets.meter_raw[m + 1];
                if (hi != 0) screen[p] |= hi;
                if (lo != 0) screen[p + 1] |= lo;
            }
        }
    }
}
