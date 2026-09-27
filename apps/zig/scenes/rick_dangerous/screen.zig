// --------------------------------------------------------------------------
// The screen routines of the menus, GAME OVER and the level intro (the
// model's d_screen.py), each advancing the long calls' clock by the
// original's cycles. The fades are resumable (fade.zig); these are the
// pieces that run straight through.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const core = @import("core.zig");
const clock = @import("clock.zig");
const hud = @import("hud.zig");
const game = @import("game.zig");

const GREY: i64 = 0x3D8E8;

/// d_screen.wait's body ($38D92 + the clock + the input that arrived).
pub fn waitD() void {
    hud.wait();
    clock.waited();
    clock.poll();
}

/// d_screen.flip's body.
pub fn flipD() void {
    const c = m.rb(F.VBL_COUNT);
    const waits = c == 0 or c & 0x80 != 0;
    hud.flip();
    if (waits) {
        clock.waited();
        clock.poll();
    } else clock.work(60);
}

/// a_pass.wait_vbl's body (no input poll).
pub fn waitA() void {
    hud.wait();
    clock.waited();
}

/// a_pass.flip's body.
pub fn flipA() void {
    const c = m.rb(F.VBL_COUNT);
    const waits = c == 0 or c & 0x80 != 0;
    hud.flip();
    if (waits) clock.waited() else clock.work(60);
}

/// $3B25C: the screen at screen_ptr, then the other (32000 bytes each).
pub fn clearBoth() void {
    const sp = m.rl(F.SCREEN_PTR);
    m.zero(sp & 0xFFFFFF, 32000);
    m.zero((sp ^ 0x8000) & 0xFFFFFF, 32000);
    clock.work(clock.CLEAR_BOTH);
}

/// $3B280: clear both screens, all 4 HUD dirty, the 4 HUD redraws.
pub fn clearHud() void {
    clearBoth();
    for ([_]i64{ F.DIRTY_SCORE, F.DIRTY_BULLETS, F.DIRTY_DYNAMITE, F.DIRTY_LIVES }) |a| m.wb(a, 0xFF);
    hud.all();
    clock.work(clock.CLEAR_HUD_EXTRA);
}

fn length(a: i64) i64 {
    var n: i64 = 0;
    while (m.rb(a + n) != 0xFF) n += 1;
    return n;
}

/// $38EC8(d0 = column, d1 = text row): offset = y x 1280 + (x & ~1) x 4 + (x & 1).
pub fn printAt(x: i64, y: i64, text: i64) void {
    var d1 = (y << 8) & 0xFFFF;
    d1 = (d1 + ((d1 << 2) & 0xFFFF)) & 0xFFFF;
    if (x & 1 != 0) d1 = (d1 + 1) & 0xFFFF;
    clock.work(clock.PRINT_BASE + clock.PRINT_CHAR * length(text));
    core.printText(((((x & ~@as(i64, 1)) & 0xFFFF) << 2) + d1) & 0xFFFF, text);
}

/// $38F2E: the tiles at a0 to ONE screen address a1 (odd = right half); returns a1 after.
pub fn printOne(a1_: i64, a0_: i64) i64 {
    var a1 = a1_;
    var a0 = a0_;
    clock.work(clock.PRINT1_BASE + clock.PRINT1_CHAR * length(a0));
    while (true) {
        const t = m.rb(a0);
        a0 += 1;
        if (t == 0xFF) return a1;
        core.drawTile(a1, t);
        a1 = if (a1 & 1 != 0) (a1 ^ 1) + 8 else a1 | 1;
    }
}

/// $34670: 1280 longs from a0 to both screens' top (the first 16 lines).
pub fn banner(a0: i64) void {
    m.copy(0x78000, a0, 5120);
    m.copy(0x70000, a0, 5120);
    clock.work(clock.BANNER);
}

/// $3D9EC: the title picture $13A70 (32768 bytes) to the back screen.
pub fn titlePicture() void {
    m.copy(game.backScreen() & 0xFFFFFF, 0x13A70, 0x8000);
    clock.work(clock.TITLE_PICTURE);
}

/// $3D8EA's palette swap: the live palette = the grey one ($3D934) or the
/// normal one ($3D954) by $3D8E8, which flips.
pub fn swapPalette() void {
    const src: i64 = if (m.rw(GREY) != 0) 0x3D934 else 0x3D954;
    m.copy(F.LIVE_PAL, src, 32);
    m.ww(GREY, m.rw(GREY) ^ 0xFF);
    clock.work(400);
}

/// One fade-out step: every colour register's R, G, B -1 where not 0.
pub fn fadeOutStep(last: bool) void {
    var n: i64 = 0;
    for (&game.pal) |*p| {
        for ([3][2]i64{ .{ 0x700, 0x100 }, .{ 0x70, 0x10 }, .{ 0x7, 0x1 } }) |mo| {
            if (p.* & mo[0] != 0) {
                p.* = (p.* - mo[1]) & 0xFFFF;
                n += 1;
            }
        }
    }
    clock.work(clock.FADE_OUT_STEP + 12 * n + @as(i64, if (last) clock.FADE_OUT_END else 0));
}

/// One fade-in step d4 = 7..0: +1 where the live palette's gun is above the step's threshold.
pub fn fadeInStep(d4: i64) void {
    const d2 = 0x700 - 0x100 * (7 - d4);
    const d3 = 0x70 - 0x10 * (7 - d4);
    var n: i64 = 0;
    for (&game.pal, 0..) |*p, c| {
        const live = m.rw(F.LIVE_PAL + 2 * @as(i64, @intCast(c)));
        for ([3][3]i64{ .{ 0x700, d2, 0x100 }, .{ 0x70, d3, 0x10 }, .{ 0x7, d4, 0x1 } }) |mo| {
            if ((live & mo[0]) > mo[1]) {
                p.* = (p.* + mo[2]) & 0xFFFF;
                n += 1;
            }
        }
    }
    clock.work(clock.FADE_IN_STEP + 12 * n + @as(i64, if (d4 == 0) clock.FADE_IN_END else 0));
}
