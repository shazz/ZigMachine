// --------------------------------------------------------------------------
// The sprites (the model's d_draw.py, literal): the per-slot bounds check +
// masked blit + dirty-rect record that follows every handler ($3AB14-$3ADA0),
// the slot kill $3A6C0, and the erase of the rects $3A70E (call 9).
//
// The blit keeps the 68000's register moves: a sprite line is four longs
// (d0-d3 by movem), the mask NOT(d0|d1|d2|d3); aligned, the high words go to
// the left 16-px group and the low words to the right one; shifted (x & 15),
// ror.l over THREE groups, and the rect is marked 'shifted' (bit1).
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");

const M32: i64 = 0xFFFFFFFF;

fn swap(x: i64) i64 {
    return ((x << 16) | ((x & M32) >> 16)) & M32;
}
fn ror(x: i64, n: i64) i64 {
    const s: u6 = @intCast(@mod(n & 63, 32));
    if (s == 0) return x & M32;
    const v: u64 = @intCast(x & M32);
    return @intCast(((v >> s) | (v << @intCast(32 - @as(u7, s)))) & 0xFFFFFFFF);
}
fn lo(x: i64, w: i64) i64 {
    return (x & 0xFFFF0000) | (w & 0xFFFF);
}

fn rectOff() i64 {
    return if (m.rl(F.SCREEN_PTR) & 0x8000 != 0) 0x16 else 0x1C;
}

/// $3A70E: every slot's dirty rect restored ON THE BACK SCREEN from the clean
/// copy $65B00 (same offset). A dead slot is erased only if bit2 is set (and
/// bit2 is cleared). Nothing is erased while the scroll runs ($3A180).
pub fn erase() void {
    const back = m.rl(F.SCREEN_PTR) ^ 0x8000;
    var a = F.ENT;
    while (m.rw(a) != 0xFFFF) : (a += F.ENT_SZ) {
        const rect = a + rectOff();
        var flags = m.rb(rect);
        if (m.rw(a) == 0) {
            if (flags & 4 == 0) continue;
            flags &= ~@as(i64, 4);
            m.wb(rect, flags);
        }
        if (flags & 1 == 0 or m.rb(F.SCROLL_ON) != 0) continue;
        const off = m.rw(rect + 4);
        const n = m.rw(rect + 2);
        const lines: i64 = if (n == 0x14) 21 else n + 1;
        const width: i64 = if (flags & 2 != 0) 24 else 16;
        const src = 0x65B00 + off;
        const dst = (back + off) & 0xFFFFFF;
        var y: i64 = 0;
        while (y < lines) : (y += 1) m.copy(dst + 160 * y, src + 160 * y, width);
    }
}

/// $3A6C0: type = 0; the rect of the DISPLAYED screen erased once more (bit2).
pub fn killSlot(a0: i64) void {
    m.ww(a0, 0);
    const r = a0 + (if (m.rl(F.SCREEN_PTR) & 0x8000 != 0) @as(i64, 0x1C) else 0x16);
    m.wb(r, m.rb(r) | 4);
}

/// The draw unit of slot `slot` (pkg_d.draw_slot).
pub fn drawSlot(slot: i64) void {
    const a0 = F.ENT + F.ENT_SZ * slot;
    if (m.rw(a0) != 0) drawSlotAt(a0);
}

/// $3AB14 with a0 = the slot.
pub fn drawSlotAt(a0: i64) void {
    const x = m.sw(a0 + 4);
    if (x < -8 or x > 0xF0) return killSlot(a0);
    const y0 = m.sw(a0 + 6);
    if (y0 < 0 or y0 > 0x142) return killSlot(a0);
    const d0 = m.rl(F.SCREEN_PTR) ^ 0x8000;
    const r = a0 + rectOff();
    m.ww(r, 0x0100);
    var h = m.rw(a0 + 0x14);
    if (h == 0) h = 0x15;
    const sprite = m.rl(a0 + 0x22);
    if (sprite == 0 or x < 0 or x > 0xE8) return m.wb(r, m.rb(r) & ~@as(i64, 1));
    const c = clipY(y0, h, sprite) orelse return m.wb(r, m.rb(r) & ~@as(i64, 1));
    const y = c.y;
    const a6 = c.a6;
    const lines = (c.h - 1) & 0xFFFF;
    m.ww(r + 2, lines);
    const xx = (x + 0x20) & 0xFFFF;
    const off = (((y - 0x38) * 160) + ((xx & 0xFFF0) >> 1)) & 0xFFFF;
    m.ww(r + 4, off);
    const a2 = (d0 + off) & M32;
    const s = xx & 15;
    if (s != 0) {
        m.wb(r, m.rb(r) | 2);
        blitShifted(a6, a2, s, lines);
    } else {
        blitAligned(a6, a2, lines);
    }
}

