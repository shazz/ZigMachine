// --------------------------------------------------------------------------
// SYNC #1's scroller, $213D4: NINE letters, each 32x22 in 4-pixel preshifts
// (sync1_init.zig), on lines 100..195 of the buffer about to be shown. Each
// letter has an x in 4-pixel units (0..80, entering at 80) and a height read
// from a wave table: all nine at one height (the text bounces) or stepped
// along the table (a wave). The text carries commands:
//   $FD  stop the letters for 900 frames      $FF  start the text over
//   '@'  the next wave setting ($2284A: which table, speed flags, the step)
// With the setting's "distort" flag each letter is drawn through a list of
// source lines (22 lists, $22888, cycled one a letter) that squash it; a list
// starting above line 0 also drops plane 2, which shades the letter.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const S = @import("sync1.zig");

const Ram = st.Ram;

const XS: u32 = 0x22BC6; // .w x of the nine letters
const CODES: u32 = 0x22BE8; // .w their characters ($FE: none)
const HEIGHTS: u32 = 0x23BD2; // .b their lines, this frame
const TEXT: u32 = 0x21682; // .l -> the next character
const TEXT_START: u32 = 0x22C02;
const SETTINGS: u32 = 0x2280A; // .l -> the current '@' setting
const SETTINGS_START: u32 = 0x2284A;
const WAVE: u32 = 0x23BCE; // .l -> the wave table, this frame
const WAVE_START: u32 = 0x2281A; // .l
const WAVE_END: u32 = 0x2281E; // .l
const WAVE_STEP: u32 = 0x22846; // .l between letters, when the wave is stepped
const STEPPED_ABOVE: u32 = 0x23CCB; // wave tables above this address are stepped
const DISTORT: u32 = 0x22824; // .b
const LISTS: u32 = 0x22880; // .l -> the distortion list, advanced every few frames
const LIST: u32 = 0x22884; // .l -> the list the next letter uses
const LISTS_START: u32 = 0x22888;
const PLAIN_LIST: u32 = 0x22934; // all 22 lines, no distortion
const LIST_DELAY: u32 = 0x2287C; // .w
const LIST_PERIOD: u32 = 0x2287E; // .w
const PAUSE: u32 = 0x22822; // .w frames the letters stay still
const SPEED: u32 = 0x22818; // .w
const FONT: u32 = 0x3C600; // the preshifts, $840 a letter
const FONT_OFFSET: u32 = 0x2185C; // .l letter * $840
const SHIFT_OFFSET: u32 = 0x227FC; // .w the four preshifts, 22 * 24 bytes apart
const COLUMN: u32 = 0x22BA2; // .b x >> 2 -> byte offset of the 16-pixel column

/// $213D4. Returns nothing: the flip it starts with is the one the NEXT frame shows.
pub fn scroller(r: *const Ram) void {
    flip(r);
    r.zero(r.l(S.BAND), 96 * st.LINE); // $21144
    var delay = r.w(LIST_DELAY) -% 1;
    r.sw(LIST_DELAY, delay);
    if (delay & 0x8000 != 0) {
        delay = r.w(LIST_PERIOD);
        r.sw(LIST_DELAY, delay);
        var p = r.l(LISTS) + 4;
        r.sl(LISTS, p);
        if (r.l(p) == 0xFFFF_FFFF) p = LISTS_START;
        r.sl(LISTS, p);
    }
    r.sl(LIST, r.l(LISTS));
    for (0..9) |i| {
        const k: u32 = @intCast(i);
        letter(r, r.w(XS + 2 * k), r.w(CODES + 2 * k), r.b(HEIGHTS + k));
    }
    for (0..71) |row| r.zero(r.l(S.BAND) + @as(u32, @intCast(row)) * st.LINE, 16); // $2121C
    advance(r);
    wave(r);
}

fn flip(r: *const Ram) void {
    const to_a = r.b(S.FLIP) == 1;
    r.sb(S.FLIP, if (to_a) 0 else 1);
    const scr = r.l(if (to_a) S.SCR_A else S.SCR_B);
    r.sl(S.DRAW, scr);
    r.sl(S.BAND, scr + 100 * st.LINE);
}

