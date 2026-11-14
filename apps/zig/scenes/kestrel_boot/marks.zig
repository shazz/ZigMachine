// --------------------------------------------------------------------------
// KESTREL BOOT: plane 1's colours. Everything on this plane appears, glints and fades
// by PALETTE, never by redrawing pixels:
//   - the bird's eight colours (bird.zig indices 1..8);
//   - the highlight that runs down the bird at the arrival: a COPPER list (four entries
//     changed per line, zg.copper; a real raster, the colour registers per scanline);
//   - the wordmark: each letter its own entry, transparent until it lights, then rising
//     from the sky's colour to cream in LETTER_FRAMES (zero pixel writes);
//   - the fade, with the TC fade's own integer rule, so both planes reach black together.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const tl = @import("timeline.zig");
const bird = @import("bird.zig");
const sky = @import("sky.zig");
const word = @import("word.zig");

const Rgb = sky.Rgb;

/// The bird's colours: a kestrel's rufous back, slate head and tail, black tips, a cream rim.
const BIRD = [9]Rgb{
    .{ .r = 0, .g = 0, .b = 0 }, // 0: transparent
    .{ .r = 226, .g = 120, .b = 64 }, // rufous, lit
    .{ .r = 184, .g = 84, .b = 44 }, // rufous
    .{ .r = 132, .g = 56, .b = 34 }, // rufous, shaded
    .{ .r = 118, .g = 136, .b = 170 }, // slate
    .{ .r = 72, .g = 84, .b = 116 }, // slate, shaded
    .{ .r = 26, .g = 22, .b = 30 }, // wing tips, tail band, beak
    .{ .r = 244, .g = 226, .b = 190 }, // cream rim
    .{ .r = 70, .g = 34, .b = 24 }, // back spots
};
const CREAM = Rgb{ .r = 250, .g = 238, .b = 214 };
const SUB_INK = Rgb{ .r = 214, .g = 196, .b = 176 };
const SUB_FRAMES: u32 = 20;

/// The copper's four entries: the bird's lighter colours, where a highlight shows.
pub const GLINT = [4]u8{ bird.RUFOUS_LIGHT, bird.RUFOUS, bird.SLATE, bird.RIM };
const PLAIN = [4]u8{ bird.RUFOUS_DARK, bird.SLATE_DARK, bird.TIPS, bird.SPOT };
const VISIBLE_TOP: usize = 40; // physical row of visible line 0

var tables: [GLINT.len]zg.copper.Table = undefined;

pub const Marks = struct {
    behind: Rgb, // the sky behind the wordmark: where its letters fade in from
    glint_row: i32 = -1000, // the highlight's centre line last built (visible lines)
    coef: u8 = 255, // the fade last built (255: never)

    pub fn init(fb: *zg.LogicalFB) Marks {
        for (0..256) |i| fb.palette[i] = 0; // alpha 0: transparent until a colour is set
        for (GLINT) |e| fb.palette[e] = rgba(BIRD[e], 31);
        zg.copper.install(fb, &GLINT, &tables, .{});
        return .{ .behind = sky.colourAt(sky.W / 2, VISIBLE_TOP + word.Y + word.CELL_H * 3) };
    }

    /// Plane 1's colours at frame `f`.
    pub fn frame(m: *Marks, fb: *zg.LogicalFB, f: u32) void {
        const c = tl.fade(f);
        for (PLAIN) |e| put(fb, e, rgba(BIRD[e], c));
        for (0..word.LETTERS) |i| put(fb, word.FIRST + @as(u8, @intCast(i)), m.letter(i, f, c));
        put(fb, word.SUB_INK, m.rise(SUB_INK, f, tl.SUB, SUB_FRAMES, c));
        const g = glintRow(f);
        if (g == m.glint_row and c == m.coef) return;
        m.glint_row = g;
        m.coef = c;
        for (GLINT, 0..) |e, s| buildTable(zg.copper.visible(fb, @intCast(s)), BIRD[e], g, c);
    }

    fn letter(m: *const Marks, i: usize, f: u32, c: u5) u32 {
        return m.rise(CREAM, f, tl.WORD + @as(u32, @intCast(i)) * tl.LETTER_STEP, tl.LETTER_FRAMES, c);
    }

    /// `ink` rising from the sky's colour from frame `at` over `n` frames; transparent before.
    fn rise(m: *const Marks, ink: Rgb, f: u32, at: u32, n: u32, c: u5) u32 {
        if (f < at) return 0;
        const t = @min(f - at + 1, n);
        const r = Rgb{ .r = mix(m.behind.r, ink.r, t, n), .g = mix(m.behind.g, ink.g, t, n), .b = mix(m.behind.b, ink.b, t, n) };
        return rgba(r, c);
    }
};

fn mix(a: u8, b: u8, t: u32, n: u32) u8 {
    return @intCast((@as(u32, a) * (n - t) + @as(u32, b) * t) / n);
}

fn put(fb: *zg.LogicalFB, e: u8, v: u32) void {
    if (fb.palette[e] != v) fb.palette[e] = v;
}

/// RGBA as the palette holds it, faded by coefficient `c` (TC_FADE's rule), opaque.
fn rgba(x: Rgb, c: u5) u32 {
    const col = zg.Color{ .r = tl.fadeChannel(x.r, c), .g = tl.fadeChannel(x.g, c), .b = tl.fadeChannel(x.b, c), .a = 255 };
    return col.toRGBA();
}

/// The highlight's centre line at frame `f` (visible lines), or far away when there is none.
fn glintRow(f: u32) i32 {
    if (f < tl.ARRIVE or f >= tl.ARRIVE + tl.GLINT_FRAMES) return -1000;
    return 12 + @as(i32, @intCast((f - tl.ARRIVE) * 108 / tl.GLINT_FRAMES));
}

/// One copper table: `base` on every visible line, lightened toward white near line `g`.
fn buildTable(t: *[200]u32, base: Rgb, g: i32, c: u5) void {
    for (t, 0..) |*v, row| {
        const d: i32 = @intCast(@abs(@as(i32, @intCast(row)) - g));
        const a: u32 = @intCast(@max(0, 10 - d) * 22); // 0..220 of 256
        const lit = Rgb{ .r = toward(base.r, a), .g = toward(base.g, a), .b = toward(base.b, a) };
        const w = rgba(lit, c);
        if (v.* != w) v.* = w;
    }
}

fn toward(x: u8, a: u32) u8 {
    return @intCast(@as(u32, x) + ((255 - @as(u32, x)) * a >> 8));
}
