// --------------------------------------------------------------------------
// F6's text and logo. $D622 types a line of text a character a pass into
// both screens at line 140 (plane 2, the 8x8 font $15074 by $DEB8), a new
// line every 200 passes ($D722), ']' ends a line, 0 the whole text. $DF46
// copies the balls into the lower border, under the logo (generated code at
// $2C70E: f6_blit.zig). $DF58, from the VBL: sparkles on the SYNC logo (the
// logo kept at $156D4, two planes, 80 bytes a line, from line 179); seven
// of them at once, at the positions of $E4AA.., each a 16-pixel, 11-line
// sprite in 7 phases ($151F4 + $E31E[phase]), the last phase putting the
// logo back.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const blit = @import("f6_blit.zig");

pub const DRAW: u32 = 0x12AEE; // this pass's screen; $12AF2 the other
const OTHER: u32 = 0x12AF2;
const LINES: u32 = 0x43A96;
const LOGO: u32 = 0x156D4;

/// $DF46.
pub fn reflect(r: *const st.Ram) void {
    blit.run(r, 0x2C70E, r.l(DRAW) + 0x7D00, r.l(DRAW));
}

/// $D622.
pub fn text(r: *const st.Ram) void {
    const count = r.w(0xD722) -% 1;
    r.sw(0xD722, count);
    if (count & 0x8000 != 0) newLine(r);
    if (r.b(0xD720) == 0) return;
    const p = r.l(0xD72C);
    const c = r.b(p);
    if (c == 0) {
        r.sl(0xD72C, 0xD730);
        r.sb(0xD720, 0);
        return;
    }
    r.sl(0xD72C, p + 1);
    if (c == ']') return r.sb(0xD720, 0);
    const glyph = 0x15074 + (@as(u32, r.b(0xDEB8 + @as(u32, c -% 0x20))) << 3);
    for (0..8) |row| {
        const o: u32 = @intCast(row * st.LINE);
        r.sb(r.l(0xD724) + o, r.b(glyph + @as(u32, @intCast(row))));
        r.sb(r.l(0xD728) + o, r.b(glyph + @as(u32, @intCast(row))));
    }
    const step: u32 = r.b(0xD709); // the moveq's byte, 1 / 7 by turns
    r.sl(0xD724, r.l(0xD724) + step);
    r.sl(0xD728, r.l(0xD728) + step);
    r.sw(0xD708, r.w(0xD708) ^ 6);
}

/// Every 200 passes: the text's next line, at line 140 of both screens.
fn newLine(r: *const st.Ram) void {
    r.sw(0xD722, 0xC8);
    r.sl(0xD724, r.l(DRAW) + 0x5784);
    r.sl(0xD728, r.l(OTHER) + 0x5784);
    r.sb(0xD709, 1);
    r.sb(0xD720, 0xFF);
}

const Spot = struct { screen: u32, logo: u32, shift: u5 };

/// Where the sparkle at table entry `e` (x.w, y.w) lands on both screens
/// and in the kept logo ($DFAE..$DFF0).
fn spot(r: *const st.Ram, e: u32) Spot {
    const x = r.w(e);
    const y4: u32 = @as(u32, r.w(e + 2)) *% 4 & 0xFFFF;
    const line = r.l(st.add(LINES, st.sx(@truncate(y4)))) + 4;
    const logo_line: u32 = r.w(st.add(LINES, st.sx(@truncate(y4 -% 0x2CC))) + 2) >> 1;
    const col: u32 = (x & 0xFF0) >> 1;
    return .{ .screen = line + col, .logo = LOGO + logo_line + (col >> 1), .shift = @intCast(x & 15) };
}

/// $DF58.
pub fn sparkle(r: *const st.Ram) void {
    r.sw(0xE47A, 5);
    const phase = (r.w(0xE47C) + 2) & 15;
    r.sw(0xE47C, phase);
    if (phase == 0) {
        var p = r.l(0xE47E) + 4;
        if (p >= 0xE50E) p = 0xE4AA;
        r.sl(0xE47E, p);
    }
    const s = spot(r, r.l(0xE47E) - 2 * @as(u32, phase));
    if (phase == 14) return restore(r, s);
    var src = 0x151F4 + @as(u32, r.w(0xE31E + phase));
    for (0..11) |row| {
        const o: u32 = @intCast(row);
        const a = rot(r.w(src), s.shift);
        const b = rot(r.w(src + 2), s.shift);
        src += 4;
        put(r, s, o * 0x50, o * st.LINE, @truncate(a), @truncate(b));
        put(r, s, o * 0x50 + 4, o * st.LINE + 8, @truncate(a >> 16), @truncate(b >> 16));
    }
}

/// `ror.l` of a zero-extended word: the low word is this group's, the
/// high word what spills into the next.
fn rot(w: u16, s: u5) u32 {
    return @as(u32, w) >> s | (if (s == 0) 0 else @as(u32, w) << @intCast(32 - @as(u6, s)));
}

/// A logo long with the sprite's two words cut in (plane 2 gets `a`).
fn put(r: *const st.Ram, s: Spot, lo: u32, so: u32, a: u16, b: u16) void {
    const m = ~(a | b);
    const v = r.l(s.logo + lo);
    const hi: u16 = (@as(u16, @truncate(v >> 16)) & m) | a;
    const low: u16 = (@as(u16, @truncate(v)) & m) | b;
    const out = @as(u32, hi) << 16 | low;
    r.sl(r.l(DRAW) + s.screen + so, out);
    r.sl(r.l(OTHER) + s.screen + so, out);
}

/// $E32E: the logo back where the sparkle was.
fn restore(r: *const st.Ram, s: Spot) void {
    for (0..11) |row| {
        const o: u32 = @intCast(row);
        for ([2]u32{ 0, 4 }) |g| {
            const v = r.l(s.logo + o * 0x50 + g);
            r.sl(r.l(DRAW) + s.screen + o * st.LINE + 2 * g, v);
            r.sl(r.l(OTHER) + s.screen + o * st.LINE + 2 * g, v);
        }
    }
}
