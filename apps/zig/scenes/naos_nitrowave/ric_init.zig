// --------------------------------------------------------------------------
// F1's set-up after its figure choice ($A3E..$D98), transcribed: the figure's
// path, the Timer B table, the four screens $9B00 apart, and the precalculation
// ($C50) that runs the eight-sprite chain along the whole path and keeps the
// first sprite's planes for the VBL's third list. On the ST this runs under
// the title picture (594 to 748 VBLs, by figure); here it runs in one go at
// the title's end. prototypes/naos_nitrowave_re/ric_init.py is the same, =
// Hatari's RAM at the main loop for all four figures.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const spr = @import("ric_sprites.zig");
const font = @import("ric_font.zig");
const scroll = @import("ric_scroll.zig");

pub const SCREENS: u32 = 0x47942; // the four screens, then -1
pub const SCREEN_PTR: u32 = 0x4796A; // the next of them
pub const COUNTDOWN: u32 = 0x316A; // VBLs before the shifter follows them
pub const LOGO_PAL: u32 = 0x782AA; // colours 3, 5..13 from line 60 on (+6)
pub const PALETTE: u32 = 0x68C2; // the part's 16 colours
const STEP: u32 = 0x18; // one sprite step in a path: 4 entries
const CHAIN: u32 = 0x782E2; // eight path variables, a step apart

const Figure = struct { path: u32, gap: u32, countdown: ?u16 };
/// $A4A..$AAE: the figure the video counter picks.
const figures = [4]Figure{
    .{ .path = 0x5096, .gap = 0x2A0, .countdown = null },
    .{ .path = 0x5728, .gap = 0x270, .countdown = null },
    .{ .path = 0x5DBA, .gap = 0x210, .countdown = null },
    .{ .path = 0x6398, .gap = 0x300, .countdown = 0x8C },
};

pub fn run(r: *const st.Ram, figure: u2) void {
    paths(r, figures[figure]);
    tables(r);
    screens(r);
    precalc(r);
    finish(r);
}

fn paths(r: *const st.Ram, f: Figure) void {
    if (f.countdown) |n| r.sw(COUNTDOWN, n);
    r.sl(0x782CE, f.gap);
    r.sl(spr.PATH, f.path);
    r.sl(0x47928, f.path);
    r.sl(0x47924, f.path + STEP);
    r.sl(0x47920, f.path + STEP + f.gap);
    r.sl(spr.STREAM, spr.STREAM_FIRST);
    for (0..8) |k| r.sl(CHAIN + 4 * @as(u32, @intCast(k)), f.path + STEP * @as(u32, @intCast(k)));
}

/// $B1A..$BB0: the Timer B table, the rainbow tables' mirrored rows, the
/// logo palette, the sprite sheets.
fn tables(r: *const st.Ram) void {
    for (0..0xF2) |ii| {
        const i: u32 = @intCast(ii);
        r.cp(scroll.TABLE + 4 * i, 0x1B902 + 2 * i, 2);
        r.cp(scroll.TABLE + 2 + 4 * i, 0x3022 + 2 * i, 2);
    }
    r.sl(scroll.SCROLL_LIST, 0x31A0);
    for (0..8) |ki| {
        const a0 = 0x2D56 + 0x3C * @as(u32, @intCast(ki));
        for (0..15) |ji| {
            const j: u32 = @intCast(ji);
            r.cp(a0 + 0x3C - 2 - 2 * j, a0 + 2 * j, 2);
        }
    }
    r.cp(0x2D56 + 0x1E0, 0x2D56, 120);
    r.cp(LOGO_PAL, 0xCBD8 + 4, 32);
    r.sl(spr.GFX, 0x68C2 + 0x20);
    r.sl(spr.MASK, 0x9312 + 0x80);
}

/// $BB6..$C42: four screens from the first 256-byte boundary after $4796E;
/// the picture's lower part into the first, copied on into the next two.
fn screens(r: *const st.Ram) void {
    const s: u32 = (0x4796E & ~@as(u32, 0xFF)) + 0x100;
    r.sl(0x4793A, s);
    for (0..4) |k| r.sl(SCREENS + 4 * @as(u32, @intCast(k)), s + 0x9B00 * @as(u32, @intCast(k)));
    r.sl(SCREENS + 16, 0xFFFFFFFF);
    r.cp(s + 0x3840, 0xCBD8 + 0x80, 0xBB8 * 4);
    r.cp(s + 0x9B00, s, 32000);
    r.cp(s + 2 * 0x9B00, s + 0x9B00, 32000);
    r.sl(0x9312, s + 2 * 0x9B00);
    r.sl(0x9316, s + 3 * 0x9B00);
    r.sl(spr.WORK, 0x64B6E);
}

/// $C50: screen 2 into the work screen, the chain of eight drawn, and the
/// first sprite's planes 1..3 kept at *$782DA -- until its path ends.
fn precalc(r: *const st.Ram) void {
    while (true) {
        const work = r.l(spr.WORK);
        r.cp(work, r.l(SCREENS + 4), 0x23F0 * 4);
        for (0..8) |ki| {
            const v = CHAIN + 4 * @as(u32, @intCast(ki));
            r.sl(0x782DE, r.l(v));
            spr.draw(r, 0x782DE, .all);
            if (ki != 0) r.sl(v, r.l(0x782DE));
        }
        const a2 = r.l(CHAIN);
        r.sl(CHAIN, a2 + 6);
        keep(r, spr.add(work, spr.ws(r, a2)));
        if (r.w(r.l(CHAIN)) == 0xFFFF) return;
    }
}

fn keep(r: *const st.Ram, src: u32) void {
    var a1 = r.l(spr.STREAM);
    r.sl(spr.STREAM, a1 + 0x21C);
    var a0 = src;
    for (0..30) |_| {
        for (0..3) |gi| {
            const g: u32 = @intCast(gi);
            r.cp(a1 + 6 * g, a0 + 8 * g + 2, 6);
        }
        a1 += 0x12;
        a0 += 160;
    }
}

/// $CB6..$D82: the stream's end mark, the background from screen 0, each
/// screen's scroller place.
fn finish(r: *const st.Ram) void {
    r.sl(r.l(spr.STREAM), spr.STREAM_END);
    r.sl(spr.STREAM, spr.STREAM_FIRST + 0x870);
    r.sl(spr.WORK, r.l(spr.BG));
    r.cp(r.l(0x9316), r.l(0x9312), 0x2440 * 4);
    r.sl(SCREEN_PTR, SCREENS);
    r.cp(r.l(spr.BG), r.l(SCREENS), 32000);
    for (font.FONTS, 0..) |f, ki| {
        const k: u32 = @intCast(ki);
        r.sl(0x78274 + 8 * k, f);
        r.sl(0x78278 + 8 * k, 0x449A);
    }
    r.sl(0x78270, 0x316C);
    r.sw(0x7826E, 0);
}
