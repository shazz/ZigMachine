// --------------------------------------------------------------------------
// F2 (OMEGA, "Liesen dist"): the distorted logo, $11E0. Self-modifying, as
// the original is: $1114 writes the displacement words of the 40 `movep.l`
// that draw a logo line ($149C..) and of the 40 that clear around it
// ($13B8..), one per 8-pixel column, from a wave of line numbers ($8274..,
// one word further every frame). Here those words are written where the
// 68000 wrote them and read back where it executed them.
//
// A line of the logo is 40 longs (one 8-pixel column of four plane bytes
// each) from one of 16 preshifted copies ($8738): the copy is the sum of two
// waves ($87EE forwards, $87F2 backwards) mod 16, the 16-pixel steps a
// source offset, and the line's own offset comes from a table ($87FE, 67
// words a frame of it) that a little script ($8778) runs up and down: rows
// 1/3 scroll it towards a target, 2 waits, 4/5 swap the two logos ($8802),
// 6 loads a palette, 7 sets the table.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");

pub const DRAW: u32 = 0x87FA; // the screen being drawn (the low word flips $8000)
const STATE: u32 = 0x87E0; // 0 read the script, 1 scroll down, 2 up, 3 wait
const SCRIPT: u32 = 0x87E2;
const SCRIPT_START: u32 = 0x8778;
const TARGET: u32 = 0x87DC;
const LINES: u32 = 0x87FE;
pub const ROWS: u32 = 0x1C64; // the scroller's row table offset, moved with LINES
const WAVE_A: u32 = 0x87EE;
const WAVE_B: u32 = 0x87F2;
const WAVE_Y: u32 = 0x87F6;
const LOGO: u32 = 0x8802; // 0 or $29400: which logo
const SHIFTS: u32 = 0x8738;
const PATCH_DRAW: u32 = 0x149C;
const PATCH_CLEAR: u32 = 0x13B8;

/// One VBL of the logo, after the music: everything but the scroller.
pub fn frame(r: *const st.Ram, pal: *[16]u16) void {
    patchWave(r);
    script(r, pal);
    advance(r);
    const a = r.l(WAVE_A) + 2;
    r.sl(WAVE_A, if (a == 0x80D8) 0x6968 else a);
    const b = r.l(WAVE_B) -% 2;
    r.sl(WAVE_B, if (b == 0x8196) 0x8204 else b);
    clear(r);
    draw(r);
}

/// $1114: the 40 columns' line numbers into both movep tables.
fn patchWave(r: *const st.Ram) void {
    var a1 = r.l(WAVE_Y) + 2;
    if (a1 == 0x86BE) a1 = 0x8274;
    r.sl(WAVE_Y, a1);
    for (0..40) |j| {
        const col: u16 = @intCast(8 * (j / 2) + j % 2); // bytes 0,1, 8,9, ...
        const d = r.w(a1 + 2 * @as(u32, @intCast(j))) *% 160 +% col;
        r.sw(drawPatch(j), d);
        r.sw(PATCH_CLEAR + 4 * @as(u32, @intCast(j)), d);
    }
}

/// The displacement word of the j-th draw movep: 8 to a movem.
fn drawPatch(j: usize) u32 {
    return PATCH_DRAW + 36 * @as(u32, @intCast(j / 8)) + 4 * @as(u32, @intCast(j % 8));
}

fn script(r: *const st.Ram, pal: *[16]u16) void {
    if (r.w(STATE) != 0) return;
    while (true) {
        var a0 = r.l(SCRIPT);
        const cmd: u16 = @truncate(r.l(a0));
        a0 += 4;
        switch (cmd) {
            0 => a0 = SCRIPT_START,
            1, 2, 3 => {
                r.sl(TARGET, r.l(a0));
                a0 += 4;
                r.sw(STATE, if (cmd == 1) 1 else if (cmd == 2) 3 else 2);
            },
            4, 5 => r.sl(LOGO, if (cmd == 4) 0 else 0x29400),
            6 => {
                const src = r.l(a0);
                a0 += 4;
                for (pal, 0..) |*c, i| c.* = r.w(src + 2 * @as(u32, @intCast(i)));
                r.sw(STATE, 0);
            },
            7 => {
                r.sl(LINES, r.l(a0));
                a0 += 4;
            },
            else => {},
        }
        r.sl(SCRIPT, a0);
        if (cmd != 0 and cmd != 4 and cmd != 5 and cmd != 6) return;
    }
}

/// $12BE: run the line table down (1) or up (2) to the target, or wait (3).
fn advance(r: *const st.Ram) void {
    if (r.w(STATE) == 1) {
        var a3 = r.l(LINES) + 0x86;
        var a4 = r.w(ROWS) +% 0x1A;
        if (a3 == 0xFD9A) {
            a3 = 0xAF16;
            a4 = 0;
        }
        if (a3 == r.l(TARGET)) r.sw(STATE, 0);
        r.sl(LINES, a3);
        r.sw(ROWS, a4);
    }
    if (r.w(STATE) == 2) {
        var a3 = r.l(LINES) - 0x86;
        var a4 = r.w(ROWS) -% 0x1A;
        if (a3 == 0xAE90) {
            a3 = 0xFD14;
            a4 = 0xF22;
        }
        if (a3 == r.l(TARGET)) r.sw(STATE, 0);
        r.sl(LINES, a3);
        r.sw(ROWS, a4);
    }
    if (r.w(STATE) == 3) {
        r.sl(TARGET, r.l(TARGET) -% 1);
        if (r.l(TARGET) == 0) r.sw(STATE, 0);
    }
}

/// movep.l: the long's four bytes to every other byte from `a`.
pub fn movep(r: *const st.Ram, a: u32, v: u32) void {
    inline for (.{ 0, 1, 2, 3 }) |k| r.sb(a +% 2 * k, @truncate(v >> (24 - 8 * k)));
}

/// $13A6: lines 0-1 and 64-65 of the logo's band, at this frame's waves.
fn clear(r: *const st.Ram) void {
    var a0 = r.l(DRAW);
    for (0..2) |_| {
        for (0..2) |_| {
            for (0..40) |j| movep(r, st.add(a0, st.sx(r.w(PATCH_CLEAR + 4 * @as(u32, @intCast(j))))), 0);
            a0 += st.LINE;
        }
        a0 += 0x26C0;
    }
}

/// $1466: 62 lines of 40 columns from the preshifted copy the waves pick.
fn draw(r: *const st.Ram) void {
    var a4 = r.l(DRAW) + 0x140;
    var a2 = r.l(WAVE_A);
    var a5 = r.l(WAVE_B);
    var a3 = r.l(LINES);
    for (0..62) |_| {
        const s = r.w(a2) +% r.w(a5);
        a2 += 2;
        a5 += 2;
        const src = r.l(SHIFTS + 4 * @as(u32, s & 15)) +% r.w(a3) +% r.l(LOGO) -% ((s & 0xFFF0) >> 1);
        a3 += 2;
        for (0..40) |j| movep(r, st.add(a4, st.sx(r.w(drawPatch(j)))), r.l(src + 4 * @as(u32, @intCast(j))));
        a4 += st.LINE;
    }
}
