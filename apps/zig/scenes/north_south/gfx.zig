// --------------------------------------------------------------------------
// ns.app's graphics primitives, at pixel level. A screen is 320x200 colour
// indices; the original's are ST planar screens, and every primitive below
// writes the pixels the 68000 routine writes into them.
//
//   blit  = $143FC  masked sprite draw (colour 0 transparent), (x, y) = the
//                   BOTTOM-left corner, clipped to (0,319)x(0,199) with the
//                   original's edge rules; frame bit 15 = mirrored
//   plot  = $1539C  one pixel in the pen colour, with NO clipping: the address
//                   is computed as the 68000 does, and a pixel outside the
//                   screen lands where that address points (or nowhere here)
//   hline = $1426C  horizontal line, clipped, inclusive
// --------------------------------------------------------------------------
const A = @import("assets.zig");

pub const W: usize = 320;
pub const H: usize = 200;
pub const PIXELS: usize = W * H;

/// The two screen buffers and the background, keyed by the RAM address the
/// game keeps in $1CD28 / $1CF16 / $1C934. Module scope: 192 KB is not the
/// Demo struct's.
pub var screens: [3][PIXELS]u8 = undefined;
pub const SCREEN_ADDR = [3]u32{ 0x2AC00, 0xF8000, 0x9C712 };

pub fn screenAt(addr: u32) ?*[PIXELS]u8 {
    for (SCREEN_ADDR, 0..) |a, i| if (a == addr) return &screens[i];
    return null;
}

/// What a blit cost, for the pacing model: rows drawn, 16-px words a row,
/// the shift, and whether it was clipped.
pub const BlitCost = struct { rows: i32, words: i32, sh: i32, clipped: bool };

pub fn blit(scr: *[PIXELS]u8, bank: A.BankId, frame_in: i32, x: i32, y: i32) ?BlitCost {
    const frame: u32 = @as(u16, @truncate(@as(u32, @bitCast(frame_in))));
    const s = A.banks[@intFromEnum(bank)].get(frame & 0x3FFF) orelse return null;
    const w: i32 = s.w;
    var h: i32 = s.h;
    const top = y - h + 1;
    const d1 = 199 - top; // bottom clip ($1DA76)
    if (d1 <= 0) return null;
    if (d1 < h) h = d1 + 1;
    var r0: i32 = 0;
    if (top < 0) { // top clip ($1DA74)
        r0 = -top;
        if (h - r0 <= 0) return null;
    }
    if (x >= 319) return null; // right edge ($1DA72): a sprite starting at 319 is skipped
    const x0 = @max(0, x);
    const x1 = @min(x + w - 1, 319);
    if (x1 < x0) return null;
    const mirror = frame & 0x8000 != 0;
    const cost = BlitCost{
        .rows = h - r0,
        .words = (x1 >> 4) - (x0 >> 4) + 1,
        .sh = (-x) & 15,
        .clipped = x < 0 or x + w - 1 > 319 or r0 > 0 or h < s.h,
    };
    const uw: usize = s.w;
    const span: usize = @intCast(x1 - x0 + 1);
    var r = r0;
    while (r < h) : (r += 1) {
        const row = s.pixels[@as(usize, @intCast(r)) * uw ..][0..uw];
        const dst = scr[@as(usize, @intCast(top + r)) * W + @as(usize, @intCast(x0)) ..][0..span];
        const first: usize = @intCast(x0 - x);
        if (mirror) {
            for (dst, 0..) |*d, i| {
                const c = row[uw - 1 - (first + i)];
                if (c != 0) d.* = c;
            }
        } else {
            for (dst, row[first..][0..span]) |*d, c| {
                if (c != 0) d.* = c;
            }
        }
    }
    return cost;
}

/// $1539C with the pen of $15380: the 68000's 16-bit address arithmetic.
pub fn plot(scr: *[PIXELS]u8, x: i32, y: i32, colour: u8) void {
    var d0: u32 = @as(u32, @bitCast(y *% 160)) & 0xFFFF;
    d0 = (d0 + ((@as(u32, @bitCast(x)) & 0xFFF0) >> 1)) & 0xFFFF;
    var off: i32 = if (d0 & 0x8000 != 0) @as(i32, @intCast(d0)) - 0x10000 else @intCast(d0);
    if (x & 8 != 0) off += 1;
    const bit = 7 - (x & 7);
    if (off < 0 or off >= 32000) return;
    const row: usize = @intCast(@divTrunc(off, 160));
    const rem: usize = @intCast(@mod(off, 160));
    const group = rem / 8;
    const byte = rem % 8;
    if (byte > 1) return; // would hit planes 1-3 of another word: not seen
    const px = group * 16 + byte * 8 + @as(usize, @intCast(7 - bit));
    scr[row * W + px] = colour;
}

pub fn hline(scr: *[PIXELS]u8, x0_in: i32, y: i32, x1_in: i32, colour: u8) void {
    if (y < 0 or y > 199) return;
    var x0 = x0_in;
    var x1 = x1_in;
    if (x0 > x1) {
        const t = x0;
        x0 = x1;
        x1 = t;
    }
    if (x0 > 319 or x1 < 0) return;
    x0 = @max(x0, 0);
    x1 = @min(x1, 319);
    const base = @as(usize, @intCast(y)) * W;
    @memset(scr[base + @as(usize, @intCast(x0)) .. base + @as(usize, @intCast(x1)) + 1], colour);
}

/// A 32000-byte ST low-res screen -> 64000 colour indices.
pub fn planarToIndices(src: *const [32000]u8, dst: *[PIXELS]u8) void {
    var i: usize = 0;
    while (i < 32000) : (i += 8) {
        const p0 = A.be16(src, i);
        const p1 = A.be16(src, i + 2);
        const p2 = A.be16(src, i + 4);
        const p3 = A.be16(src, i + 6);
        const base = (i / 8) * 16;
        for (0..16) |bi| {
            const sh: u4 = @intCast(15 - bi);
            dst[base + bi] = @intCast(((p0 >> sh) & 1) | ((p1 >> sh) & 1) << 1 | ((p2 >> sh) & 1) << 2 | ((p3 >> sh) & 1) << 3);
        }
    }
}
