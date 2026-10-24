// --------------------------------------------------------------------------
// The rotozoom's tile, built by gen_anima.zig on the HOST: 64x64 texels of 16
// light levels (roto.zig gives every LINE its own 16 colours for them).
// An "A" from the 16x16 font, EPX-doubled to 32x32, lit as embossed metal
// (bevel light top-left, dark bottom-right) on a field of diagonal grooves,
// with a dark outline so the letter reads at any zoom.
// --------------------------------------------------------------------------
const gen = @import("gen.zig");

pub const N = 64;

fn at(m: *const [32][32]u1, y: i32, x: i32) bool {
    if (y < 0 or x < 0 or y >= 32 or x >= 32) return false;
    return m[@intCast(y)][@intCast(x)] != 0;
}

pub fn build(font: *const [gen.SHEET_BYTES]u8, out: *[N * N]u8) void {
    const g = gen.epx(16, 16, gen.glyph16(font, 'A'));
    for (0..N) |yy| for (0..N) |xx| {
        const y: i32 = @as(i32, @intCast(yy)) - 16;
        const x: i32 = @as(i32, @intCast(xx)) - 17;
        // the field: diagonal grooves, 8 texels a period
        const d: u32 = @intCast((xx + yy) % 8);
        var c: u8 = if (d < 2) 1 else @intCast(3 + d / 2);
        if (at(&g, y, x)) {
            const lit = !at(&g, y - 1, x) or !at(&g, y, x - 1) or !at(&g, y - 2, x);
            const dark = !at(&g, y + 1, x) or !at(&g, y, x + 1) or !at(&g, y + 2, x);
            c = if (lit and !dark) 15 else if (dark and !lit) 9 else 12 + @as(u8, @intCast(@mod(y, 3)));
        } else {
            var near = false;
            var dy: i32 = -1;
            while (dy <= 1) : (dy += 1) {
                var dx: i32 = -1;
                while (dx <= 1) : (dx += 1) near = near or at(&g, y + dy, x + dx);
            }
            if (near) c = 0;
        }
        out[yy * N + xx] = c;
    };
}