const Clip = struct { y: i64, h: i64, a6: i64 };

/// The playfield's top ($40: the sprite's first lines skipped) and bottom
/// ($FF) edges; null when nothing of it is visible.
fn clipY(y: i64, h: i64, a6: i64) ?Clip {
    if (y < 0x40) {
        if (y <= m.s16(0x40 - h)) return null;
        const d6 = 0x40 - y;
        return .{ .y = 0x40, .h = h - d6, .a6 = (a6 + (d6 << 4)) & M32 };
    }
    if (y > m.s16(0xFF - h)) {
        if (y >= 0xFF) return null;
        return .{ .y = y, .h = 0x100 - y, .a6 = a6 };
    }
    return .{ .y = y, .h = h, .a6 = a6 };
}

/// $3AD38: 16-px aligned, 2 groups; the low words go to the right group.
fn blitAligned(a6_: i64, a2_: i64, d7_: i64) void {
    var a6 = a6_;
    var a2 = a2_;
    var d7 = d7_;
    while (true) {
        const d = [4]i64{ m.rl(a6), m.rl(a6 + 4), m.rl(a6 + 8), m.rl(a6 + 12) };
        a6 += 16;
        const d4 = ~(d[0] | d[1] | d[2] | d[3]) & M32;
        halfGroup(a2 + 8, d, d4);
        halfGroup(a2, .{ swap(d[0]), swap(d[1]), swap(d[2]), swap(d[3]) }, swap(d4));
        a2 += 0xA0;
        d7 = (d7 - 1) & 0xFFFF;
        if (d7 == 0xFFFF) return;
    }
}

fn halfGroup(base: i64, w: [4]i64, mask: i64) void {
    const d5 = ((mask & 0xFFFF) << 16) | (mask & 0xFFFF);
    putPair(base, d5, w[0], w[1]);
    putPair(base + 4, d5, w[2], w[3]);
}

/// move.l (a),d6; and.l d5,d6; or.w lo,d6; swap; or.w hi,d6; swap; move.l d6,(a)
fn putPair(a: i64, d5: i64, hi: i64, lo_: i64) void {
    var d6 = m.rl(a) & d5;
    d6 |= lo_ & 0xFFFF;
    d6 = swap(d6) | (hi & 0xFFFF);
    m.wl(a, swap(d6));
}

/// $3AC3C: shifted by s = 1..15, 3 groups (a2, a3 = +8, a4 = +16), word by word.
fn blitShifted(a6_: i64, a2_: i64, s: i64, a5_: i64) void {
    var a6 = a6_;
    var a2 = a2_;
    var a5 = a5_;
    while (true) {
        const d = [4]i64{ m.rl(a6), m.rl(a6 + 4), m.rl(a6 + 8), m.rl(a6 + 12) };
        a6 += 16;
        const mk = shiftedMasks(d, s);
        // a2 / a3 = +8 / a4 = +16 step 2 a plane; then adda #$9A: $A0 a line
        for (0..4) |k| shiftedWord(a2 + 2 * @as(i64, @intCast(k)), d[k], s, mk[0], mk[1]);
        a2 += 0xA0;
        const d7c = (a5 - 1) & 0xFFFF;
        if (d7c == 0xFFFF) return;
        a5 = d7c;
    }
}

/// The line's mask NOT(d0|d1|d2|d3) shifted over the three groups: d4 (the
/// left word) and d5 (high word: the right group's, low: the middle's).
fn shiftedMasks(d: [4]i64, s: i64) [2]i64 {
    var d4 = ~(d[0] | d[1] | d[2] | d[3]) & M32;
    var d5 = 0xFFFF0000 | (d4 & 0xFFFF);
    d4 = swap((d4 & 0xFFFF0000) | 0xFFFF);
    d4 = ror(d4, s);
    d5 = ror(d5, s);
    d4 = swap(d4);
    d5 = lo(d5, d5 & d4);
    d4 = swap(d4);
    return .{ d4, d5 };
}

/// One plane's long v, shifted right by s, into the words at a2, a2+8, a2+16.
fn shiftedWord(a2: i64, v0: i64, s: i64, d4: i64, d5: i64) void {
    var v = v0;
    var d7 = v & 0xFFFF;
    v = swap(v & 0xFFFF0000);
    v = ror(v, s);
    d7 = ror(d7, s);
    v = swap(v);
    d7 = lo(d7, d7 | v);
    v = swap(v);
    m.ww(a2, (m.rw(a2) & d4) | (v & 0xFFFF));
    m.ww(a2 + 8, (m.rw(a2 + 8) & d5) | (d7 & 0xFFFF));
    d7 = swap(d7);
    m.ww(a2 + 16, (m.rw(a2 + 16) & (swap(d5) & 0xFFFF)) | (d7 & 0xFFFF));
}
