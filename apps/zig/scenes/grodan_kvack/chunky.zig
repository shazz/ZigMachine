// --------------------------------------------------------------------------
// grodan_kvack -- every layer's art expanded ONCE to chunky (one palette index
// a byte, 0 = transparent) in cart RAM, so a frame is CHISEL blits from it.
//
// The first port tested a 1-bit mask per pixel and stored a byte per set pixel
// for all six layers every frame (two full-screen tile layers alone were
// 128,000 bit tests).  Each image here is the exact pixel set model.zig's draw
// functions paint, in the same per-layer order, so a keyed blit (key 0) of it
// paints the same bytes:
//
//   green, pink   320x199  the two tiled line-art masks, in GREEN / PINK
//   sprites       12 x 16x10  sprite frame i = mask columns i*17 .. +15
//   big           one 96x99 image per glyph cell main.cells USES (Scale 4:3)
//   vert[p]       the WHOLE vertical text as a 16-wide strip, glyph k at row
//                 floor((p + 29k)/2), for both parities p of the scroll base
//                 (drawVert floors (base + 29k)/2, so the glyphs' spacing
//                 depends on base's parity); later glyphs overwrite earlier
//                 ones exactly as drawVert's loop does
//   small[i]      the whole small text i as an 8-row strip, cell k at x = 8k
//
// ~830 KB of cart RAM (zg.mem), built at init (~1 Mc once).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");

pub const BIG_W = 96;
pub const BIG_H = 99;
pub const VERT_W = 16;
pub const VERT_GLYPH_H = 15;

/// main.cells' cell -> slot in `big` (0xFF: never used), and the slot count.
pub const BIG_SLOT: [256]u8 = blk: {
    @setEvalBranchQuota(20_000);
    var t: [256]u8 = @splat(0xFF);
    var n: usize = 0;
    for (A.main_cells) |c| {
        if (c != 0xFF and t[c] == 0xFF) {
            t[c] = n;
            n += 1;
        }
    }
    break :blk t;
};
const BIG_SLOTS: usize = blk: {
    var n: usize = 0;
    for (BIG_SLOT) |s| {
        if (s != 0xFF) n += 1;
    }
    break :blk n;
};

/// Strip row of vertical glyph k for base parity p.
pub inline fn vertOff(p: i32, k: usize) i32 {
    return @divFloor(p + 29 * @as(i32, @intCast(k)), 2);
}
pub const VERT_ROWS: [2]usize = .{
    @intCast(vertOff(0, A.vert_cells.len - 1) + VERT_GLYPH_H),
    @intCast(vertOff(1, A.vert_cells.len - 1) + VERT_GLYPH_H),
};

pub const Art = struct {
    green: []u8,
    pink: []u8,
    sprites: []u8,
    big: []u8,
    vert: [2][]u8,
    small: [2][]u8,
};

pub var art: ?Art = null;

/// Build the art the first time; null when cart RAM is short (the caller then
/// keeps the CPU composer).
pub fn get() ?*const Art {
    if (art == null) art = build();
    return if (art) |*a| a else null;
}

fn build() ?Art {
    const m = zg.mem.mark();
    const a = Art{
        .green = zg.mem.alloc(u8, A.BG_W * A.BG_H) orelse return fail(m),
        .pink = zg.mem.alloc(u8, A.BG_W * A.BG_H) orelse return fail(m),
        .sprites = zg.mem.alloc(u8, 12 * 16 * A.SPRITE_H) orelse return fail(m),
        .big = zg.mem.alloc(u8, BIG_SLOTS * BIG_W * BIG_H) orelse return fail(m),
        .vert = .{
            zg.mem.alloc(u8, VERT_ROWS[0] * VERT_W) orelse return fail(m),
            zg.mem.alloc(u8, VERT_ROWS[1] * VERT_W) orelse return fail(m),
        },
        .small = .{
            zg.mem.alloc(u8, A.small1_cells.len * 64) orelse return fail(m),
            zg.mem.alloc(u8, A.small2_cells.len * 64) orelse return fail(m),
        },
    };
    expandMask(a.green, A.bg_green, A.BG_W, A.BG_H, A.GREEN);
    expandMask(a.pink, A.bg_pink, A.BG_W, A.BG_H, A.PINK);
    buildSprites(a.sprites);
    buildBig(a.big);
    buildVert(a.vert[0], 0);
    buildVert(a.vert[1], 1);
    buildSmall(a.small[0], A.small1_cells);
    buildSmall(a.small[1], A.small2_cells);
    return a;
}

fn fail(m: zg.mem.Mark) ?Art {
    zg.mem.release(m);
    return null;
}

fn expandMask(out: []u8, mask: []const u8, w: usize, h: usize, color: u8) void {
    for (0..h) |y| {
        for (0..w) |x| out[y * w + x] = if (A.bit(mask, x, y, w) != 0) color else 0;
    }
}

fn buildSprites(out: []u8) void {
    for (0..12) |i| {
        for (0..A.SPRITE_H) |sy| {
            for (0..16) |sx| {
                const on = A.bit(A.sprite, i * A.SPRITE_STRIDE + sx, sy, A.SPRITE_W) != 0;
                out[(i * A.SPRITE_H + sy) * 16 + sx] = if (on) A.SPRITE else 0;
            }
        }
    }
}

/// glyphBig's pixel set: (dx, dy) is font bit (col*24 + dx/4, row*33 + dy/3).
fn buildBig(out: []u8) void {
    for (BIG_SLOT, 0..) |slot, cell| {
        if (slot == 0xFF) continue;
        const img = out[@as(usize, slot) * BIG_W * BIG_H ..][0 .. BIG_W * BIG_H];
        const col = cell % 10;
        const row = cell / 10;
        for (0..BIG_H) |dy| {
            for (0..BIG_W) |dx| {
                const on = A.bit(A.bsfont, col * 24 + dx / 4, row * 33 + dy / 3, A.BSF_W) != 0;
                img[dy * BIG_W + dx] = if (on) A.BIG else 0;
            }
        }
    }
}

/// glyphUp's pixel set for every cell, in drawVert's order (a later glyph's
/// set pixels land over an earlier one's; unset pixels never erase).
fn buildVert(out: []u8, p: i32) void {
    @memset(out, 0);
    for (A.vert_cells, 0..) |c, k| {
        if (c == 0xFF) continue;
        const col: usize = c % 10;
        const row: usize = c / 10;
        const y0: usize = @intCast(vertOff(p, k));
        for (0..VERT_GLYPH_H) |dy| {
            for (0..VERT_W) |dx| {
                if (A.bit(A.upfont, col * 33 + 2 * dx, row * 29 + 2 * dy, A.UPF_W) != 0)
                    out[(y0 + dy) * VERT_W + dx] = A.VERT;
            }
        }
    }
}

/// glyphSmall's pixel set, cell k at x = 8k of an 8-row strip.
fn buildSmall(out: []u8, cells: []const u8) void {
    const w = cells.len * 8;
    for (cells, 0..) |c, k| {
        for (0..8) |dy| {
            for (0..8) |dx| {
                const on = c != 0xFF and
                    A.bit(A.lfont, (c % 10) * 8 + dx, (c / 10) * 8 + dy, A.LF_W) != 0;
                out[dy * w + k * 8 + dx] = if (on) A.SMALL else 0;
            }
        }
    }
}
