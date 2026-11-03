// --------------------------------------------------------------------------
// TC TEST's moving view: a 512x320 RGB565 plasma painted ONCE into VRAM, wider and
// taller than the 400x280 screen and periodic both ways, then warped every frame by
// the plane's copper list alone: each raster line's LBASE picks a texture row (a
// rolling, breathing line zoom) and its HSCROLL a byte offset (a travelling sine
// shear). The CPU writes ~2 list words a line and no pixel (fixtrig: no float).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ft = zg.fixtrig;
const paint = @import("paint.zig");

pub const TW: u32 = 512;
pub const TH: u32 = 320;
const ROW_BYTES: u32 = TW * 2;
const SLACK: u32 = TW - 400; // pixels HSCROLL may move right of a row's start

pub const Texture = struct { pixels: [*]align(4) u16, off: u32 };

// An angle of `turns` whole turns per `period` texels at texel n (periodic: n = period is 0).
fn wave(n: u32, turns: u32, period: u32) ft.Angle {
    return @truncate((@as(u64, n) * turns << 32) / period);
}

fn chan(a: ft.Angle, w: i32) u32 {
    const c: i32 = (128 * ft.ONE + 127 * ft.sin(a)) >> 16;
    return @intCast(c * w >> 8);
}

// Hue from three crossing sine fields, each channel's phase pushed apart by a fourth field and
// brightness from a fifth: no two channels follow one curve, so the 565 picture holds tens of
// thousands of colours (one hue field alone gave ~4,400 on screen).
fn texel(x: u32, y: u32) u16 {
    const v = ft.sin(wave(x, 2, TW)) + ft.sin(wave(y, 3, TH)) + ft.sin(wave(x, 1, TW) +% wave(y, 2, TH));
    const h: ft.Angle = @as(u32, @bitCast(v)) *% 21845;
    const u: ft.Angle = @as(u32, @bitCast(ft.sin(wave(x, 3, TW) +% wave(y, 1, TH)))) *% 12000; // +-0.18 turn
    const w: i32 = 150 + (105 * ft.sin(wave(x, 1, TW) -% wave(y, 1, TH)) >> 16);
    const third: ft.Angle = 0x5555_5555; // a third of a turn
    return paint.to565(.{ chan(h, w), chan(h +% third +% u, w), chan(h +% 2 *% third -% u, w) });
}

/// The texture in VRAM (an LBASE must name VRAM), painted; null when the pool is full.
pub fn build() ?Texture {
    const v = zg.vramWords(TW * TH / 2) orelse return null;
    const px: [*]align(4) u16 = @ptrCast(v.words.ptr);
    for (0..TH) |y| for (0..TW) |x| {
        px[y * TW + x] = texel(@intCast(x), @intCast(y));
    };
    return .{ .pixels = px, .off = v.off };
}

const ROLL = ft.angle(0.021); // per frame
const SHEAR = ft.angle(0.034);
const LINE_A = ft.angle(0.045); // per line
const LINE_B = ft.angle(0.017);

/// Raster line y's source this frame (fc): texture row and byte offset.
pub fn line(t: Texture, y: u32, fc: u32) zg.linelist.Line {
    const zoom: i32 = 256 + (64 * ft.sin(fc *% ROLL) >> 16); // 192..320 / 256 rows a line
    const ripple: i32 = 18 * ft.sin(fc *% SHEAR +% y *% LINE_B) >> 16;
    const r: i32 = @divFloor(@as(i32, @intCast(y)) * zoom, 256) + @as(i32, @intCast(fc % TH)) + ripple;
    const row: u32 = @intCast(@mod(r, @as(i32, TH)));
    const a: i32 = 40 * ft.sin(fc *% SHEAR +% y *% LINE_A) + 15 * ft.sin(fc *% ROLL *% 3 -% y *% (LINE_B *% 3));
    const px: u32 = @intCast(@as(i32, SLACK / 2) + (a >> 16)); // 1..111: the row's 400 pixels stay in it
    return .{ .base = t.off + row * ROW_BYTES, .hscroll = @intCast(px * 2) };
}
