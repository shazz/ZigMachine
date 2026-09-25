// --------------------------------------------------------------------------
// The curtain, $1928 draw + $1984 list (parts 2-4, 6-8, 10-12).
//
// The strip is colour 7 ($777) after $0452; this writes PLANE 0 only, from a
// 64-row table whose row r is clear for x in [80-r, 112+r) — a centred band
// 32+2r wide. Clearing plane 0 turns 7 into 6, the pink $755. The typer owns
// planes 1 and 2 over the same pixels, which is why the text's ink changes
// shade as the curtain moves under it.
//
// The list is computed AFTER the draw, so each frame draws the previous
// frame's list. And $6BDE4 is shared: on the first curtain frame of part 2 it
// still holds the wobble's rows (row * 32, up to $1FE0), and of part 10 the
// distorter's (row * 96). The draw reads 24 bytes at table + list[y] all the
// same, which walks off the 1536-byte table into the program's own bytes for
// one frame. That glitch is reproduced: curtain_tail.bin is those bytes as RAM
// holds them, and the counters living in them are patched in live.
// --------------------------------------------------------------------------
const std = @import("std");
const A = @import("assets.zig");
const st = @import("st.zig");

const ROW = A.CURTAIN_ROW_BYTES;
const GROUPS: usize = ROW / 2; // 12 x 16 px = the strip

// Where the live variables sit, as offsets from $1F42.
const VAR_F: usize = 0x2542 - 0x1F42; // the frame word
const VAR_C: usize = 0x2546 - 0x1F42; // the part counter, a long
const VAR_TYPED: usize = 0x254A - 0x1F42; // the typer's counter
const VARS_END: usize = VAR_TYPED + 2;

pub fn draw(scr: *[st.BYTES]u8, m: *const st.Machine) void {
    var scratch: [ROW]u8 = undefined;
    for (m.list, 0..) |off, y| {
        const src = row(off, m, &scratch);
        const dst = scr[y * st.LINE + st.STRIP ..];
        for (0..GROUPS) |g| dst[g * 8 ..][0..2].* = src[g * 2 ..][0..2].*;
    }
}

/// $1984: two walkers, the same seeds as the wobble but a different step.
pub fn rows(f: u16, list: *[st.LINES]u16) void {
    var a = A.seedU(f, 27);
    var b = A.seedS(f, -19);
    for (list) |*out| {
        const v: u32 = @intCast(A.sw(a) + A.sw(b) + 0x200); // 0..1024
        const r = (((v >> 2) * 63) >> 8) & 63;
        out.* = @intCast(r * ROW);
        a = A.step(a, 11);
        b = A.step(b, 29);
    }
}

/// The 24 bytes at $1F42 + off. Every list any effect writes stays inside
/// curtain_tail.bin (assets.zig checks the size against the largest).
fn row(off: u16, m: *const st.Machine, scratch: *[ROW]u8) *const [ROW]u8 {
    const at: usize = @min(off, A.curtain_tail.len - ROW);
    const src = A.curtain_tail[at..][0..ROW];
    if (at + ROW <= VAR_F or at >= VARS_END) return src;
    // A stale row that overlaps the counters: they hold this frame's values.
    var vars: [VARS_END - VAR_F]u8 = A.curtain_tail[VAR_F..VARS_END].*;
    std.mem.writeInt(u16, vars[0..2], m.f, .big);
    std.mem.writeInt(u32, vars[VAR_C - VAR_F ..][0..4], m.c, .big);
    std.mem.writeInt(u16, vars[VAR_TYPED - VAR_F ..][0..2], m.typed, .big);
    scratch.* = src.*;
    for (scratch, at..) |*b, a| {
        if (a >= VAR_F and a < VARS_END) b.* = vars[a - VAR_F];
    }
    return scratch;
}
