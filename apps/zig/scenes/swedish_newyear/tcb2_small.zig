// --------------------------------------------------------------------------
// TCB #2's small scroller, $1058E: seven letters 12 pixels apart, a pixel a
// frame, text $113F4 ("... TRY THE FIRST FIVE FUNCTION KEYS! (ALL MUZAK BY
// MAD MAX) ..."), wrapped round a cylinder behind and in front of the big
// scroller. Each letter's height scale (0..24) and line come from two
// 128-byte waves ($1024E, $103CE) read 24 bytes apart and moving back one a
// frame: a scale above 12 is drawn BEHIND ($F1A0: only where the screen's
// plane 3 -- the big scroller -- is clear, planes 0-2), 12 or less in FRONT
// ($F396: all four planes, masked by the glyph's own plane 3). A scale is a
// block of $F54E: the number of rows, then each row's source offset, so a
// letter is squashed by skipping rows. $10652 clears the band the letters
// used two frames ago, above and below the big scroller.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const T = @import("tcb2.zig");

const Ram = st.Ram;

const WAVE_POS: u32 = 0x1063E; // .l 0..127, one back a frame
const CHAR: u32 = 0x10636; // .l the first letter's index in the text
const SUB: u32 = 0x1063A; // .l pixels 0..11 into it
const SMALL_TEXT: u32 = 0x113F4;
const TEXT_LEN: u32 = 0x11678; // .l
const CHAR_MAP: u32 = 0x1167C; // ASCII -> glyph
const SCALE_WAVE: u32 = 0x1024E;
const LINE_WAVE: u32 = 0x103CE;
const PRESHIFTS: u32 = 0x10642; // .l x 4: the glyph's pixel shift
const CLEAR_DELAY: u32 = 0x10712; // .w

/// $10652.
pub fn clear(r: *const Ram) void {
    const old = r.l(0x1070A);
    r.sl(0x1070A, r.l(0x10706));
    r.sl(0x10706, r.l(0x1070E));
    const n = r.w(CLEAR_DELAY) -% 1;
    r.sw(CLEAR_DELAY, n);
    if (n & 0x8000 == 0) return;
    r.sw(CLEAR_DELAY, 0);
    const now = r.l(0x1070E);
    var a1 = r.l(T.DRAWN) +% old +% 0x17C0;
    var d0: i32 = @bitCast(old -% now +% 0x8C0);
    while (true) {
        a1 -%= 0xA0;
        r.zero(a1, 0xA0);
        d0 -%= 0xA0;
        if (d0 <= 0) break;
    }
    d0 = @bitCast(now -% old +% 0xB40);
    a1 -%= 0xFA0;
    while (true) {
        a1 -%= 0xA0;
        r.zero(a1, 0xA0);
        d0 -%= 0xA0;
        if (d0 <= 0) break;
    }
}

/// $1058E.
pub fn step(r: *const Ram) void {
    const pos = (r.l(WAVE_POS) -% 1) & 0x7F;
    r.sl(WAVE_POS, pos);
    var ch = r.l(CHAR);
    var sub = r.l(SUB) + 1;
    if (sub >= 12) {
        sub = 0;
        ch += 1;
        if (@as(i32, @bitCast(ch)) >= @as(i32, @bitCast(r.l(TEXT_LEN)))) ch = 0;
    }
    r.sl(CHAR, ch);
    r.sl(SUB, sub);
    var scale_at = SCALE_WAVE + pos + 0xC - 2 * sub;
    var line_at = LINE_WAVE + pos + 0xC - 2 * sub;
    var x: u32 = 0 -% sub;
    for (0..7) |i| {
        const g = r.b(CHAR_MAP + r.b(SMALL_TEXT + ch + @as(u32, @intCast(i))));
        const y: u16 = @as(u8, 0x64) +% r.b(line_at + 0x20);
        letter(r, x, y, g, r.b(scale_at));
        x +%= 12;
        scale_at += 0x18;
        line_at += 0x18;
    }
}

/// $F1A0 / $F396: letter `g` at pixel x (negative: clipped at the left),
/// line y (its bottom), scale `s`.
fn letter(r: *const Ram, x: u32, y0: u16, g: u8, s: u8) void {
    var rows_at = T.SCALE + (@as(u32, s) << 7);
    const rows = r.l(rows_at);
    rows_at += 4;
    const y: u16 = (y0 -% @as(u16, @truncate(rows))) << 2;
    const count: u16 = @truncate(rows << 1);
    var src = T.GLYPHS +% r.l(PRESHIFTS + ((x & 3) << 2));
    var dst = r.l(st.add(T.LINE160, st.sx(y))) +% r.l(0x10702) -% 0x4880;
    const col = x >> 2;
    const glyph = r.l(st.add(T.GLYPH_OFFSET, st.sx(@as(u16, g) << 2)));
    var groups: u32 = 3;
    var skip: u32 = 0; // source groups clipped on the left
    switch (col) {
        0...0x11 => {},
        else => switch (@as(u16, @truncate(col))) {
            0x12 => groups = 2,
            0x13 => groups = 1,
            0xFFFF => skip = 1,
            0xFFFE => skip = 2,
            else => return,
        },
    }
    if (skip == 0) dst +%= col << 3 else groups -= skip;
    src +%= glyph + 8 * skip;
    const front = s <= 12;
    var n: u32 = @as(u32, count) + 1;
    while (n > 0) : (n -= 1) {
        const row = src +% r.l(rows_at);
        rows_at += 4;
        for (0..groups) |k| {
            const d = dst + 8 * @as(u32, @intCast(k));
            const sg = row + 8 * @as(u32, @intCast(k));
            if (front) inFront(r, d, sg) else behind(r, d, sg);
        }
        dst +%= 0xA0;
    }
}

/// $F396's group: all four planes through the glyph's own plane 3.
fn inFront(r: *const Ram, d: u32, s: u32) void {
    const m = ~r.w(s + 6);
    for (0..4) |p| {
        const a = d + 2 * @as(u32, @intCast(p));
        r.sw(a, (r.w(a) & m) | r.w(s + 2 * @as(u32, @intCast(p))));
    }
}

/// $F1A0's group: planes 0-2, only where the screen's plane 3 is clear.
fn behind(r: *const Ram, d: u32, s: u32) void {
    const m = ~r.w(d + 6);
    for (0..3) |p| {
        const a = d + 2 * @as(u32, @intCast(p));
        r.sw(a, r.w(a) | (r.w(s + 2 * @as(u32, @intCast(p))) & m));
    }
}
