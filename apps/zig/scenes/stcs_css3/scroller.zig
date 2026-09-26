// --------------------------------------------------------------------------
// The big scroller ($CAE, vbl slot 2, planes 0+1, screen lines 176..194).
//
// Four buffers, each 16 px out of phase with the next, and eight column
// entries: entry n is the glyph's current 16 px rol-ed left by 2n bits with
// the next 16 px shifting in. Each frame one buffer is shown and another is
// shifted a whole group left with an entry appended: 4 px a frame, a 32 px
// glyph every 8 frames. Phase ($E7AE) p shows buffer (p+1)&3 and shifts
// buffer p&3 with entry 2(p&3); phase 0 fetches the next glyph, phases 0 and
// 4 build the entries from its left and right halves.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const machine = @import("machine.zig");
const Machine = machine.Machine;

const SCREEN_AT: usize = 0x6E00; // line 176
const SPACE: u8 = 0x34;
const LOOKAHEAD_BLANK: u8 = 0xE0; // a look-ahead code above this reads as a space

pub fn step(m: *Machine) void {
    if (!m.scroller_on) return;
    if (A.text[m.text_at] == A.TEXT_PAUSE) {
        // back to the columns and the stars; the glyph after $F0 comes next
        m.scroller_on = false;
        m.columns_on = true;
        m.stars_on = true;
        m.text_at += 1;
        return;
    }
    const ph = m.phase;
    m.phase = (ph + 1) & 7;
    display(&machine.bufs[(ph + 1) & 3]);
    if (ph == 0) {
        m.half = 0;
        fetch(m);
        build(m);
    } else if (ph == 4) {
        m.half = 8;
        build(m);
    }
    shift(&machine.bufs[ph & 3], &m.cols[2 * (ph & 3)]);
}

/// Phase 0: the glyph at $E7AC ($3F wraps to the start) and a look at the next.
fn fetch(m: *Machine) void {
    while (A.text[m.text_at] == A.TEXT_WRAP) m.text_at = 0;
    m.glyph_cur = A.glyph(A.text[m.text_at]);
    m.text_at += 1;
    var c = A.text[m.text_at];
    if (c > LOOKAHEAD_BLANK) c = SPACE;
    if (c == A.TEXT_WRAP) c = A.text[0];
    m.glyph_next = A.glyph(c);
}

/// $E98: 19 lines of planes 0+1 to the screen.
fn display(buf: *const [A.BUF_BYTES]u8) void {
    for (0..A.SCROLL_LINES) |y| {
        for (0..20) |g| {
            const o = y * A.LINE + 8 * g;
            @memcpy(machine.screen[SCREEN_AT + o ..][0..4], buf[o..][0..4]);
        }
    }
}

/// $E0E: 18 lines one group left, the column entry appended at group 19.
fn shift(buf: *[A.BUF_BYTES]u8, col: *const [A.SCROLL_LINES]u32) void {
    for (0..A.SCROLL_LINES - 1) |y| {
        const row = buf[y * A.LINE ..][0..A.LINE];
        for (0..19) |g| @memcpy(row[8 * g ..][0..4], row[8 * g + 8 ..][0..4]);
        A.put32(row, 8 * 19, col[y]);
    }
}

/// $EB2: entry 0 is the half as it is; entry n = (cur << 2n) | (next >> 16-2n)
/// per plane word, where `next` is the other half of the glyph (half 0) or the
/// next glyph's left half (half 8).
fn build(m: *Machine) void {
    const d4 = m.glyph_cur;
    const d6: u32 = m.half;
    const d5: u32 = if (d6 == 8) m.glyph_next -% d4 else 8;
    for (0..A.SCROLL_LINES) |y| m.cols[0][y] = A.be32(A.font, d4 + d6 + A.LINE * y);
    for (1..8) |n| {
        const d2: u5 = @intCast(2 * n);
        for (0..A.SCROLL_LINES) |y| {
            const a1: u32 = d4 + @as(u32, @intCast(A.LINE * y));
            var v: u32 = 0;
            for ([_]u32{ 0, 2 }) |p| {
                const nxt: u32 = A.be16(A.font, a1 +% d5 +% p);
                const cur: u32 = A.be16(A.font, a1 + d6 + p);
                const w: u16 = @truncate((cur << d2) | (nxt >> (16 - d2)));
                v = (v << 16) | w;
            }
            m.cols[n][y] = v;
        }
    }
}
