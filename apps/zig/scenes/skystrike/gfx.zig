// --------------------------------------------------------------------------
// STOS's graphics on the logical screen: INK, GR WRITING, SET PAINT, BAR,
// BOX, DRAW, POINT. Corners are INCLUSIVE (the fuel gauge: box 128,193 to
// 229,197 is 102 pixels wide on the ST, bar 154..227 clears 74). With AUTO
// BACK on and logic = physic, everything also lands on the background screen
// (sprite.zig restores from it), as STOS duplicates it.
//
// SET PAINT 2,4 (the bonus bar) is VDI fill pattern 4: a checkerboard, set
// where x + y is even (measured on the ST screen: bar 16,4 to 304,10 in ink
// 13, gr writing 2, colours x=16 on line 8 and x=17 on line 9).
// --------------------------------------------------------------------------
const scr = @import("scr.zig");

pub var ink: u8 = 1;
/// 1 replace, 2 transparent, 3 xor, 4 reverse transparent.
pub var writing: u8 = 1;
pub var paint_style: i32 = 1;
pub var paint_index: i32 = 1;

pub fn reset() void {
    ink = 1;
    writing = 1;
    paint_style = 1;
    paint_index = 1;
}

/// The screens a drawing lands on: logic, and back under AUTO BACK.
pub fn targets(buf: *[2][]u8) []const []u8 {
    buf[0] = scr.get(scr.logic);
    if (scr.auto_back and scr.logic == .physic) {
        buf[1] = scr.get(.back);
        return buf[0..2];
    }
    return buf[0..1];
}

fn patternBit(x: i32, y: i32) bool {
    if (paint_style == 2 and paint_index == 4) return @mod(x + y, 2) == 0;
    return true;
}

fn plotOn(b: []u8, x: i32, y: i32, on: bool) void {
    const i: usize = @intCast(y * 320 + x);
    switch (writing) {
        1 => b[i] = if (on) ink else 0,
        2 => if (on) {
            b[i] = ink;
        },
        3 => if (on) {
            b[i] ^= ink;
        },
        else => if (!on) {
            b[i] = ink;
        },
    }
}

fn clip(v: i32, hi: i32) i32 {
    return @max(0, @min(hi, v));
}

pub fn bar(x1: i32, y1: i32, x2: i32, y2: i32) void {
    var tb: [2][]u8 = undefined;
    const xa = clip(@min(x1, x2), 319);
    const xb = clip(@max(x1, x2), 319);
    const ya = clip(@min(y1, y2), 199);
    const yb = clip(@max(y1, y2), 199);
    for (targets(&tb)) |b| {
        var y = ya;
        while (y <= yb) : (y += 1) {
            var x = xa;
            while (x <= xb) : (x += 1) plotOn(b, x, y, patternBit(x, y));
        }
    }
}

fn plot(x: i32, y: i32) void {
    if (x < 0 or x > 319 or y < 0 or y > 199) return;
    var tb: [2][]u8 = undefined;
    for (targets(&tb)) |b| plotOn(b, x, y, true);
}

pub fn box(x1: i32, y1: i32, x2: i32, y2: i32) void {
    draw(x1, y1, x2, y1);
    draw(x2, y1, x2, y2);
    draw(x2, y2, x1, y2);
    draw(x1, y2, x1, y1);
}

pub fn draw(x1: i32, y1: i32, x2: i32, y2: i32) void {
    const dx: i32 = @intCast(@abs(x2 - x1));
    const dy: i32 = -@as(i32, @intCast(@abs(y2 - y1)));
    const sx: i32 = if (x1 < x2) 1 else -1;
    const sy: i32 = if (y1 < y2) 1 else -1;
    var err = dx + dy;
    var x = x1;
    var y = y1;
    while (true) {
        plot(x, y);
        if (x == x2 and y == y2) return;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y += sy;
        }
    }
}

/// POINT(x,y): the colour on the logical screen (-1 off screen).
pub fn point(x: i32, y: i32) i32 {
    if (x < 0 or x > 319 or y < 0 or y > 199) return -1;
    return scr.get(scr.logic)[@intCast(y * 320 + x)];
}
