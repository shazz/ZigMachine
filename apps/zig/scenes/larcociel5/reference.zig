// --------------------------------------------------------------------------
// The REFERENCE picture and colour bank, as the cart built them before the
// CHISEL compositor, verbatim: the Go's GlyphWindow in two passes (a 272-row
// stencil, then the perspective sampling), the 64 KB ribbon "body" redrawn
// from scratch every tick, and the shader's per-pixel index math over the
// whole plane. Only chunky_test.zig uses it.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");
const colorbank = @import("colorbank.zig");
const Clock = @import("clock.zig").Clock;

const W: usize = 320;
const H: usize = 200;

pub const RefBank = struct {
    colors: [100 * 16]u32 = [_]u32{0} ** (100 * 16),
    stencil: [272 * 15]u32 = undefined,

    pub fn build(self: *RefBank, tick: u32) void {
        const msg = assets.message;
        const position: usize = @intCast(if (tick > 0) tick - 1 else 0);
        const current = (position / 17) % msg.len;
        const off = position % 17;

        @memset(&self.stencil, 0);
        var slot: usize = 0;
        while (slot < 16) : (slot += 1) {
            const ch: u8 = if (current + slot < msg.len) msg[current + slot] else ' ';
            const glyph = colorbank.glyphIndex(ch);
            const top: i32 = @as(i32, @intCast(slot * 17)) - @as(i32, @intCast(off));
            var row: usize = 0;
            while (row < 17) : (row += 1) {
                const y = top + @as(i32, @intCast(row));
                if (y < 0 or y >= 272) continue;
                const base = @as(usize, @intCast(y)) * 15;
                var col: usize = 0;
                while (col < 15) : (col += 1)
                    self.stencil[base + col] = assets.rgbw(colorbank.fontWord(glyph, row, col));
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

pub fn buildBody(clock: *const Clock, body: *[W * H]u8) void {
    @memset(body, 0);
    const hist = clock.history;
    const y0: i32 = clock.y;
    var r: usize = 0;
    while (r < 50) : (r += 1) {
        const yy = y0 + @as(i32, @intCast(r));
        if (yy < 0 or yy >= H) continue;
        const row = r * 112;
        var x: usize = 0;
        while (x < 112) : (x += 1) {
            const v = assets.ribbon[row + x];
            if (v == 0) continue;
            const dx: i32 = @as(i32, @intCast(x)) + @as(i32, hist[r]);
            if (dx < 0 or dx >= W) continue;
            body[@as(usize, @intCast(yy)) * W + @as(usize, @intCast(dx))] = v & 3;
        }
    }
}

pub fn present(px: *[W * H]u8, body: *const [W * H]u8, meters: [3]u8, with_bats: bool) void {
    const bg = assets.bg;
    var y: usize = 0;
    while (y < H) : (y += 1) {
        const base = y * W;
        const bat_row = y < 32;
        var x: usize = 0;
        while (x < W) : (x += 1) {
            var i: u8 = bg[base + x];
            const b = body[base + x];
            if (b != 0) i = (i & ~@as(u8, 3)) | b;
            if (bat_row) {
                var hit = false;
                if (with_bats) {
                    const rx = x & 127;
                    if (rx < 64) hit = assets.batBit(15 - meters[x >> 7], rx, y) != 0;
                }
                i = (i & 3) | (if (hit) @as(u8, 4) else 0);
            }
            px[base + x] = i;
        }
    }
}
