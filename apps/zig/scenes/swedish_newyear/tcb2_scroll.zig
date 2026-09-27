// --------------------------------------------------------------------------
// TCB #2's big scroller, $C06A: seven slots of 48x25 glyphs (four 4-pixel
// preshifts at $1908C, $258 bytes each), 24 bytes apart. A phase ($C14C)
// walks the preshifts down by the speed each frame; below 0 every slot moves
// 16 pixels left and the one at the left edge takes the next letter and
// parks at the right edge, where the two end blocks ($D710) cover it. The
// whole row bounces: a list of line offsets ($C374..., -2 ends it) is
// subtracted from every slot, one a frame, and a script ($D682) picks the
// next list.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const T = @import("tcb2.zig");

const Ram = st.Ram;

pub const PHASE: u32 = 0xC14C; // .l offset into the glyph's preshifts, 0..$960
pub const SPEED: u32 = 0xC136; // .l subtracted from PHASE every frame
const GLYPH_TABLE: u32 = 0xC2AC; // text byte -> glyph offset
const EDGE_BLOCK: u32 = 0xD710; // 25 rows of 8 bytes
const LIST_END: u32 = 0xFFFF_FFFE;

/// $B99C, $BD7C, $BA88.
pub fn step(r: *const Ram) void {
    const right = r.l(T.RIGHT_EDGE);
    r.sl(0x10702, r.l(T.DRAWN) + right + 8); // for the small scroller's clear
    r.sl(0x1070E, right + 8);
    for (0..7) |k| {
        const x = r.l(T.SLOT_X + 4 * @as(u32, @intCast(k)));
        if (x == right) continue;
        glyph(r, r.l(T.SLOT_GLYPH + 4 * @as(u32, @intCast(k))) +% r.l(PHASE), x);
    }
    r.sl(PHASE, r.l(PHASE) -% r.l(SPEED));
    if (@as(i32, @bitCast(r.l(PHASE))) < 0) advance(r);
    edges(r);
    bounce(r);
}

/// $BC04: 25 lines of 24 bytes.
fn glyph(r: *const Ram, src: u32, x: u32) void {
    const dst = r.l(T.DRAWN) +% x;
    for (0..25) |line| r.cp(dst + 0xA0 * @as(u32, @intCast(line)), src + 24 * @as(u32, @intCast(line)), 24);
}

/// $BADA + $BB14: 16 pixels left; the slot at the left edge takes a letter.
fn advance(r: *const Ram) void {
    r.sl(PHASE, r.l(PHASE) +% 0x960);
    for (0..7) |k| {
        const a = T.SLOT_X + 4 * @as(u32, @intCast(k));
        r.sl(a, r.l(a) -% 8);
    }
    const left = r.l(T.LEFT_EDGE);
    for (0..7) |k| {
        const a = T.SLOT_X + 4 * @as(u32, @intCast(k));
        if (r.l(a) != left) continue;
        r.sl(T.SLOT_GLYPH + 4 * @as(u32, @intCast(k)), nextLetter(r));
        r.sl(a, r.l(T.RIGHT_EDGE));
        return;
    }
}

/// $BBD4.
fn nextLetter(r: *const Ram) u32 {
    if (r.b(r.l(T.TEXT)) == 0xFF) r.sl(T.TEXT, T.TEXT_START);
    const at = r.l(T.TEXT);
    r.sl(T.TEXT, at + 1);
    return T.GLYPHS +% r.l(GLYPH_TABLE + r.b(at));
}

/// $BD7C: the end blocks, at the right edge and 8 bytes right of it one
/// line up; the line above the first cleared.
fn edges(r: *const Ram) void {
    const a1 = r.l(T.DRAWN) +% r.l(T.RIGHT_EDGE);
    r.zero(a1 -% 0xA0, 8);
    for (0..25) |row| {
        const k: u32 = @intCast(row);
        r.cp(a1 +% 0xA0 * k, EDGE_BLOCK + 8 * k, 8);
        r.cp(a1 +% 0xA0 * k -% 0x98, EDGE_BLOCK + 8 * k, 8);
    }
}

/// $BA88: this frame's bounce step, the next list when one ends ($BCD2).
fn bounce(r: *const Ram) void {
    var list = r.l(T.YLIST);
    var d = r.l(list);
    while (d == LIST_END) {
        if (!nextList(r)) return;
        list = r.l(T.YLIST);
        d = r.l(list);
    }
    for (0..7) |k| {
        const a = T.SLOT_X + 4 * @as(u32, @intCast(k));
        r.sl(a, r.l(a) -% d);
    }
    r.sl(T.LEFT_EDGE, r.l(T.LEFT_EDGE) -% d);
    r.sl(T.RIGHT_EDGE, r.l(T.RIGHT_EDGE) -% d);
    r.sl(T.YLIST, list + 4);
}

const LISTS = [6]u32{ 0xC4CC, 0xC374, 0xC3F4, 0xC478, 0xC7F0, 0xC930 };

/// $BCD2: the script's next list ($FE: from the top). False on a byte the
/// original has no case for (it would spin forever; never in the script).
fn nextList(r: *const Ram) bool {
    while (true) {
        const at = r.l(T.YSCRIPT);
        const n = r.b(at);
        if (n == 0xFE) {
            r.sl(T.YSCRIPT, 0xD682);
            continue;
        }
        if (n >= LISTS.len) return false;
        r.sl(T.YLIST, LISTS[n]);
        r.sl(T.YSCRIPT, at + 1);
        return true;
    }
}
