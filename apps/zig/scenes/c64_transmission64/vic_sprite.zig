// --------------------------------------------------------------------------
// The eight sprites on one window line.
//
// A sprite with Y = y shows its rows on lines y+1..y+21 (y+1..y+42 Y-expanded), at physical
// column X + 16 (X wraps at 504 on PAL); sprite 0 in front of 1, and so on. Its data is the
// pointer at screen + $3F8 + i, times 64, in the VIC's bank. Hires: a set bit is the sprite's
// colour; multicolour: pairs 01 $D025, 10 the sprite's colour, 11 $D026. The side borders are
// never opened here, so a sprite is cut at the window's edges.
// Not modelled: the background-priority bit ($D01B; this invitation never sets it) and a
// sprite re-triggered by raster line + 256 (no Y below 56 here).
// --------------------------------------------------------------------------
const line_mod = @import("vic_line.zig");
const Ctx = line_mod.Ctx;

const PAL_X = 504;
const LEFT = 40; // the window, physical columns
const RIGHT = 360;

/// Whether an enabled sprite shows a row on `line` (vic_dirty.zig redraws such lines).
pub fn covers(ctx: Ctx, line: u16) bool {
    const reg = ctx.reg;
    if (reg[0x15] == 0) return false;
    for (0..8) |s| {
        const b = @as(u8, 1) << @intCast(s);
        if (reg[0x15] & b == 0) continue;
        const y: u16 = reg[1 + 2 * s];
        const h: u16 = if (reg[0x17] & b != 0) 42 else 21;
        if (line > y and line <= y + h) return true;
    }
    return false;
}

pub fn draw(ctx: Ctx, line: u16, row: *[400]u8) void {
    const reg = ctx.reg;
    if (reg[0x15] == 0) return;
    const ptrs = ctx.screen() + 0x3F8;
    var s: u3 = 7;
    while (true) : (s -= 1) {
        const b = @as(u8, 1) << s;
        if (reg[0x15] & b != 0) one(ctx, s, b, line, ptrs, row);
        if (s == 0) break;
    }
}

fn one(ctx: Ctx, s: u3, b: u8, line: u16, ptrs: u16, row: *[400]u8) void {
    const reg = ctx.reg;
    const y: u16 = reg[1 + 2 * @as(usize, s)];
    if (line <= y) return;
    var dy = line - y - 1;
    if (reg[0x17] & b != 0) dy /= 2;
    if (dy >= 21) return;
    const ptr: u16 = ctx.mem.vic(ctx.bank, ptrs + s);
    const base = ptr * 64 + dy * 3;
    const bits: u32 = (@as(u32, ctx.mem.vic(ctx.bank, base)) << 16) |
        (@as(u32, ctx.mem.vic(ctx.bank, base + 1)) << 8) | ctx.mem.vic(ctx.bank, base + 2);
    if (bits == 0) return;
    const x0: u32 = reg[2 * @as(usize, s)] | (@as(u32, (reg[0x10] >> s) & 1) << 8);
    const xe: u32 = if (reg[0x1D] & b != 0) 2 else 1;
    const mc = reg[0x1C] & b != 0;
    const cs = [4]u8{ 0, (reg[0x25] & 15) + 1, (reg[0x27 + @as(usize, s)] & 15) + 1, (reg[0x26] & 15) + 1 };
    var c: u32 = (x0 + 16) % PAL_X;
    var p: u5 = 0;
    while (true) : (p += 1) {
        // multicolour: pixels 2k and 2k+1 both show pair k (bits 23-2k, 22-2k)
        const ink: u8 = if (mc) cs[@intCast((bits >> (22 - (p & 0x1E))) & 3)] else if ((bits >> (23 - @as(u5, p))) & 1 != 0) cs[2] else 0;
        for (0..xe) |_| {
            if (ink != 0 and c >= LEFT and c < RIGHT) row[c] = ink;
            c += 1;
            if (c == PAL_X) c = 0;
        }
        if (p == 23) break;
    }
}
