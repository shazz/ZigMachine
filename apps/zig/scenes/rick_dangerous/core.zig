// --------------------------------------------------------------------------
// Shared pieces (the model's core.py): packed BCD (abcd / sbcd) and the tile
// printer $38EE8 with its 8x8 tile draw $38F64.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");

pub const Bcd = struct { r: i64, c: i64 };

/// abcd a + b + x.
pub fn bcdAdd(a: i64, b: i64, x: i64) Bcd {
    var lo = (a & 15) + (b & 15) + x;
    var c: i64 = 0;
    if (lo > 9) lo += 6;
    var hi = (a >> 4) + (b >> 4) + (lo >> 4);
    if (hi > 9) {
        hi += 6;
        c = 1;
    }
    return .{ .r = ((hi << 4) | (lo & 15)) & 0xFF, .c = c };
}

/// sbcd a - b - x.
pub fn bcdSub(a: i64, b: i64, x: i64) Bcd {
    var lo = (a & 15) - (b & 15) - x;
    var borrow_lo: i64 = 0;
    if (lo < 0) {
        lo += 10;
        borrow_lo = 1;
    }
    var hi = (a >> 4) - (b >> 4) - borrow_lo;
    var c: i64 = 0;
    if (hi < 0) {
        hi += 10;
        c = 1;
    }
    return .{ .r = ((hi << 4) | lo) & 0xFF, .c = c };
}

pub const FONT: i64 = 0xAAA0;

/// $38F64: one 8x8 tile at screen byte address a (8 lines, planes at +0/+2/+4/+6).
pub fn drawTile(a: i64, tile: i64) void {
    const src = FONT + 32 * tile;
    var y: i64 = 0;
    while (y < 8) : (y += 1) {
        var p: i64 = 0;
        while (p < 4) : (p += 1) m.wb(a + 160 * y + 2 * p, m.rb(src + 4 * y + p));
    }
}

/// $38EE8(d0 = screen byte offset, a0 = $FF-terminated tile string): prints on
/// BOTH screens. An odd offset is the right half of a 16-px group; the next
/// glyph goes to the next half (+8 when it wraps to the next group).
pub fn printText(off0: i64, text: i64) void {
    var off = off0;
    var a = text;
    while (true) {
        const t = m.rb(a);
        a += 1;
        if (t == 0xFF) return;
        for (F.SCREENS) |base| drawTile((base + off) & 0xFFFFFF, t);
        if (off & 1 != 0) off = (off ^ 1) + 8 else off |= 1;
    }
}
