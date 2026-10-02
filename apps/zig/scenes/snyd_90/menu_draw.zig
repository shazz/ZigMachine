// --------------------------------------------------------------------------
// The menu's drawing: the clear, the scroller and the sprites.
//
// The sprites. $10C2 compiles each of the 11 bitmaps listed at $386C (64 or
// 48 px wide, 62 rows, four planes; O M E G A / S Y N C / T C B, the C shared)
// into eight routines, one per 2-pixel shift, that skip transparent words,
// move opaque ones and and/or the rest -- a pixel whose four plane bits are
// all 0 is transparent. Their addresses fill a table of 8 longs per bitmap at
// $1402; a letter set ($1596, $15AC, $15BE) is a count and that many table
// pointers. Here the table entries hold (bitmap, shift) and blit() is the
// masked copy the routines perform: the same pixels, at the same addresses.
//
// The scroller ($15CC): a 16x13 four-plane font ($1A5A + (c - 'A') * $68,
// space $19F2), four ring buffers of 13 rows x 320 bytes ($38C4...), one per
// 4-pixel shift; each frame writes the newest 16-pixel column of the current
// shift's buffer twice (at col and col + 160), then copies 160 bytes a row
// to line 140. 4 pixels a frame, $FF restarts the text at $1718.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");

pub const DRAW: u32 = 0x3818; // the screen being drawn
pub const CLEAR: u32 = 0x381C; // two clear lists, swapped every frame
pub const COUNT: u32 = 0x158C;
pub const TABLES: u32 = 0x1592;
const RING_PTR: u32 = 0x2D92;
const RING: u32 = 0x2D96;
const RING_END: u32 = 0x2DFA;
const SPRITE_LIST: u32 = 0x386C;
const SPRITE_TABLES: u32 = 0x1402;
const ROWS = 62;
const NB = 11;

const Sprite = struct { src: u32, cols: u8 };
var sprite: [NB]Sprite = undefined;

pub fn indexSprites(r: *const st.Ram) void {
    for (&sprite, 0..) |*s, i| {
        const at = SPRITE_LIST + 8 * @as(u32, @intCast(i));
        s.* = .{ .src = r.l(at), .cols = if (r.l(at + 4) != 0) 3 else 4 };
        for (0..8) |sh| r.sl(SPRITE_TABLES + 32 * @as(u32, @intCast(i)) + 4 * @as(u32, @intCast(sh)), @intCast(i << 8 | sh));
    }
}

/// $2B38: 62 rows of 40 bytes at each address of the list.
pub fn clear(r: *const st.Ram, n: u16) void {
    const list = r.l(CLEAR);
    for (0..n) |k| {
        const a = r.l(list + 4 * @as(u32, @intCast(k)));
        for (0..ROWS) |row| r.zero(a +% @as(u32, @intCast(row)) * st.LINE, 40);
    }
}

pub fn scroller(r: *const st.Ram) void {
    const sh = (r.w(0x1702) -% 4) & 0xC;
    r.sw(0x1702, sh);
    if (sh == 0xC) nextLetter(r);
    const b = r.l(0x1706 + @as(u32, sh)) + r.w(0x1704);
    var cur = r.l(0x16F6);
    var prev = r.l(0x16FA);
    for (0..13) |row| {
        for (0..4) |p| {
            const v: u16 = @truncate((@as(u32, r.w(prev)) << 16 | r.w(cur)) >> @intCast(sh));
            const o = b + @as(u32, @intCast(row * 320 + 2 * p));
            r.sw(o, v);
            r.sw(o + 160, v);
            prev += 2;
            cur += 2;
        }
    }
    const dst = r.l(DRAW) + 140 * st.LINE;
    for (0..13) |row| r.cp(dst + @as(u32, @intCast(row)) * st.LINE, b + 8 + @as(u32, @intCast(row)) * 320, st.LINE);
}

fn nextLetter(r: *const st.Ram) void {
    r.sw(0x1704, (r.w(0x1704) + 8) % 0xA0);
    r.sl(0x16FA, r.l(0x16F6));
    var p = r.l(0x16FE);
    var c = r.b(p);
    r.sl(0x16FE, p + 1);
    if (c == 0xFF) {
        p = 0x1718;
        c = r.b(p);
        r.sl(0x16FE, p + 1);
    }
    const glyph: u32 = if (c == ' ') 0x19F2 else 0x1A5A + @as(u32, c -% 'A') * 0x68;
    r.sl(0x16F6, glyph);
}

/// Push the head (x, y) on the ring, then draw the set's letters from it.
pub fn sprites(r: *const st.Ram, x: u16, y: u16) void {
    var a6 = r.l(RING_PTR);
    const pos: u16 = y *% 160 +% (x & 0xFFF0) / 2;
    inline for (.{ 0, 0x64 }) |o| {
        r.sw(a6 + o, pos);
        r.sw(a6 + o + 2, (x & 0xE) * 2);
    }
    a6 += 4;
    if (a6 == RING_END) a6 = RING;
    r.sl(RING_PTR, a6);
    const list = r.l(CLEAR);
    const tables = r.l(TABLES);
    for (0..r.w(COUNT)) |k| {
        const kk: u32 = @intCast(k);
        const a5 = st.add(r.l(DRAW) +% r.w(a6), st.sx(r.w(0x29DC)));
        r.sl(list + 4 * kk, a5);
        const id = r.l(r.l(tables + 4 * kk) + r.w(a6 + 2));
        blit(r, a5, sprite[id >> 8], @intCast((id & 7) * 2));
        a6 += 24;
    }
}

fn blit(r: *const st.Ram, dst: u32, s: Sprite, sh: u5) void {
    for (0..ROWS) |row| {
        var prev = [4]u16{ 0, 0, 0, 0 };
        for (0..@as(usize, s.cols) + 1) |k| {
            var out: [4]u16 = undefined;
            var mask: u16 = 0;
            for (&out, &prev, 0..) |*o, *pv, p| {
                const w: u16 = if (k < s.cols) r.w(s.src + @as(u32, @intCast(((row * s.cols + k) * 4 + p) * 2))) else 0;
                o.* = @truncate((@as(u32, pv.*) << 16 | w) >> sh);
                pv.* = w;
                mask |= o.*;
            }
            const at = dst +% @as(u32, @intCast(row * st.LINE + k * 8));
            for (out, 0..) |o, p| {
                const q = at + 2 * @as(u32, @intCast(p));
                r.sw(q, (r.w(q) & ~mask) | o);
            }
        }
    }
}
