// --------------------------------------------------------------------------
// The main loop's two routines, after each Vsync:
//   $930 the text columns (planes 0 and 1, x 0..63 and 256..319): plane 0
//        moves up one line a frame, plane 1 two, and lines 41/42 are OR-ed back
//        in at 168/169, so each layer is a 127-line ring. Call 300 hands over to
//        the scroller (and freezes the stars) but still scrolls that frame.
//   $AA2 the four STCS letters (plane 2): each erased, moved along the path
//        tables and OR-drawn, the path index stepping once per letter.
// --------------------------------------------------------------------------
const std = @import("std");
const A = @import("assets.zig");
const machine = @import("machine.zig");
const Machine = machine.Machine;

const FIRST: usize = 43;
const LINES: usize = 129; // 43..171
const HANDOVER: u16 = 300;
const PATH_END: u16 = 0x3A8C; // 14988
const PATH_Y: u8 = 0x46; // screen y = path y + 70
const LETTER_GAP: u16 = 16; // path entries between letters, before the per-letter step

pub fn columns(m: *Machine) void {
    if (!m.columns_on) return;
    m.columns_calls += 1;
    if (m.columns_calls == HANDOVER) {
        m.columns_calls = 0;
        m.scroller_on = true;
        m.stars_on = false;
        m.columns_on = false;
    }
    const s = &machine.screen;
    for ([_]usize{ 0, 0x80 }) |x0| {
        for (FIRST..FIRST + LINES) |y| {
            for (0..4) |g| {
                const a = y * A.LINE + x0 + 8 * g;
                A.put16(s, a - A.LINE, A.be16(s, a)); // plane 0: one line up
                A.put16(s, a + 2 - 2 * A.LINE, A.be16(s, a + 2)); // plane 1: two
            }
        }
    }
    // $9E6: planes 0+1 of lines 41, 42 OR-ed into 168, 169
    for ([_]usize{ 0, 0x80 }) |x0| {
        for (0..2) |y| {
            for (0..4) |g| {
                const src = (41 + y) * A.LINE + x0 + 8 * g;
                const dst = (168 + y) * A.LINE + x0 + 8 * g;
                A.put32(s, dst, A.be32(s, dst) | A.be32(s, src));
            }
        }
    }
}

pub fn letters(m: *Machine) void {
    for (0..4) |_| {
        const k: usize = m.letter;
        blit(k, m.letter_x[k], m.letter_y[k], false);
        const ku: u16 = @intCast(k);
        const off: u16 = if (m.backward) ku * LETTER_GAP else (3 - ku) * LETTER_GAP;
        const at: usize = m.path + off;
        const x = A.path_x[at];
        const y = A.path_y[at] +% PATH_Y;
        m.letter_x[k] = x;
        m.letter_y[k] = y;
        blit(k, x, y, true);
        m.letter = (m.letter + 1) & 3;
        if (!m.backward) {
            m.path += 1;
            if (m.path == PATH_END) m.backward = true;
        } else {
            m.path -= 1;
            if (m.path == 0) m.backward = false;
        }
    }
}

/// 17 lines of the letter's word ror.l-ed by x & 15: the low word ORs (or
/// and-nots) into group x >> 4, the high word into the next group.
fn blit(k: usize, x: u8, y: u8, draw: bool) void {
    const s = &machine.screen;
    const base: usize = 4 + @as(usize, y) * A.LINE + ((@as(usize, x) >> 1) & 0xF8);
    const sh: u5 = @intCast(x & 15);
    for (0..A.LETTER_WORDS) |i| {
        const wd: u32 = A.be16(A.letters, (k * A.LETTER_WORDS + i) * 2);
        const v = std.math.rotr(u32, wd, sh);
        const lo: u16 = @truncate(v);
        const hi: u16 = @truncate(v >> 16);
        const a = base + A.LINE * i;
        if (draw) {
            A.put16(s, a, A.be16(s, a) | lo);
            A.put16(s, a + 8, A.be16(s, a + 8) | hi);
        } else {
            A.put16(s, a, A.be16(s, a) & ~lo);
            A.put16(s, a + 8, A.be16(s, a + 8) & ~hi);
        }
    }
}
