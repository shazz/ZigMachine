// --------------------------------------------------------------------------
// RACER: the race HUD over the picture (R82 bug pass, Matt 27 Nov: "the arcade shows its info OVER the
// picture"). Our own look, the title's: the big numbers in the logo's scaled font and gradient with its
// drop shadow, the labels in white with a dark shadow, no boxes. Drawn into the view after the 3D (and
// after the benchmark's view CRC) with no plane of its own (a plane costs ~0.6 Mc a frame on the board):
//
//   POS               TIME            LAP              the place / cars, the clock, the lap time
//   3/8                45          0:12.3
//                                          [map]       the racing line, the AI cars, the player
//   [rev gauge]
//   245 KM/H                           SALT FLATS      speed, the gauge above it; the course name
//
// The countdown, GO, the finish and EXTEND TIME show big in the middle. The 3D repaints the whole view
// every frame, so the overlay is drawn every frame too (a few thousand bytes of runs: ~0.01-0.02 Mc).
// The old two bands stay as an option (key 0, and the benchmark laps always: their lines are the bench's).
// No ZigOS import: the pixels and the font are parameters (hudpic_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const carmodel = @import("carmodel.zig");
const menu = @import("menu.zig");
const minimap = @import("minimap.zig");
const palette = @import("palette.zig");

pub var on = true; // key 0: the picture HUD (default) or the two bands
pub const MAP = [4]i32{ 250, 44, 64, 56 }; // the minimap's box: x, y, w, h
pub const GAUGE_SEGS = 12;

pub const Info = struct {
    state: enum { grid, countdown, race, finish, other } = .race, // grid / other: present.zig shows the bands instead
    place: u32 = 1,
    cars: u32 = 8,
    seconds: i32 = 0,
    lap_ticks: u32 = 0,
    lap: u32 = 1,
    laps: u32 = 3,
    kmh: u32 = 0,
    rev: u32 = 0, // 0..256: the engine's revs
    count: u32 = 3, // the countdown's digit
    win: bool = false,
    extend: bool = false, // EXTEND TIME blinking on this frame
    track: []const u8 = "",
};

/// The picture HUD is on (key 0) in a race (never a benchmark lap: its lines are the bench's) from the countdown to the
/// finish; the grid's prompt and the results stay in the bands.
pub fn shows(race: bool, st: @import("fsm.zig").State) bool {
    return on and race and (st == .countdown or st == .race or st == .finish);
}

/// The racing line fitted to MAP's box.
pub fn fitMap(t: *const @import("trk.zig").Track) minimap.Map {
    return minimap.Map.fit(t, MAP[2], MAP[3]);
}

/// The overlay for one frame. `map` is fitted to MAP's box; `cars` the eight positions (the player's first).
pub fn draw(p: menu.Px, font: []const u8, i: Info, map: *const minimap.Map, cars: []const [3]i32) void {
    var b: [24]u8 = undefined;
    switch (i.state) {
        .countdown => return centre(p, font, fmt(&b, "{}", .{i.count}), 70, 4),
        .grid, .other => return,
        .race, .finish => {},
    }
    label(p, font, "POS", 8, 16);
    p.big(font, fmt(&b, "{}/{}", .{ i.place, i.cars }), 8, 26, 2);
    label(p, font, "TIME", 160 - 16, 16);
    const t = fmt(&b, "{}", .{@max(i.seconds, 0)});
    p.big(font, t, 160 - @as(i32, @intCast(t.len)) * 8, 26, 2);
    label(p, font, fmt(&b, "LAP {}/{}", .{ @min(i.lap, i.laps), i.laps }), 312 - 9 * 8, 16);
    const lt = lapTime(&b, i.lap_ticks);
    p.big(font, lt, 312 - @as(i32, @intCast(lt.len)) * 8, 27, 1);
    mapOver(p, map, cars);
    gauge(p, i.rev, 8, 154);
    const k = fmt(&b, "{}", .{i.kmh});
    p.big(font, k, 8, 164, 2);
    label(p, font, "KM/H", 12 + @as(i32, @intCast(k.len)) * 16, 172);
    label(p, font, i.track, 312 - @as(i32, @intCast(i.track.len)) * 8, 172);
    if (i.state == .finish) centre(p, font, if (i.win) "FINISH" else "TIME OVER", 76, 3);
    if (i.extend) centre(p, font, "EXTEND TIME", 64, 2);
}