/// $20F94. `d5` is always 0 here (the caller's register, restored around
/// every call), so a list whose first line offset is above 0 drops plane 2.
fn letter(r: *const Ram, x: u16, ch: u16, y: u8) void {
    if (ch == 0xFE) return;
    const shift = x & 3;
    const src = FONT + r.l(FONT_OFFSET + 4 * @as(u32, ch)) + r.w(SHIFT_OFFSET + 2 * @as(u32, shift));
    var dst = r.l(S.BAND) + (r.w(S.LINE_TAB + 2 * @as(u32, y)) & 0xFFFE) + r.b(COLUMN + (x >> 2));
    var list: u32 = PLAIN_LIST;
    if (r.b(DISTORT) != 0) {
        var p = r.l(LIST) + 4;
        r.sl(LIST, p);
        list = r.l(p);
        if (list == 0xFFFF_FFFF) {
            p = LISTS_START;
            r.sl(LIST, p);
            list = r.l(p);
        }
    }
    dst = st.add(dst, st.sx(r.w(list)));
    list += 2;
    const shade = 0 < st.sx(r.w(list)); // cmp.w (a4),d5 / blt
    while (true) : (dst += st.LINE) {
        const line = r.w(list);
        list += 2;
        if (line == 0xFFFF) return;
        copyLine(r, dst, st.add(src, st.sx(line)), shift == 3, shade);
    }
}

/// One 32-pixel line (48 with the last preshift, whose third column is
/// written a byte a plane: the left half only).
fn copyLine(r: *const Ram, dst: u32, src: u32, wide: bool, shade: bool) void {
    if (!wide) {
        r.cp(dst, src, 16);
        if (shade) {
            r.sw(dst + 4, 0);
            r.sw(dst + 0xC, 0);
        }
        return;
    }
    if (shade) {
        r.cp(dst, src, 4);
        r.cp(dst + 6, src + 6, 6); // word 6, long 8
        r.cp(dst + 0xE, src + 0xE, 2);
        for ([_]u32{ 0x10, 0x12, 0x16 }) |k| r.sb(dst + k, r.b(src + k));
    } else {
        r.cp(dst, src, 16);
        for ([_]u32{ 0x10, 0x12, 0x14, 0x16 }) |k| r.sb(dst + k, r.b(src + k));
    }
}

/// $214D2: move the letters; one that reaches x = 0 takes the next character.
fn advance(r: *const Ram) void {
    for (0..9) |i| {
        const k: u32 = @intCast(i);
        var x = r.w(XS + 2 * k);
        if (x == 0) {
            feed(r, CODES + 2 * k);
            x = 0x50;
        } else if (r.w(PAUSE) != 0) {
            r.sw(PAUSE, r.w(PAUSE) - 1);
        } else {
            x -%= r.w(SPEED);
        }
        r.sw(XS + 2 * k, x & 0x7F);
    }
}

/// The character (or command) for the letter whose code word is at `code`.
fn feed(r: *const Ram, code: u32) void {
    var at = r.l(TEXT);
    switch (r.b(at)) {
        0xFD => r.sw(PAUSE, 0x384), // the letter keeps its old character
        0x40 => setting(r, code),
        else => |c| {
            var ch = c;
            if (c == 0xFF) {
                r.sl(SETTINGS, SETTINGS_START);
                r.sl(TEXT, TEXT_START);
                at = TEXT_START;
                ch = r.b(at);
            }
            r.sb(code + 1, ch);
        },
    }
    r.sl(TEXT, r.l(TEXT) + 1);
}

/// '@': the next of the four-byte settings (wave table, ?, distort, step).
fn setting(r: *const Ram, code: u32) void {
    var p = r.l(SETTINGS) + 4;
    if (r.b(p) & 0x80 != 0) p = SETTINGS_START;
    r.sl(SETTINGS, p);
    const table = 0x22826 + 8 * @as(u32, r.b(p));
    r.sl(0x22814, r.l(WAVE_START));
    r.sl(0x22810, r.l(WAVE_END));
    r.sl(LIST, LISTS_START);
    r.sl(WAVE_START, r.l(table));
    r.sl(WAVE_END, r.l(table + 4));
    r.sb(0x2280E, r.b(p + 1));
    r.sb(DISTORT, r.b(p + 2));
    r.sb(WAVE_STEP + 3, r.b(p + 3));
    r.sl(WAVE, r.l(WAVE_START));
    r.sb(code + 1, 0xFE);
}

/// $215FE: this frame's nine heights, then the wave moves two entries on.
fn wave(r: *const Ram) void {
    var a = r.l(WAVE);
    for (0..9) |i| {
        r.sb(HEIGHTS + @as(u32, @intCast(i)), r.b(a));
        if (a > STEPPED_ABOVE) a +%= r.l(WAVE_STEP);
    }
    const next = r.l(WAVE) + 2;
    const end = r.l(WAVE_END);
    r.sl(WAVE, if (@as(i32, @bitCast(next)) < @as(i32, @bitCast(end))) next else r.l(WAVE_START));
}
