// --------------------------------------------------------------------------
// TCB #2's yellow TCB logo, $B4BE: 112x25 from 16 preshifts ($52600, planes
// 0-2), drawn a BYTE column at a time. Two motions:
//   $AE5A  each of its 25 lines has its own x: a 30-long ring ($AEE2, with a
//          copy 30 longs on) of preshift deltas, fed one a frame from a script
//          of preshift numbers ($B1B0; a negative word jumps to the next of 64
//          segments, $B02E) -- a wave that travels down the logo;
//   $A89E  each of its 14 byte columns has its own y: a 128-word wave ($A90A)
//          read 8 apart, stepping 3 a frame, turned into screen deltas ($AB36).
// $A708 erases the old box, then draws the 25 lines bottom-up.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const T = @import("tcb2.zig");

const Ram = st.Ram;

const RING: u32 = 0xAEE2; // .l x 30, then a copy
const RING_POS: u32 = 0xB026; // .l byte offset into RING, 0..$74 stepping -4
const SCRIPT: u32 = 0xB1B0; // .w preshift numbers
const SCRIPT_POS: u32 = 0xB02A; // .w
const SEGMENT: u32 = 0xB02C; // .w 0..63
const SEGMENTS: u32 = 0xB02E; // .l x 64 -> into SCRIPT
const WAVE: u32 = 0xA90A; // .w x 128
const WAVE_POS: u32 = 0xA906; // .l
const COLUMNS: u32 = 0xAB36; // .l x 15: screen deltas, column to column

pub fn step(r: *const Ram) void {
    lineShifts(r);
    columnHeights(r);
    draw(r);
}

/// $AE5A.
fn lineShifts(r: *const Ram) void {
    var pos = r.l(RING_POS) -% 4;
    if (@as(i32, @bitCast(pos)) < 0) pos = 0x74;
    r.sl(RING_POS, pos);
    var n = r.w(SCRIPT_POS) +% 1;
    if (st.sx(r.w(SCRIPT + 2 * @as(u32, n))) < 0) {
        const seg = (r.w(SEGMENT) + 1) & 0x3F;
        r.sw(SEGMENT, seg);
        n = @truncate((r.l(SEGMENTS + 4 * @as(u32, seg)) -% SCRIPT) >> 1);
    }
    r.sw(SCRIPT_POS, n);
    const v = @as(u32, r.w(SCRIPT + 2 * @as(u32, n))) * 0x578 -% 0x38;
    const a = RING + pos;
    r.sl(a + 0x78, v);
    r.sl(a, v);
    r.sl(a + 4 + 0x78, r.l(a + 4 + 0x78) -% v -% 0x38);
    r.sl(a + 4, r.l(a + 4) -% v -% 0x38);
}

/// $A89E. The original reads the wave into a register whose top half is left
/// over (lsr.l can shift a stray bit into bit 15); the delta is shifted left
/// by 2 as a word, which drops bits 14-15, so the stray bit never shows.
fn columnHeights(r: *const Ram) void {
    var pos = r.l(WAVE_POS) + 3;
    if (pos >= 0x80) pos -= 0x80;
    r.sl(WAVE_POS, pos);
    var d0: u32 = pos << 1;
    var prev: u16 = 0;
    for (0..15) |k| {
        const h = r.w(WAVE + d0) >> 1;
        const delta: u16 = (h -% prev) +% 0xD;
        prev = h;
        r.sl(COLUMNS + 4 * @as(u32, @intCast(k)), r.l(st.add(T.LINE160, st.sx(delta << 2))) -% 0x81C);
        d0 = (d0 + 8) & 0xFF;
    }
    r.sl(COLUMNS, r.l(COLUMNS) -% 4);
}

/// $A708: erase 7 column pairs, 10 lines each, then 25 lines bottom-up.
fn draw(r: *const Ram) void {
    const base = r.l(T.DRAWN) + 0x1072;
    var a4 = base +% r.l(COLUMNS);
    for (0..7) |k| {
        for ([_]i32{ 0, 0xA0, -0xA0, -0x140, -0xF00, -0xFA0, -0x1040, -0x10E0 }) |off| r.zero(st.add(a4, off), 6);
        if (k < 6) a4 +%= r.l(COLUMNS + 4 + 8 * @as(u32, @intCast(k))) +% r.l(COLUMNS + 8 + 8 * @as(u32, @intCast(k)));
    }
    var src: u32 = T.LOGO_SHIFTS + 0x578;
    var ring = RING + r.l(RING_POS);
    var line = base -% 0xA0; // drawn from the line above the erase's base
    for (0..25) |_| {
        src +%= r.l(ring);
        ring += 4;
        var d = line;
        line -%= 0xA0;
        for (0..7) |g| {
            const s = src + 8 * @as(u32, @intCast(g));
            d +%= r.l(COLUMNS + 8 * @as(u32, @intCast(g)));
            for (0..3) |p| r.sb(d + 2 * @as(u32, @intCast(p)), r.b(s + 2 * @as(u32, @intCast(p))));
            d +%= r.l(COLUMNS + 4 + 8 * @as(u32, @intCast(g)));
            for (0..3) |p| r.sb(st.add(d, 2 * @as(i32, @intCast(p)) - 3), r.b(s + 1 + 2 * @as(u32, @intCast(p))));
        }
    }
}
