// --------------------------------------------------------------------------
// The three music meters -- internal/demo/game.go's Update, transcribed: the
// YM2149 volume registers 8/9/10 select a height from volume-curve.bin, and the
// meter-raw.bin mask ORs PLANE-3 bits into the screen at row 147 downward, so
// the three bars show up in the shader's index>=8 colour zone (a REAL raster
// colour on rows 144..199, not a fixed palette word).
//
// x/channel: ch0 x=96 width 48, ch1 x=144 width 32, ch2 x=176 width 48.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");

pub fn apply(screen: []u8, regs: [14]u8) void {
    var ch: usize = 0;
    while (ch < 3) : (ch += 1) {
        const height: usize = assets.volume_curve[regs[8 + ch] & 15];
        if (height == 0) continue;
        const x: usize = if (ch == 0) 96 else if (ch == 1) 144 else 176;
        const width: usize = if (ch == 1) 32 else 48;
        const source_x = x - 96;
        var row: usize = 0;
        while (row <= height and row < 52) : (row += 1) {
            var dx: usize = 0;
            while (dx < width) : (dx += 1) {
                const p = (147 + row) * 160 + (x + dx) / 16 * 8 + 6;
                const mask: u16 = @as(u16, 1) << @intCast(15 - (x + dx) % 16);
                var w = assets.beWord(screen, p);
                const q = source_x + dx;
                const v = assets.beWord(assets.meter_raw, row * 160 + q / 16 * 8);
                if ((v >> @intCast(15 - q % 16)) & 1 != 0) w |= mask;
                screen[p] = @truncate(w >> 8);
                screen[p + 1] = @truncate(w);
            }
        }
    }
}
