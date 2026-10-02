// --------------------------------------------------------------------------
// F6's vector balls. Up to 73 points ($12F60: x, y, z longs, the integer in
// the LOW word, the fraction above it -- the morph adds 16.16 steps) are
// turned by three angles ($12F48, stepped by $C222.. each pass, $C228), the
// object moved ($CC84..) and pushed back ($C220), projected (x * $8C /
// (d - z) + 160, y the same + 100) and dropped into 128 depth buckets
// ($22F0E: pointers into $2470E, $100 bytes each) -- $CC8A, whose code the
// angles are patched into. $D03E then draws the buckets back to front, each
// at its own ball size ($D4D6), through the generated routines (one per
// size and preshift, $D0D6), and lists what it drew for $D016 to erase two
// passes later (the list $2370E, $300 bytes a screen).
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const blit = @import("f6_blit.zig");

pub const DRAW: u32 = 0x12AEE; // the screen drawn now
const POINTS: u32 = 0x12F60;
const END: u32 = 0xCC0A; // the points' end
const ANGLES: u32 = 0x12F48;
const SINE: u32 = 0x14672;
const COSINE: u32 = 0x14872;
const BUCKETS: u32 = 0x22F0E;
const BUCKET0: u32 = 0x2470E;
const LIST: u32 = 0x2370E;
const LIST_HALF: u32 = 0x15072;
const LINES: u32 = 0x43A96;

/// $D016: erase what this screen showed (the other half of the list).
pub fn erase(r: *const st.Ram) void {
    r.sw(LIST_HALF, r.w(LIST_HALF) ^ 0x300);
    var a = LIST + r.w(LIST_HALF);
    while (r.l(a) & 0x8000_0000 == 0) : (a += 8) blit.run(r, r.l(a + 4), r.l(a), 0);
}

/// $C228: the angles move, then $CC8A.
pub fn turn(r: *const st.Ram) void {
    for (0..3) |k| {
        const a = ANGLES + 2 * @as(u32, @intCast(k));
        r.sw(a, (r.w(a) +% r.w(0xC222 + 2 * @as(u32, @intCast(k)))) & 0x7FE);
    }
    r.sw(0x12F50, 0x8C);
    project(r);
}

const Trig = struct { s: i32, c: i32 };

fn trig(r: *const st.Ram, k: u32) Trig {
    const a = r.w(ANGLES + 2 * k);
    return .{ .s = st.sx(r.w(SINE + a)), .c = st.sx(r.w(COSINE + a)) };
}

/// The 68000's `add.l #$2000; swap; rol.l #2`: a 2.14 product back to a word.
fn round(v: i32) i32 {
    const w: u16 = @truncate(@as(u32, @bitCast(v +% 0x2000)) >> 14);
    return @as(i16, @bitCast(w));
}

/// Where $CC8A patches each angle into its own code (kept: the memory stays
/// the original's).
const PATCHES = [3][4]u32{
    .{ 0xCF2E, 0xCF34, 0xCF3C, 0xCF40 },
    .{ 0xCF5C, 0xCF64, 0xCF6A, 0xCF6E },
    .{ 0xCF8A, 0xCF90, 0xCF98, 0xCF9C },
};

fn project(r: *const st.Ram) void {
    for (PATCHES, 0..) |at, k| for (at) |a| r.sw(a, r.w(ANGLES + 2 * @as(u32, @intCast(k))));
    for (0..128) |k| r.sl(BUCKETS + 4 * @as(u32, @intCast(k)), BUCKET0 + 0x100 * @as(u32, @intCast(k)));
    r.sw(0x12F52, r.w(0x12F4E) +% r.w(0x12F50));
    const t = [3]Trig{ trig(r, 0), trig(r, 1), trig(r, 2) };
    var p = POINTS;
    while (p < r.l(END)) : (p += 12) point(r, p, t);
}

fn coord(r: *const st.Ram, p: u32, k: u32) i32 {
    return st.sx(r.w(p + 4 * k + 2) +% r.w(0xCC84 + 2 * k));
}

fn point(r: *const st.Ram, p: u32, t: [3]Trig) void {
    var x = coord(r, p, 0);
    var y = coord(r, p, 1);
    var z = coord(r, p, 2);
    const y1 = round(t[0].c *% y +% t[0].s *% z);
    z = round(t[0].c *% z -% t[0].s *% y);
    y = y1;
    const x1 = round(t[1].c *% x -% z *% t[1].s);
    z = round(t[1].c *% z +% t[1].s *% x);
    x = x1;
    const x2 = round(t[2].c *% x -% t[2].s *% y);
    y = round(t[2].c *% y +% t[2].s *% x);
    x = x2;
    z = word(z - st.sx(r.w(0xC220)));
    const sx = perspective(r, x, z) +% 0xA0;
    const sy = perspective(r, y, z) +% 0x64;
    var d = word(z + 0x100);
    d = @max(0, @min(d, 0x1FC)) & 0x1FC;
    const slot = BUCKETS + @as(u32, @intCast(d));
    const at = r.l(slot);
    r.sw(at, sx);
    r.sw(at + 2, sy);
    r.sl(slot, at + 4);
}

/// A word register's value (the 68000 wraps word arithmetic at 16 bits).
fn word(v: i32) i32 {
    return @as(i16, @truncate(v));
}

/// `muls $12F50,v; divs (d - z)`: a quotient that does not fit a word
/// leaves the product (the 68000 sets V and writes nothing), as does d = z.
fn perspective(r: *const st.Ram, v: i32, z: i32) u16 {
    const prod: i32 = st.sx(r.w(0x12F50)) * @as(i32, @as(i16, @truncate(v)));
    const den: i16 = @bitCast(r.w(0x12F52) -% @as(u16, @bitCast(@as(i16, @truncate(z)))));
    if (den == 0) return @truncate(@as(u32, @bitCast(prod)));
    const q = @divTrunc(prod, den);
    if (q > 32767 or q < -32768) return @truncate(@as(u32, @bitCast(prod)));
    return @truncate(@as(u32, @bitCast(q)));
}

/// $D03E: the buckets, back to front, each ball by its size's routine.
pub fn draw(r: *const st.Ram) void {
    var list = LIST + r.w(LIST_HALF);
    for (0..128) |k| {
        const kk: u32 = @intCast(k);
        const size: u32 = r.w(0xD4D6 + 2 * kk);
        var a = BUCKET0 + 0x100 * kk;
        while (a < r.l(BUCKETS + 4 * kk)) : (a += 4) {
            const x = r.w(a);
            const y = r.w(a + 2);
            const at = r.l(DRAW) +% r.l(st.add(LINES, st.sx(y *% 4))) +% ((x & 0xFF0) >> 1);
            const routines = st.add(0xD0D6 + (@as(u32, x & 15) << 3), st.sx(@truncate(size)));
            r.sl(list, at);
            r.sl(list + 4, r.l(routines));
            list += 8;
            blit.run(r, r.l(routines + 4), at, 0);
        }
    }
    r.sl(list, 0xFFFF_FFFF);
    // What $D03E leaves patched in its own code: the size read past the
    // table, the bucket pointer past the last.
    r.sw(0xD09E, r.w(0xD4D6 + 2 * 128));
    r.sl(0xD0B6, BUCKET0 + 0x100 * 128);
}
