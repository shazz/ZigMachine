// --------------------------------------------------------------------------
// OMEGA's VBL work ($8286, after the palette): the replay ($8D0E, played here
// by beyond_the_ice_palace.sndh), then
//   * the six LED meters ($8290..$872C): plane 3 of the LED panel in the
//     opened bottom border, lines 201..207 / 209..215 / 217..223 for voices
//     A / B / C, one meter growing right from x 160 and its mirror growing
//     left from x 159. Each reads the voice's amplitude register straight
//     after the replay wrote it (level = register & 15, no decay, no peak):
//     level >> 1 whole 16-pixel groups, plus 8 pixels when the level is EVEN
//     (the 68000 tests the odd bit and skips on odd -- so 10 lights 5.5
//     groups and 11 lights 5). Level 0 lights nothing. Level 1 would run the
//     fill 65536 times over memory (a subq/bne from 0); this tune never plays
//     it (0 of 90,000 voice-frames), and here the fill stops at the meter's
//     eight groups.
//   * the drive LED ($872E): register 14 (port A) gets 5 (LED on) when the
//     noise period (register 6) is <= 4, else 7. The machine has no drive LED;
//     not reproduced.
//   * the ATARI logo ($87A0): the last position's 89 lines cleared, the frame
//     (0..31) and the bounce pointer advanced, the frame copied (all four
//     planes, 112x89) at x 112, line 19 + 30 + bounce (bounce 0..-30).
//   * the scroller ($8856): lines 172..187, planes 0-1, the whole width moved
//     4 pixels left, the new pixels from a 16x16 glyph buffer rolled through;
//     every 4th VBL the next character's glyph is copied into that buffer.
// The logo and the scroller are drawn in the frame they show (single screen,
// all of it done by display line ~127: measured in Hatari).
// --------------------------------------------------------------------------
const st = @import("st.zig");
const O = @import("omega.zig");
const LOGO_BYTES = @import("omega_init.zig").LOGO_BYTES;

const Ram = st.Ram;

// --- meters
const METER_LINES = 7;
const METER_GROUPS = 8;
/// Voice c's meters: the plane-3 word of the group each one starts at.
const RIGHT = [3]u32{ 0x77DF6, 0x782F6, 0x787F6 };
const LEFT = [3]u32{ 0x77DEE, 0x782EE, 0x787EE };

// --- logo
const LOGO_AT: u32 = 0x70C18; // line 19, x 112
const LOGO_FRAME: u32 = 0x817A; // .l 0..31
const BOUNCE_PTR: u32 = 0xC98E; // .l into the table below
const BOUNCE: u32 = 0xC992; // .w x 40: 0, -2 .. -30 .. -1
const BOUNCE_END: u32 = 0xC9E2;
const LOGO_LINES = 89;

// --- scroller
const SCROLL_END: u32 = 0x7757A; // line 187, the last group's plane-1 word
const GLYPH_END: u32 = 0x9CA8; // the glyph buffer $9C6A..$9CAA, walked bottom up
const GLYPH: u32 = 0x9C6A;
const COUNT: u32 = 0x9C64; // .w VBLs to the next character
const TEXT_PTR: u32 = 0x9C66; // .l
const TEXT: u32 = 0x9CAA;
const FONT: u32 = 0xB47C; // 64 bytes a glyph from '+', also the text's end
const SCROLL_LINES = 16;

/// $8286's work, `levels` = amplitude registers 8, 9, 10 as the replay left them.
pub fn vbl(r: *const Ram, levels: [3]u8) void {
    for (0..3) |c| meter(r, RIGHT[c], 8, levels[c] & 15, 0);
    for (0..3) |c| meter(r, LEFT[c], -8, levels[c] & 15, 1);
    logo(r);
    scroll(r);
    nextChar(r);
}

