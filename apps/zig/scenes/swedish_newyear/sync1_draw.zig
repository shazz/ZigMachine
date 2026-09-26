// SYNC #1's pixel layers, each sampled at the 640-space point (2X+0.5, 2Y+0.5)
// through the remake's own transform, nearest (an ST moves whole pixels).
const frame = @import("frame.zig");
const gen = @import("assets_gen.zig");
const image = @import("image.zig");
const sc = @import("scroller.zig");
const fx = @import("fx.zig");

const ifloor = image.ifloor;
const NONE = image.NONE;

/// banner.drawTile(mycanvas, tile, 320, 51, 1, 0, 1, XX): midhandled, so the
/// 266x70 tile is centred on (320, 51) and squashed by XX about it. Column
/// 2X-187 is always odd (the asset keeps only those).
pub fn banner(tile: i32, xx: f64) void {
    if (xx == 0) return; // scale(1, 0): nothing is drawn
    var y: i32 = 0;
    while (y < 225) : (y += 1) {
        const v = ifloor((@as(f64, @floatFromInt(2 * y)) + 0.5 - 51) / xx + 35);
        if (v < 0 or v >= 70) continue;
        var x: i32 = 94;
        while (x <= 226) : (x += 1) {
            const g = gen.banner.at(x - 94, tile * 70 + v);
            if (g != NONE) frame.put(x, y, g);
        }
    }
}

pub const Place = struct { y: f64, flip: f64, plain: bool };

/// A 520x450 scroll canvas drawn to mycanvas, midhandled on (320, place.y):
/// plain = drawImage at (60, y-225); else scale(1, flip) about the handle.
pub fn scroller(s: *const sc.Scroller, place: Place) void {
    if (place.flip == 0) return;
    var owner: [520]u8 = undefined; // which letter covers canvas column cx
    var dy: [sc.MAX]f64 = undefined; // letter top: prov + 205
    letters(s, &owner, &dy);
    var y: i32 = 0;
    while (y < 225) : (y += 1) {
        const my = @as(f64, @floatFromInt(2 * y)) + 0.5;
        const cy = if (place.plain) 2 * y - ifloor(place.y - 225) else ifloor((my - place.y) / place.flip + 225);
        if (cy < 0 or cy >= 450) continue;
        const cyf = @as(f64, @floatFromInt(cy)) + 0.5;
        var x: i32 = 30;
        while (x < 290) : (x += 1) {
            const cx = 2 * x - 60;
            const k = owner[@intCast(cx)];
            if (k == 0xFF) continue;
            const g = glyph(s, k, cx, ifloor(cyf - dy[k]));
            if (g != NONE) frame.put(x, y, g);
        }
    }
}

/// The scroller's draw into its canvas: letters left to right, the sine phase
/// stepping `inc` per letter (repeated addition, as drawn).
fn letters(s: *const sc.Scroller, owner: *[520]u8, dy: *[sc.MAX]f64) void {
    @memset(owner, 0xFF);
    var ord: [sc.MAX]u8 = undefined;
    var phase = s.phase;
    for (s.order(&ord)) |k| {
        dy[k] = 205;
        if (s.sine) |sn| {
            dy[k] = @sin(phase) * sn.amp + 205;
            phase += sn.inc;
        }
        const px: i32 = @intFromFloat(s.posx[k]);
        var cx = @max(px, 0);
        while (cx < px + 32 and cx < 520) : (cx += 1) owner[@intCast(cx)] = k;
    }
}

fn glyph(s: *const sc.Scroller, k: u8, cx: i32, row: i32) u16 {
    if (row < 0 or row >= 27) return NONE;
    const nb: i32 = @as(i32, s.ltr[k]) - 32;
    const party = @divFloor(nb, 10) * 27;
    if (party >= 162) return NONE; // '\' ']' '_': no cell, nothing drawn
    const px: i32 = @intFromFloat(s.posx[k]);
    return gen.syncfont.at(@mod(nb, 10) * 32 + cx - px, party + row);
}

/// logo.png centred in a 640x450 canvas (top-left 235,200), FX sinx(50,50)
/// into a second, FX siny(50,50) into a third, drawn with its centre at
/// (230,15): mycanvas (x,y) = third (x+90, y+210).
pub fn logo(fx1: *fx.Fx(2), fx2: *fx.Fx(2)) void {
    var p: [450]f64 = undefined; // row shifts (sinx)
    var q: [640]f64 = undefined; // column shifts (siny)
    fx1.run(&p);
    fx2.run(&q);
    var y: i32 = 0;
    while (y < 120) : (y += 1) {
        const r3 = @as(f64, @floatFromInt(2 * y + 210)) + 0.5;
        var x: i32 = 0;
        while (x < 275) : (x += 1) {
            const i = 2 * x + 90 - 50; // the siny column
            if (i < 0 or i >= 640) continue;
            const r2 = ifloor(r3 - (q[@intCast(i)] + 50));
            if (r2 >= 450) continue; // the second canvas is 450 high
            const j = r2 - 50; // the sinx row
            if (j < 0) continue;
            const c1 = ifloor(@as(f64, @floatFromInt(i)) + 0.5 - (p[@intCast(j)] + 50));
            const g = gen.logo.at(c1 - 235, j - 200);
            if (g != NONE) frame.put(x, y, g);
        }
    }
}
