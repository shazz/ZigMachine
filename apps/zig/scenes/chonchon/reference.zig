// --------------------------------------------------------------------------
// The REFERENCE picture, as the cart drew it before the chunky compositor:
// the Go's per-pixel meter loop, the per-pixel 4-plane decode of the whole
// screen (the Go's Pixels) and the opaque logo rows over it (ImageSlots),
// verbatim. Only chunky_test.zig uses it: the live cart must produce exactly
// this picture from Clock.step + meterApply + present on every tick.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");
const Clock = @import("clock.zig").Clock;

const W: usize = 320;
const H: usize = 200;

pub fn meterApply(screen: []u8, regs: [14]u8) void {
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

pub fn present(clock: *const Clock, px: *[W * H]u8) void {
    const scr = clock.screen[0..];
    var y: usize = 0;
    while (y < H) : (y += 1) {
        const sbase = y * 160;
        const obase = y * W;
        var x: usize = 0;
        while (x < W) : (x += 1) {
            const sb = sbase + (x >> 4) * 8;
            const bit: u4 = @intCast(15 - (x & 15));
            const w0 = assets.beWord(scr, sb);
            const w1 = assets.beWord(scr, sb + 2);
            const w2 = assets.beWord(scr, sb + 4);
            const w3 = assets.beWord(scr, sb + 6);
            const i: u8 = @intCast(((w0 >> bit) & 1) | (((w1 >> bit) & 1) << 1) |
                (((w2 >> bit) & 1) << 2) | (((w3 >> bit) & 1) << 3));
            px[obase + x] = i;
        }
    }
    drawLogo(clock, px);
}

fn drawLogo(clock: *const Clock, px: []u8) void {
    var row: usize = 0;
    while (row < 63) : (row += 1) {
        const lr = clock.logoRow(row);
        if (lr.y < 0 or lr.y >= H) continue;
        const sr = (@as(usize, @intCast(row)) * 17 + lr.phase) * 96;
        var dx: usize = 0;
        while (dx < 96) : (dx += 1) {
            const idx = assets.logo[sr + dx];
            if (idx == 0) continue;
            const pxx = lr.x + @as(i32, @intCast(dx));
            if (pxx < 0 or pxx >= W) continue;
            px[@as(usize, @intCast(lr.y)) * W + @as(usize, @intCast(pxx))] = idx;
        }
    }
}