/// One meter: its 8 groups cleared, then the level lit. `half` is the byte of
/// the next group the 8-pixel step lights (+0 going right, +1 going left).
fn meter(r: *const Ram, at: u32, step: i32, level: u8, half: u32) void {
    for (0..METER_GROUPS) |g| column(r, group(at, step, g), 0);
    if (level == 0) return;
    const half_level: usize = level >> 1; // 0..7
    // level 1: the 68000's 65536 passes, bounded to the meter (see the header)
    const words = if (half_level == 0) METER_GROUPS else half_level;
    for (0..words) |g| column(r, group(at, step, g), 0xFFFF);
    if (level & 1 != 0) return;
    const a = group(at, step, words);
    for (0..METER_LINES) |y| r.sb(a + half + @as(u32, @intCast(y)) * st.LINE, 0xFF);
}

fn group(at: u32, step: i32, g: usize) u32 {
    return st.add(at, step * @as(i32, @intCast(g)));
}

fn column(r: *const Ram, a: u32, v: u16) void {
    for (0..METER_LINES) |y| r.sw(a + @as(u32, @intCast(y)) * st.LINE, v);
}

/// $8772: the logo's current frame and where it goes.
fn logoAt(r: *const Ram) struct { src: u32, dst: u32 } {
    const f = r.l(LOGO_FRAME);
    const y = r.w(r.l(BOUNCE_PTR)) +% 30; // addi.w: -30..0 -> 0..30
    return .{ .src = O.FRAMES + f *% 0x1378, .dst = LOGO_AT + @as(u32, y) * st.LINE };
}

fn logo(r: *const Ram) void {
    const old = logoAt(r).dst;
    for (0..LOGO_LINES) |y| r.zero(old + @as(u32, @intCast(y)) * st.LINE, LOGO_BYTES);
    var f = r.l(LOGO_FRAME) + 1;
    if (f == O.LOGO_FRAMES) f = 0;
    r.sl(LOGO_FRAME, f);
    var p = r.l(BOUNCE_PTR) + 2;
    if (p == BOUNCE_END) p = BOUNCE;
    r.sl(BOUNCE_PTR, p);
    const at = logoAt(r);
    for (0..LOGO_LINES) |y| {
        const k: u32 = @intCast(y);
        r.cp(at.dst + k * st.LINE, at.src + k * LOGO_BYTES, LOGO_BYTES);
    }
}

/// `w` rotated left 4 through `carry` (rol.l #4 / or.w / swap): the new word,
/// and the nibble shifted out becomes the carry.
fn roll(r: *const Ram, a: u32, carry: *u16) void {
    const v = @as(u32, r.w(a)) << 4;
    r.sw(a, @as(u16, @truncate(v)) | carry.*);
    carry.* = @truncate(v >> 16);
}

/// $8856: 16 lines bottom up, each shifted 4 pixels left, planes 1 and 0,
/// fed from the glyph buffer's matching row.
fn scroll(r: *const Ram) void {
    var a = SCROLL_END;
    var g = GLYPH_END;
    for (0..SCROLL_LINES) |_| {
        var c1: u16 = 0;
        var c0: u16 = 0;
        roll(r, g, &c1);
        roll(r, g - 2, &c0);
        g -= 4;
        for (0..20) |_| { // (a) and -8(a): plane 1; -2 and -10: plane 0
            roll(r, a, &c1);
            roll(r, a - 2, &c0);
            a -= 8;
        }
    }
}

/// $8B0A: every 4th VBL, the next printable character's glyph into the buffer.
fn nextChar(r: *const Ram) void {
    const n = r.w(COUNT) -% 1;
    r.sw(COUNT, n);
    if (n != 0) return;
    r.sw(COUNT, 4);
    while (true) {
        const ch = map(r.b(r.l(TEXT_PTR)));
        if (ch != '\r' and ch != '\n') {
            const off: u16 = (@as(u16, ch) -% 0x2B) << 6; // subi.w / lsl.w
            r.cp(GLYPH, FONT + off, 64);
        }
        advance(r);
        if (ch != '\r' and ch != '\n') return;
    }
}

fn advance(r: *const Ram) void {
    var p = r.l(TEXT_PTR) + 1;
    if (p == FONT) p = TEXT;
    r.sl(TEXT_PTR, p);
}

/// $8BA8: the characters the font keeps elsewhere.
fn map(c: u8) u8 {
    return switch (c) {
        '!' => 0x5B,
        '(' => '<',
        ')' => '>',
        '"' => 0x5C,
        '\'' => 0x5D,
        ' ' => '+',
        else => c,
    };
}
