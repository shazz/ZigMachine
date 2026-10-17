// --------------------------------------------------------------------------
// STCS STARGOOSE — the scroller strip copied onto plane 1 in each period's shape.
//
// Every shape moves a whole 16-pixel column group by whole lines (x / 16), so
// it is copied 16 bytes at a time (four word stores) instead of one byte store
// per pixel: on the board each store is a bus write, and the byte loop cost
// ~44,000 of them a frame.
//
// Byte-identical to the per-pixel loops it replaces: a plane address is one
// (line, x) pair, so only writes of the SAME x can meet, and for one x the
// writes still come in the old order (strip row y, then the period's writes in
// their old order) because each 16-byte copy is one (y, write) step of all of
// its 16 columns. Rows past line 199 are written as before (the fb pointer is
// unbounded, and the old u16 indices reached there too).
// --------------------------------------------------------------------------
const zg = @import("zigos");

const W: usize = zg.WIDTH;
const GROUP: usize = 16;
const GROUPS: usize = W / GROUP;

/// The plane line of strip row `y`'s write `k` for column group `g`.
const RowFn = fn (y: i32, k: usize, g: i32, arg: i32) i32;

fn copy(dst: [*]u8, src: []const u8, rows: usize, comptime writes: usize, comptime row: RowFn, arg: i32) void {
    for (0..rows) |y| {
        for (0..GROUPS) |g| {
            const from = src[y * W + g * GROUP ..][0..GROUP];
            inline for (0..writes) |k| {
                const line = row(@intCast(y), k, @intCast(g), arg);
                const at = @as(usize, @intCast(line)) * W + g * GROUP;
                @memcpy(dst[at..][0..GROUP], from);
            }
        }
    }
}

const H: i32 = 34; // SCROLL_CHAR_HEIGHT

fn threelines(y: i32, k: usize, _: i32, _: i32) i32 {
    // the old loop: +0, +78, +39 lines (and +78 again, the same bytes)
    return 84 + y + switch (k) {
        0 => 0,
        1 => 2 * H + 10,
        else => H + 5,
    };
}
fn bigFont(y: i32, k: usize, _: i32, yp: i32) i32 {
    return 78 + yp + 2 * y + @as(i32, @intCast(k));
}
fn interlacedMirror(y: i32, k: usize, g: i32, _: i32) i32 {
    return if (k == 0) 88 + y - g else 88 + (H + 5) + (2 * H - 2 * y) - g;
}
fn interlacedSteam(y: i32, k: usize, g: i32, _: i32) i32 {
    return if (k == 0) 164 + y else 76 + 2 * y + 2 * g;
}
fn inverted(y: i32, k: usize, g: i32, _: i32) i32 {
    return if (k == 0) 86 + y + g else 156 + (H - y) - g;
}
fn invertedMirror(y: i32, k: usize, g: i32, _: i32) i32 {
    const left = g < 10; // x < 160
    const h = if (left) g else g - 10;
    return switch (k) {
        0 => if (left) 90 + y - h else 80 + y + h,
        1 => if (left) 110 + (H - y) + h else 120 + (H - y) - h,
        else => 160 + y,
    };
}

pub const Period = enum { threelines, big_font, interlaced_mirror, interlaced_big_font, inverted, interlaced_steam, inverted_mirror };

/// Draw the strip `src` (WIDTH x 34) onto `dst` as `period` does; `yp` is the big fonts' bounce.
pub fn draw(dst: [*]u8, src: []const u8, period: Period, yp: i32) void {
    const rows: usize = @intCast(H);
    switch (period) {
        .threelines => copy(dst, src, rows, 3, threelines, 0),
        .big_font => copy(dst, src, rows, 2, bigFont, yp),
        .interlaced_big_font => copy(dst, src, rows, 1, bigFont, yp),
        .interlaced_mirror => copy(dst, src, rows, 2, interlacedMirror, 0),
        .interlaced_steam => copy(dst, src, rows, 2, interlacedSteam, 0),
        .inverted => copy(dst, src, rows, 2, inverted, 0),
        .inverted_mirror => copy(dst, src, rows, 3, invertedMirror, 0),
    }
}