fn fmt(b: []u8, comptime f: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(b, f, args) catch "";
}

/// M:SS.T of a 30 Hz tick count.
pub fn lapTime(b: []u8, t: u32) []const u8 {
    const tenths = t / 3;
    return fmt(b, "{}:{d:0>2}.{}", .{ tenths / 600, tenths / 10 % 60, tenths % 10 });
}

fn centre(p: menu.Px, font: []const u8, s: []const u8, y: i32, scale: i32) void {
    p.big(font, s, 160 - @as(i32, @intCast(s.len)) * 4 * scale, y, scale);
}

/// White text with a dark shadow one pixel down-right, transparent.
pub fn label(p: menu.Px, font: []const u8, s: []const u8, x: i32, y: i32) void {
    glyphs(p, font, s, x + 1, y + 1, menu.SHADE);
    glyphs(p, font, s, x, y, palette.INK);
}

fn glyphs(p: menu.Px, font: []const u8, s: []const u8, x: i32, y: i32, c: u8) void {
    for (s, 0..) |ch, n| {
        const g = font[@as(usize, ch) * 64 ..][0..64];
        const gx = x + @as(i32, @intCast(n)) * 8;
        for (0..8) |r| {
            var col: usize = 0;
            while (col < 8) {
                if (g[r * 8 + col] == 0) {
                    col += 1;
                    continue;
                }
                const a = col;
                while (col < 8 and g[r * 8 + col] != 0) col += 1;
                p.rect(gx + @as(i32, @intCast(a)), y + @as(i32, @intCast(r)), @intCast(col - a), 1, c);
            }
        }
    }
}

/// The rev gauge: GAUGE_SEGS segments filled left to right with the revs, the last three in red, a dark backing.
pub fn gauge(p: menu.Px, rev: u32, x: i32, y: i32) void {
    const r: u32 = @min(rev, 256); // a u32: @min with 256 alone narrows to u9 (and the product wrapped)
    const lit = (r * GAUGE_SEGS + 128) / 256;
    for (0..GAUGE_SEGS) |s| {
        const sx = x + @as(i32, @intCast(s)) * 6;
        const h: i32 = 3 + @as(i32, @intCast(s / 2)); // rising like a tachometer
        const c: u8 = if (s >= lit) menu.SHADE else if (s >= GAUGE_SEGS - 3) menu.ALERT else menu.LOGO[0];
        p.rect(sx, y + 8 - h, 5, h, c);
    }
}

/// The minimap over the picture: the line in white on a dark one-pixel shadow, the AI cars in their liveries, the player
/// 2 x 2 in the highlight colour. No background: the view shows through.
fn mapOver(p: menu.Px, map: *const minimap.Map, cars: []const [3]i32) void {
    for (map.pts[0..map.n]) |q| p.rect(MAP[0] + q[0] + 1, MAP[1] + q[1] + 1, 1, 1, menu.SHADE);
    for (map.pts[0..map.n]) |q| p.rect(MAP[0] + q[0], MAP[1] + q[1], 1, 1, palette.INK);
    for (cars[1..], 0..) |c, k| {
        const q = map.to(c);
        p.rect(MAP[0] + q[0], MAP[1] + q[1], 2, 2, @intCast(16 + (carmodel.RAMP_LIVERY + k % carmodel.LIVERIES) * 8 + 6));
    }
    const q = map.to(cars[0]);
    p.rect(MAP[0] + q[0] - 1, MAP[1] + q[1] - 1, 3, 3, menu.HILITE);
}
