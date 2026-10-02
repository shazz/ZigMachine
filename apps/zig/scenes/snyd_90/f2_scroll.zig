// --------------------------------------------------------------------------
// F2 (OMEGA, "HAQ scroll"): the wave scroller, $1650. A 32x13 font
// preshifted by 4 pixels into 4 copies ($10CD6 + shift * $1EE0, two columns
// a letter) feeds four ring buffers of 14 rows x 320 bytes ($2098: one per
// shift); each VBL writes the newest 16-pixel column of the current shift's
// buffer (at col and col + 160), three planes only -- or all four after an
// odd number of spaces ($1C5A).
//
// Drawn 20 columns of 16 pixels at line 48, each column lowered by its own
// entry of a sine table of line offsets ($1C68.., 3 words apart, 4 words on
// a frame) -- the self-modifying `lea d(a3),a0` at $17DC.. -- and BEHIND the
// logo: only where all four planes of the screen are 0. Its rows come from
// the buffer through a row table ($FD9A + $1C64) that the logo's script moves
// with the logo's line table. Then the same columns are cleared on the OTHER
// screen (the one on display), with the offsets it was drawn at: two clear
// routines, one a screen, whose displacements are patched a frame ahead.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const logo = @import("f2_logo.zig");

const SHIFT: u32 = 0x2094; // 0, 4, 8, 12: which buffer, and the font's shift
const COL: u32 = 0x2096; // byte column in the ring buffers
const BUFFERS: u32 = 0x2098;
const CUR: u32 = 0x2088; // the letter entering, and the one before it
const PREV: u32 = 0x208C;
const TEXT: u32 = 0x2090;
const TEXT_START: u32 = 0x66A8;
const SPACE_GLYPH: u32 = 0x12AEA;
const FONT: u32 = 0x10CD6;
const FOUR_PLANES: u32 = 0x1C5A;
const SPACE_SEEN: u32 = 0x1C5C;
const CLEAR_SIDE: u32 = 0x1C5E;
const PHASE: u32 = 0x1C66;
const SINE: u32 = 0x1C68;
const ROW_TABLE: u32 = 0xFD9A;
const PATCH_DRAW: u32 = 0x17DC;
const CLEAR_A: u32 = 0x1A78;
const CLEAR_B: u32 = 0x1B22;
const TOP: u32 = 0x1E00; // line 48

pub fn frame(r: *const st.Ram) void {
    column(r);
    var d3 = r.w(SHIFT) + 4;
    if (d3 == 16) {
        d3 = 0;
        nextLetter(r);
    }
    r.sw(SHIFT, d3);
    r.sw(PHASE, r.w(PHASE) + 8);
    if (r.w(PHASE) == 0x210) r.sw(PHASE, 0);
    patch(r);
    draw(r);
    clear(r);
}

/// The newest column of the current shift's buffer.
fn column(r: *const st.Ram) void {
    const d3 = r.w(SHIFT);
    const d2: u16 = @truncate(@as(u32, d3) * 0x7B8);
    var a3 = st.add(r.l(CUR), st.sx(d2));
    var a2 = st.add(r.l(PREV), st.sx(d2)) -% 0x68;
    var a1 = st.add(r.l(BUFFERS + d3), st.sx(r.w(COL))) + 0x140;
    const four = r.w(FOUR_PLANES) != 0;
    for (0..13) |_| {
        for (0..4) |p| {
            const v: u16 = if (p == 3 and !four) 0 else r.w(a3) | r.w(a2);
            r.sw(a1, v);
            r.sw(a1 + st.LINE, v);
            a1 += 2;
            a3 += 2;
            a2 += 2;
        }
        a1 += 0x138;
    }
}

/// $1BCA: the next column of the ring, the next letter of the text.
fn nextLetter(r: *const st.Ram) void {
    r.sw(COL, (r.w(COL) + 8) % 0xA0);
    r.sl(PREV, r.l(CUR));
    if (r.w(SPACE_SEEN) != 0) {
        r.sw(SPACE_SEEN, ~r.w(SPACE_SEEN));
        r.sw(FOUR_PLANES, ~r.w(FOUR_PLANES));
    }
    var p = r.l(TEXT);
    r.sl(TEXT, p + 1);
    var c = r.b(p);
    if (c == ' ') {
        r.sl(CUR, SPACE_GLYPH);
        r.sw(SPACE_SEEN, ~r.w(SPACE_SEEN));
        return;
    }
    if (c == 0xFF) {
        p = TEXT_START;
        c = r.b(p);
        r.sl(TEXT, p + 1);
    }
    r.sl(CUR, FONT + @as(u32, c -% 'A') * 0xD0 + 0x68);
}

/// $16FC: each column's line offset into the draw code and into the clear
/// routine the next frame runs.
fn patch(r: *const st.Ram) void {
    var a5 = SINE + r.w(PHASE);
    r.sw(CLEAR_SIDE, ~r.w(CLEAR_SIDE));
    const side: u32 = if (r.w(CLEAR_SIDE) == 0) CLEAR_B else CLEAR_A;
    for (0..20) |c| {
        const d = r.w(a5) +% @as(u16, @intCast(8 * c));
        a5 += 6;
        r.sw(PATCH_DRAW + 0x5E * @as(u32, @intCast(c / 3)) + 0x1E * @as(u32, @intCast(c % 3)), d);
        r.sw(side + 8 * @as(u32, @intCast(c)), d);
        r.sw(side + 8 * @as(u32, @intCast(c)) + 4, d +% 4);
    }
}

fn draw(r: *const st.Ram) void {
    const src = st.add(r.l(BUFFERS + r.w(SHIFT)), st.sx(r.w(COL)));
    var a3 = r.l(logo.DRAW) + TOP;
    var a4 = st.add(ROW_TABLE, st.sx(r.w(logo.ROWS)));
    for (0..13) |_| {
        const off = st.sx(r.w(a4));
        a4 += 2;
        var a1 = st.add(st.add(src, off), off);
        for (0..20) |c| {
            const at = st.add(a3, st.sx(r.w(PATCH_DRAW + 0x5E * @as(u32, @intCast(c / 3)) + 0x1E * @as(u32, @intCast(c % 3)))));
            const m: u16 = ~(r.w(at) | r.w(at + 2) | r.w(at + 4) | r.w(at + 6));
            const ml = @as(u32, m) << 16 | m;
            r.sl(at, r.l(at) | (r.l(a1) & ml));
            r.sl(at + 4, r.l(at + 4) | (r.l(a1 + 4) & ml));
            a1 += 8;
        }
        a3 += st.LINE;
    }
}

/// $1A52: the scroller's columns on the screen on display.
fn clear(r: *const st.Ram) void {
    var a0 = (r.l(logo.DRAW) ^ 0x8000) + TOP;
    const side: u32 = if (r.w(CLEAR_SIDE) != 0) CLEAR_B else CLEAR_A;
    for (0..13) |_| {
        for (0..40) |i| r.sl(st.add(a0, st.sx(r.w(side + 4 * @as(u32, @intCast(i))))), 0);
        a0 += st.LINE;
    }
}
