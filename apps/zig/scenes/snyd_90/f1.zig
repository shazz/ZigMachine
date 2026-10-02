// --------------------------------------------------------------------------
// F1 -- OMEGA: "the ball bending scroller" (part 1: track 15 side 0,
// ByteKiller-packed, to $1000; TFE of OMEGA). A 200-pixel shaded ball on
// planes 0..2 of one screen ($78000, from $2CCA4) and the scroll text bent
// round it on plane 3 (colours 8..15 are the ball's shades in pink). Its
// set-up builds, for each of the 200 lines, a path of 314 (word, bit) steps
// across the ball ($1D6D4, $4E8 bytes a line, from the x table at $2CC24):
// that ran once on the original code (the Musashi oracle) and its memory is
// this part's asset. Every VBL from there, $1234:
//   paint  each line keeps two lists of up to 10 points ($138C: erase points,
//          then +$14 draw points; counts at $35EC): every point clears or sets
//          its pixel and steps 4 bytes back along the path; one that reaches 0
//          leaves its list (the handler at $390C + 4n moves the next n words
//          down -- one more than the live entries, as the original does).
//   feed   every $140 VBLs the next letter ($39F0, '@' = space): $5B24 +
//          (c - '@') * $E10, 9 words a line; each line counts its word down
//          ($345C), then starts a new point at the far end of the path ($4E4),
//          erase and draw by turns ($32CC): a letter's runs become trails.
// The VBL ($10EE) only plays the tune and counts. Space -> menu (the VBL's
// $39 sets $10EA; the loop then returns to the loader).
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");

pub const BASE: u32 = 0x1000;
pub const TOP: u32 = 0x80000;
pub const SCREEN: u32 = 0x78000;
/// The colour registers its set-up loads from $2CC28 -- which the path table
/// then overwrites, so they are kept here (the disk's words, STE bits and all;
/// the shifter reads three bits a channel).
pub const PALETTE = [16]u16{ 0xF888, 0x0003, 0x0014, 0xF8AD, 0xF8BE, 0xF9CF, 0xFADF, 0xFBEF, 0x0500, 0x0613, 0x0714, 0x0724, 0x0735, 0x0746, 0x0757, 0x0767 };

const PATHS: u32 = 0x1D6D4;
const COUNTS: u32 = 0x35EC; // erase count, draw count, a line
const LISTS: u32 = 0x138C; // 10 erase words, 10 draw words, a line
const PLANE3: u32 = SCREEN + 6;
const STEP: u32 = 0x39EE;
const TEXT: u32 = 0x39F0;
const TEXT_START: u32 = 0x39F8;
const TEXT_END: u32 = 0x3B1D;
const GLYPH: u32 = 0x39F4;
const TURNS: u32 = 0x32CC; // a word a line: the letter's run index (bit 1: draw)
const DELAYS: u32 = 0x345C;
const FAR_END: u16 = 0x4E4;

pub fn frame(r: *const st.Ram) void {
    var path = PATHS;
    var counts = COUNTS;
    var list = LISTS;
    for (0..200) |_| {
        walk(r, path, counts, list, false);
        walk(r, path, counts + 2, list + 0x14, true);
        path += 0x4E8;
        counts += 4;
        list += 40;
    }
    feed(r);
}

fn walk(r: *const st.Ram, path: u32, count: u32, list: u32, draw: bool) void {
    var n = r.w(count);
    var a4 = list;
    while (n != 0) : (n -= 1) {
        const step = r.w(a4);
        const at = st.add(PLANE3, st.sx(r.w(st.add(path, st.sx(step)))));
        const bit = r.w(st.add(path, st.sx(step)) + 2);
        r.sw(at, if (draw) r.w(at) | bit else r.w(at) & ~bit);
        r.sw(a4, step -% 4);
        if (step -% 4 == 0) {
            r.sw(count, r.w(count) -% 1);
            for (0..n) |k| r.sw(a4 + 2 * @as(u32, @intCast(k)), r.w(a4 + 2 * @as(u32, @intCast(k)) + 2));
        } else {
            a4 += 2;
        }
    }
}

fn feed(r: *const st.Ram) void {
    r.sw(STEP, r.w(STEP) -% 1);
    if (r.w(STEP) == 0) nextLetter(r);
    var counts = COUNTS;
    var list = LISTS;
    var turn = TURNS;
    var delay = DELAYS;
    var glyph = r.l(GLYPH);
    for (0..200) |_| {
        if (start(r, delay)) {
            const t = r.w(turn);
            r.sw(turn, t +% 2);
            const draw = t & 2 != 0;
            const count = if (draw) counts + 2 else counts;
            const k = r.w(count);
            r.sw(count, k +% 1);
            r.sw(delay, r.w(st.add(glyph, st.sx(t))));
            r.sw(st.add(list + (if (draw) @as(u32, 0x14) else 0), 2 * @as(i32, k)), FAR_END);
        }
        counts += 4;
        list += 40;
        turn += 2;
        delay += 2;
        glyph += 0x12;
    }
}

/// $133E: a line's delay counts down; at 0 it starts a point.
fn start(r: *const st.Ram, delay: u32) bool {
    if (r.w(delay) == 0) return true;
    r.sw(delay, r.w(delay) - 1);
    return r.w(delay) == 0;
}

/// $12C8: the next letter; the run indexes and delays start over.
fn nextLetter(r: *const st.Ram) void {
    r.sw(STEP, 0x140);
    var p = r.l(TEXT);
    const c: u16 = r.b(p);
    r.sl(GLYPH, @as(u32, c -% 0x40) * 0xE10 + 0x5B24);
    p += 1;
    r.sl(TEXT, if (p == TEXT_END) TEXT_START else p);
    r.zero(TURNS, 800);
}
