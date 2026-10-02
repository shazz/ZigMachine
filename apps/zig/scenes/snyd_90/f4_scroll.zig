// --------------------------------------------------------------------------
// F4's magenta scroller ($C416), below line 183 (where Timer B turns colours
// 4..11 magenta). The font's next column goes into one of four scroll
// buffers ($D9F6 + n * $594: 16 rows of $54 bytes, the column twice, $2A
// apart, so a window of 21 words reads straight), shifted by $C9BE (16, 12,
// 8, 4: four pixels a frame). Then the window goes onto the screen at line
// 184 through code the set-up generated ($C564 -> $124C8 / $14388: one
// `move.b d16(a0),d16(a1)` a byte, the bytes offset per column by the
// distortion tables $110C8 / $11AC8): 20 columns of it, an rts patched in
// at the end, entered at a column that steps with $C9BA (0..39), every
// other frame the second set. Replayed by f4_blit.zig.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const blit = @import("f4_blit.zig");

const FONT_COL: u32 = 0xC9C0;
const SHIFT: u32 = 0xC9BE;
const POS: u32 = 0xC9C4; // word: the column in the buffers
const BUF: u32 = 0xC9C6;
const PHASE: u32 = 0xC9BA;
const HALF: u32 = 0xC9D0;
const TEXT: u32 = 0xC9CA;

pub fn frame(r: *const st.Ram, screen: u32) void {
    column(r);
    show(r, screen);
    advance(r);
}

fn column(r: *const st.Ram) void {
    var src = r.l(FONT_COL);
    var a1 = st.add(r.l(BUF), st.sx(r.w(POS)));
    const s: u4 = @intCast(r.w(SHIFT) & 15);
    const shift = r.w(SHIFT);
    for (0..16) |_| {
        const v = r.w(src);
        src += 2;
        const hi: u16 = if (shift >= 16) 0 else v >> s;
        const lo: u16 = if (shift >= 16) v else if (s == 0) 0 else v << @intCast(16 - @as(u5, s));
        r.sw(a1, r.w(a1) | hi);
        r.sw(a1 + 0x2A, r.w(a1 + 0x2A) | hi);
        r.sw(a1 + 2, lo);
        r.sw(a1 + 0x2C, lo);
        a1 += 0x54;
    }
}

fn show(r: *const st.Ram, screen: u32) void {
    var phase = r.w(PHASE) + 1;
    if (phase >= 0x28) phase = 0;
    r.sw(PHASE, phase);
    var code: u32 = if (phase & 1 != 0) 0x14388 else 0x124C8;
    code += @as(u32, phase >> 1) * 192;
    const keep = r.w(code + 0xF00);
    r.sw(code + 0xF00, 0x4E75);
    var regs = blit.Regs{};
    regs.a0 = r.l(BUF) + 4 + r.w(POS) - phase;
    regs.a1 = screen + 0x7304 - @as(u32, phase & 0xFFFE) * 4;
    blit.run(r, code, &regs);
    r.sw(code + 0xF00, keep);
}

fn advance(r: *const st.Ram) void {
    r.sl(BUF, r.l(BUF) + 0x594);
    r.sw(SHIFT, r.w(SHIFT) -% 4);
    if (@as(i16, @bitCast(r.w(SHIFT))) > 0) return;
    r.sw(SHIFT, 0x10);
    r.sl(BUF, 0xD9F6);
    r.sw(POS, r.w(POS) + 2);
    if (r.w(POS) == 0x2A) r.sw(POS, 0);
    r.sw(HALF, ~r.w(HALF));
    if (r.w(HALF) != 0) return r.sl(FONT_COL, r.l(FONT_COL) + 0x20);
    r.sw(TEXT, r.w(TEXT) + 1);
    var c: u32 = r.b(0xC5D0 + @as(u32, r.w(TEXT)));
    if (c == 0xFF) r.sw(TEXT, 0);
    c = r.b(0xC8BA + c);
    r.sl(FONT_COL, (c << 6) + 0xCCF6);
}
