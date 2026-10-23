// --------------------------------------------------------------------------
// The live picture. The shader's index math touches only two places of the
// static background: the 50 ribbon rows (low two bits replaced where the
// ribbon is opaque) and the bat band (rows 0..31: i % 4, + 4 where a bat is
// lit). The cart used to clear and redraw a 64 KB ribbon buffer every tick
// and recompute all 64,000 plane bytes every frame. Now, once a tick:
//
//   BG   (plane 1, disabled) = the background with rows 0..31 already i % 4:
//        the whole picture when no bat is lit and no ribbon crosses a row;
//   WORK (plane 2, disabled) <- BG, one CHISEL copy;
//   the lit 4-pixel words of the three 64x32 bat windows and the words a
//        ribbon row covers, computed on the CPU from the background (cart RAM,
//        never a plane read) and stored as u32;
//   SHOWN (plane 0) <- WORK, one copy: never a half-built frame.
//
// chunky_test.zig proves SHOWN == the reference's per-pixel picture on every
// tick. In-plane copies: 0.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");
const Clock = @import("clock.zig").Clock;
const gpu = @import("../chonchon/gpu.zig");

const W = gpu.W;
const H = gpu.H;
const BAT_ROWS: usize = 32;

pub fn initSurfaces(comptime G: type, g: *G) void {
    const out = g.words(gpu.BG);
    for (0..W * H / 4) |w| {
        const y = w / 80;
        var v: u32 = 0;
        for (0..4) |k| {
            var i = assets.bg[w * 4 + k];
            if (y < BAT_ROWS) i &= 3;
            v |= @as(u32, i) << @intCast(8 * k);
        }
        out[w] = v;
    }
}

inline fn batHit(meters: [3]u8, x: usize, y: usize) bool {
    const rx = x & 127;
    return rx < 64 and assets.batBit(15 - meters[x >> 7], rx, y) != 0;
}

/// The shader's index at (x, y) for ribbon index `rib` (0 = none there).
inline fn shade(meters: [3]u8, x: usize, y: usize, rib: u8) u8 {
    var i: u8 = assets.bg[y * W + x];
    if (rib != 0) i = (i & ~@as(u8, 3)) | rib;
    if (y < BAT_ROWS) i = (i & 3) | (if (batHit(meters, x, y)) @as(u8, 4) else 0);
    return i;
}

/// A 4-bit run of bat mask (leftmost pixel in bit 3) as 4 index bytes of 4|0.
const LIT: [16]u32 = blk: {
    var t: [16]u32 = undefined;
    for (0..16) |n| {
        var v: u32 = 0;
        for (0..4) |i| v |= @as(u32, (n >> (3 - i)) & 1) << (8 * i + 2);
        t[n] = v;
    }
    break :blk t;
};

/// The lit words of the three bat windows: (bg % 4) | 4 where the mask is set
/// (shade() with no ribbon), 4 pixels a store; unlit words are BG's already.
fn bats(out: [*]u32, meters: [3]u8) void {
    const bgw: [*]const u32 = @ptrCast(@alignCast(assets.bg)); // 4-aligned (assets.embed4)
    for (0..3) |b| {
        const mask = assets.bats[(15 - @as(usize, meters[b])) * 256 ..][0..256];
        for (0..BAT_ROWS) |y| {
            for (0..8) |byte| {
                const m = mask[y * 8 + byte];
                if (m == 0) continue;
                const w = y * 80 + b * 32 + byte * 2;
                if (m >> 4 != 0) out[w] = (bgw[w] & 0x03030303) | LIT[m >> 4];
                if (m & 15 != 0) out[w + 1] = (bgw[w + 1] & 0x03030303) | LIT[m & 15];
            }
        }
    }
}

fn ribbonRow(out: [*]u32, meters: [3]u8, r: usize, y: usize, x0: i32) void {
    const lo: i32 = @max(x0, 0);
    const hi: i32 = @min(x0 + 112, @as(i32, W));
    if (lo >= hi) return;
    var w: usize = @as(usize, @intCast(lo)) / 4;
    while (w * 4 < @as(usize, @intCast(hi))) : (w += 1) {
        var v: u32 = 0;
        for (0..4) |k| {
            const x = w * 4 + k;
            const dx = @as(i32, @intCast(x)) - x0;
            const rib: u8 = if (dx >= 0 and dx < 112) assets.ribbon[r * 112 + @as(usize, @intCast(dx))] & 3 else 0;
            v |= @as(u32, shade(meters, x, y, rib)) << @intCast(8 * k);
        }
        out[y * 80 + w] = v;
    }
}

pub fn render(comptime G: type, g: *G, c: *const Clock, meters: [3]u8) void {
    g.copy(gpu.WORK, gpu.BG);
    const out = g.words(gpu.WORK);
    bats(out, meters);
    for (0..50) |r| {
        const yy = @as(i32, c.y) + @as(i32, @intCast(r));
        if (yy < 0 or yy >= H) continue;
        ribbonRow(out, meters, r, @intCast(yy), c.history[r]);
    }
    g.copy(gpu.SHOWN, gpu.WORK);
}
