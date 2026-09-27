// --------------------------------------------------------------------------
// STOS's text window 0: 40 x 25 cells of 8 x 8 on the logical screen, in the
// 8X8.CR0 font, PEN on PAPER (every cell is opaque), UNDER ON underlining.
// LOCATE / PRINT / CENTRE / CLW / SQUARE, with the cursor off (the game turns
// it off at once and keeps it off). PRINT wraps at column 40 and scrolls the
// window at line 25; numbers print as STR$ does, positive ones with a
// leading space.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");
const scr = @import("scr.zig");
const gfx = @import("gfx.zig");

pub const COLS: i32 = 40;
pub const ROWS: i32 = 25;

pub var cx: i32 = 0;
pub var cy: i32 = 0;
pub var pen: u8 = 1;
pub var paper: u8 = 0;
pub var under: bool = false;

pub fn reset() void {
    cx = 0;
    cy = 0;
    pen = 1;
    paper = 0;
    under = false;
}

pub fn locate(x: i32, y: i32) void {
    cx = @max(0, @min(COLS - 1, x));
    cy = @max(0, @min(ROWS - 1, y));
}

/// The graphic y of text line `row` (YGRAPHIC).
pub fn ygraphic(row: i32) i32 {
    return row * 8;
}

fn glyph(c: u8) []const u8 {
    const i: usize = if (c < 32) 0 else c - 32;
    return assets.FONT[i * 8 ..][0..8];
}

fn cellOn(b: []u8, c: u8, col: i32, row: i32) void {
    const g = glyph(c);
    for (0..8) |j| {
        var bits = g[j];
        if (under and j == 7) bits = 0xFF;
        const o: usize = @intCast((row * 8 + @as(i32, @intCast(j))) * 320 + col * 8);
        for (0..8) |i| b[o + i] = if (bits >> @intCast(7 - i) & 1 != 0) pen else paper;
    }
}

pub fn putChar(c: u8) void {
    var tb: [2][]u8 = undefined;
    for (gfx.targets(&tb)) |b| cellOn(b, c, cx, cy);
    cx += 1;
    if (cx >= COLS) newline();
}

pub fn newline() void {
    cx = 0;
    cy += 1;
    if (cy >= ROWS) {
        scroll();
        cy = ROWS - 1;
    }
}

fn scroll() void {
    var tb: [2][]u8 = undefined;
    for (gfx.targets(&tb)) |b| {
        const line: usize = 320 * 8;
        const all: usize = line * @as(usize, @intCast(ROWS));
        @memmove(b[0 .. all - line], b[line..all]);
        @memset(b[all - line .. all], paper);
    }
}

/// PRINT s; (no newline). `print` adds the newline itself.
pub fn write(s: []const u8) void {
    for (s) |c| putChar(c);
}

pub fn print(s: []const u8) void {
    write(s);
    newline();
}

/// STR$(n): a leading space when n >= 0.
pub fn str(buf: []u8, n: i32) []const u8 {
    var tmp: [12]u8 = undefined;
    var v: u32 = @abs(n);
    var i: usize = tmp.len;
    while (true) {
        i -= 1;
        tmp[i] = @intCast('0' + v % 10);
        v /= 10;
        if (v == 0) break;
    }
    i -= 1;
    tmp[i] = if (n < 0) '-' else ' ';
    const out = tmp[i..];
    @memcpy(buf[0..out.len], out);
    return buf[0..out.len];
}

/// CENTRE s: s centred on the cursor's line.
pub fn centre(s: []const u8) void {
    const n: i32 = @intCast(s.len);
    cx = @max(0, @divTrunc(COLS - n, 2));
    write(s);
}

/// CLW: the window cleared to the paper colour, the cursor home.
pub fn clw() void {
    var tb: [2][]u8 = undefined;
    for (gfx.targets(&tb)) |b| @memset(b[0 .. 320 * 200], paper);
    cx = 0;
    cy = 0;
}

/// SQUARE w,h,border: a frame of w x h cells from the cursor, in the pen
/// colour, one pixel inside the outer cells (the border-1 style), its inside
/// cleared to paper. The cursor does not move.
pub fn square(w: i32, h: i32, border: i32) void {
    _ = border;
    const x0 = cx * 8;
    const y0 = cy * 8;
    const x1 = x0 + w * 8 - 1;
    const y1 = y0 + h * 8 - 1;
    const saved = gfx.ink;
    gfx.ink = paper;
    gfx.bar(x0, y0, x1, y1);
    gfx.ink = pen;
    gfx.box(x0 + 3, y0 + 3, x1 - 3, y1 - 3);
    gfx.ink = saved;
}
