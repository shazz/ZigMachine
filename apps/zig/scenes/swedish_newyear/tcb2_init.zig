// --------------------------------------------------------------------------
// TCB #2's set-up, in the original's order: TCB #1's exit clear ($E0C2),
// then from the part's entry after TCB #1 returns ($10AC0): $1098E $10AA0
// $B440 [$11678] $109A4 $10942 $8006 $BFAA $9948 $8664, $113E6 = $78300. The
// precalculations are the demo's own -- the preshifts of the glyphs, the TCB
// logo and AN COOL, and the 128-frame raster table -- so the tables are built
// here exactly as the 68000 built them, and checked against the Musashi run of
// the original code (prototypes/snyd_re/tcb/m68run, which matches Hatari).
// --------------------------------------------------------------------------
const st = @import("st.zig");
const T = @import("tcb2.zig");
const vbl = @import("tcb2_vbl.zig");
const pre = @import("tcb2_preshift.zig");

const Ram = st.Ram;

/// The whole set-up. `r` holds the part as TCB #1 left it (or as loaded:
/// nothing TCB #2 reads survives TCB #1 except through $E0C2's clear).
pub fn init(r: *const Ram) void {
    r.zero(0x1908C, 0x41234 - 0x1908C); // $E0C2: TCB #1's samples
    r.zero(0x52600, 0x80000 - 0x52600); // $1098E
    r.cp(T.MUSIC, 0x1708C, 0x2000); // $10AA0: the Dugger replay (plays from its SNDH)
    pre.tcbLogo(r); // $B440
    r.sl(0x11678, 0x27A); // the small scroller's text length
    tables(r); // $109A4
    fillScreens(r); // $10942
    rasterBars(r); // $8006
    slots(r); // $BFAA
    pre.anCool(r); // $9948
    unionLogo(r); // $8664
    r.sl(T.DRAWN, 0x78300);
    vbl.install(); // $1081C
    T.resetKeyboard(); // module state: a second F2 must not inherit the last key
}

/// $109A4: the palettes (saved / the one shown during the precalc), the glyph
/// preshifts ($10752) and the line tables.
fn tables(r: *const Ram) void {
    // The registers as TCB #1 leaves them: its greys ($E1EA), colour 0 = $777 ($E0C2).
    for (0..16) |i| r.sw(0x10D46 + 2 * @as(u32, @intCast(i)), if (i == 0) 0x777 else r.w(0xE1EA + 2 * @as(u32, @intCast(i))));
    pre.glyphs(r);
    for (0..200) |i| {
        const k: u32 = @intCast(i);
        r.sl(T.LINE160 + 4 * k, 0xA0 * k);
        r.sl(0x11086 + 4 * k, 0x38 * k);
    }
    for (0..60) |i| r.sl(T.GLYPH_OFFSET + 4 * @as(u32, @intCast(i)), 0x960 * @as(u32, @intCast(i)));
    for (0..25) |b| { // the small scroller's row tables, x 24 (mulu.w #$18)
        const blk = T.SCALE + 4 + 128 * @as(u32, @intCast(b));
        for (0..31) |i| {
            const a = blk + 4 * @as(u32, @intCast(i));
            r.sl(a, (r.l(a) & 0xFFFF) * 0x18);
        }
    }
    r.sl(0x10702, 0);
    r.sl(0x10706, 0);
    r.sl(0x1070A, 0);
    r.sl(0x9796, 0x78300);
    r.sl(0x979A, 0x78300);
}

/// $10942: 4000 x 8 longs of the pattern at $10966 (zeros), from $80000 down:
/// the screens are black while the set-up runs (palette $113A6, colour 0 black).
fn fillScreens(r: *const Ram) void {
    var a: u32 = 0x78300 + 0x7D00;
    for (0..0xFA0) |_| {
        a -= 32;
        r.cp(a, 0x10966, 32);
    }
}

/// $8006: 128 frames x 90 words of colour 0 at $3654C. Six bars from the
/// y/z table $8464 (copied, a long each, to $8100), nearest last; words 36
/// and 87 marked for Timer B.
fn rasterBars(r: *const Ram) void {
    for (0..128) |_| {
        const frame = T.RASTERS + r.l(0x80FA);
        r.zero(frame, 0xB4);
        var d1: u16 = r.w(0x80FE) *% 4;
        r.sw(0x80FE, (r.w(0x80FE) + 1) & 0x7F);
        for (0..6) |i| {
            r.sl(BARS + 4 * @as(u32, @intCast(i)), r.l(0x8464 + @as(u32, d1)));
            d1 = (d1 + 0x38) & 0x1FF;
        }
        for (0..6) |_| bar(r, frame);
        r.sw(frame + 0x48, r.w(frame + 0x48) | 0x8000);
        r.sw(frame + 0xAE, r.w(frame + 0xAE) | 0x8000);
        r.sl(0x80FA, r.l(0x80FA) + 0xB4);
    }
}

const BARS: u32 = 0x8100; // six (y, z) words; a drawn bar's z becomes $7FFF

/// One bar: the farthest left (smallest z; the last of equals), then used.
fn bar(r: *const Ram, frame: u32) void {
    var y = r.w(BARS);
    var z = r.w(BARS + 2);
    var used: u32 = BARS;
    for (0..6) |i| {
        const e = BARS + 4 * @as(u32, @intCast(i));
        if (st.sx(r.w(e + 2)) > st.sx(z)) continue;
        z = r.w(e + 2);
        y = r.w(e);
        used = e;
    }
    r.sw(used + 2, 0x7FFF);
    var n: u16 = (z >> 7) -% 1;
    const grad = r.l(st.add(0x8140, st.sx(((n -% 8) >> 1) *% 4)));
    const at = frame + @as(u32, (y << 1) +% r.w(grad));
    if (n & 1 != 0) n -= 1;
    r.cp(at, grad + 2, 2 * (@as(usize, n) + 1));
}

/// $BFAA + $BF3A: the seven scroller slots, 24 bytes apart from line 155.
fn slots(r: *const Ram) void {
    r.sl(T.SLOT_X, 0x60E0);
    r.sl(T.LEFT_EDGE, 0x60E0 - 0x10);
    r.sl(T.RIGHT_EDGE, 0x60E0 + 0x98);
    for (0..7) |i| r.sl(T.SLOT_X + 4 * @as(u32, @intCast(i)), 0x60E0 + 8 + 0x18 * @as(u32, @intCast(i)));
    r.sl(0xC144, 0xFFFF); // d0 as $8006 left it
    for (0..7) |i| r.sl(T.SLOT_GLYPH + 4 * @as(u32, @intCast(i)), 0x35BEC);
    r.sl(T.YSCRIPT, 0xD682);
    r.sl(T.YLIST, 0xC374);
    r.sl(T.TEXT, T.TEXT_START);
    r.sl(0xC148, T.GLYPHS);
}

/// $8664: the UNION logo, plane 0 of lines 0..89 of both screens.
fn unionLogo(r: *const Ram) void {
    var src: u32 = 0x868A;
    for (0..90 * 20) |i| {
        const off = 8 * @as(u32, @intCast(i));
        r.sw(0x78300 + off, r.w(src));
        r.sw(0x70600 + off, r.w(src));
        src += 2;
    }
}
