// --------------------------------------------------------------------------
// Union intro — the WAB part's flight, precomputed (used by wab.zig).
//
// Every turning tile's per-frame setup (where it flies, its turn, its alpha, the
// plane span it can reach and its texture coordinates at the span's corner) is
// deterministic: a seeded mulberry32 and the remake's f64 formulas. It cost ~24K
// soft-float f64 operations a frame on KESTREL (cos, sin, floors, divides: the
// board showed ~4 fps), so it is evaluated HERE, at compile time, with the same
// f64 maths pasted from the port it replaces (eflogowabentry.js /
// codef_animatedtiles.js via wab.zig), and the frame only indexes ENTRIES.
// apps/zig/scenes/union/wab_table_test.zig recomputes every entry natively and
// proves the integer blit (wab_turn.zig) picks the f64 blit's texel on every pixel.
// --------------------------------------------------------------------------
const std = @import("std");

pub const TILE: f64 = 33; // eflogowabentry.js:31
pub const HALF_TILE: f64 = TILE / 2; // setmidhandle: drawPart translates by -partw/2
pub const GRID: usize = 8;
pub const NT: usize = GRID * GRID;
pub const ENDVBL: u32 = 110; // generateTilesHelper's aSpeed: every tile is at rest from here
const CANVAS_W: f64 = 768; // index.html:58 sequencer_InitAndStart(768, 540, ...)
const CANVAS_H: f64 = 540;
const IMAGE: f64 = 264; // eflogowab5.png
const STAGGER: f64 = 40; // startvbl = Math.ceil(40*Math.random())
const TURNS_DEG: f64 = 360 * 2; // rotangle += (360*2)/speed per move
const LEVELS: f64 = 32; // wab_shade.dat rows + the untouched level
pub const ORIGIN_X: f64 = 8; // canvas (0,0) on the 400x280 plane, as placement.zig
pub const ORIGIN_Y: f64 = 5;
const PLANE_W: i32 = 400; // zg.PHYSICAL_WIDTH / HEIGHT (wab.zig asserts it)
const PLANE_H: i32 = 280;
// A rotated tile reaches half its diagonal from its centre, plus the edge pixel.
const REACH: f64 = HALF_TILE * std.math.sqrt2 + 1;
const SEED: u32 = 0x77ab5;
const ONE: f64 = 16777216.0; // Q24, as wab_turn.zig

/// Which of the 8x8 tiles have some alpha: wab_tiles.dat (wab.zig asserts it).
pub const MASK = [NT]u1{
    0, 0, 1, 1, 1, 1, 0, 0,
    0, 1, 1, 1, 1, 1, 1, 0,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,
    0, 1, 1, 1, 1, 1, 1, 0,
    0, 0, 1, 1, 1, 1, 0, 0,
    0, 0, 0, 1, 1, 0, 0, 0,
};

/// One turning tile on one frame. (u0, v0): texture coordinates at (x0, y0), Q24;
/// per plane pixel u += du and v += dv, per row u -= dv and v += du.
pub const Entry = extern struct {
    u0: i32,
    v0: i32,
    du: i32, // q24(2 cos)
    dv: i32, // q24(-2 sin)
    x0: i16,
    y0: i16,
    w: u8, // the span, clamped to the plane
    h: u8,
    level: u8, // 1..32: the shade row (32 = the logo's own colours)
    tile: u8,
};

/// mulberry32: a Math.random stand-in the harness can replay bit for bit.
const Random = struct {
    state: u32,
    fn next(self: *Random) f64 {
        self.state +%= 0x6D2B79F5;
        var t = (self.state ^ (self.state >> 15)) *% (self.state | 1);
        t = (t +% ((t ^ (t >> 7)) *% (t | 61))) ^ t;
        return @as(f64, @floatFromInt(t ^ (t >> 14))) / 4294967296.0;
    }
};

pub const Tile = struct { start_x: f64 = 0, start_y: f64 = 0, startvbl: u32 = 0 };

/// generateTilesHelper: only tiles with some alpha get an animatedTile, and each
/// draws startvbl, then currX, then currY (argument order, then init).
pub fn tiles() [NT]Tile {
    var rng = Random{ .state = SEED };
    var t: [NT]Tile = @splat(.{});
    for (&t, 0..) |*tile, i| {
        if (MASK[i] == 0) continue;
        tile.startvbl = @intFromFloat(@ceil(STAGGER * rng.next()));
        tile.start_x = CANVAS_W * rng.next();
        tile.start_y = CANVAS_H * rng.next();
    }
    return t;
}

/// The f64 values the remake's turned-tile draw works from (wab_table_test.zig's reference).
pub const Flight = struct { cx: f64, cy: f64, cs: f64, sn: f64, x0: i32, x1: i32, y0: i32, y1: i32, level: usize };

/// animatedTile.draw for tile `i` on part frame `frame` (< ENDVBL), after its advance():
/// null when it does not draw, else where it is, its turn, its span and its alpha level.
pub fn flight(t: Tile, i: usize, frame: u32) ?Flight {
    if (MASK[i] == 0 or frame < t.startvbl or frame >= ENDVBL) return null; // draws once vbl > startvbl
    const speed: f64 = @floatFromInt(ENDVBL - t.startvbl);
    const moves: f64 = @floatFromInt(@min(frame - t.startvbl, ENDVBL - t.startvbl));
    // globalAlpha = (vbl-startvbl)/(endvbl-startvbl); above 1 the canvas ignores it.
    const alpha = @min(1.0, @as(f64, @floatFromInt(frame + 1 - t.startvbl)) / speed);
    const level: usize = @intFromFloat(@round(alpha * LEVELS));
    if (level == 0) return null;
    const tx: f64 = @floatFromInt(i % GRID);
    const ty: f64 = @floatFromInt(i / GRID);
    const final_x = tx * TILE + (CANVAS_W - IMAGE) / 2;
    const final_y = ty * TILE + (CANVAS_H - IMAGE) / 2;
    // Before ENDVBL every drawn tile is still flying (moves < speed).
    const x = t.start_x + (final_x - t.start_x) / speed * moves;
    const y = t.start_y + (final_y - t.start_y) / speed * moves;
    const rad = TURNS_DEG / speed * moves * std.math.pi / 180.0;
    const cx = x + HALF_TILE;
    const cy = y + HALF_TILE;
    return .{
        .cx = cx,
        .cy = cy,
        .cs = @cos(rad),
        .sn = @sin(rad),
        .x0 = planeSpan(cx - REACH, ORIGIN_X, PLANE_W, false),
        .x1 = planeSpan(cx + REACH, ORIGIN_X, PLANE_W, true),
        .y0 = planeSpan(cy - REACH, ORIGIN_Y, PLANE_H, false),
        .y1 = planeSpan(cy + REACH, ORIGIN_Y, PLANE_H, true),
        .level = level,
    };
}

/// The table entry of tile `i` on `frame`: the corner (u,v) and the steps, in Q24.
pub fn setup(t: Tile, i: usize, frame: u32) ?Entry {
    const fl = flight(t, i, frame) orelse return null;
    if (fl.x0 >= fl.x1 or fl.y0 >= fl.y1) return null;
    // (u,v) at the span's first pixel, and its steps: qx and qy grow by 2 a pixel.
    const qx0 = 2 * (@as(f64, @floatFromInt(fl.x0)) - ORIGIN_X) + 1 - fl.cx;
    const qy0 = 2 * (@as(f64, @floatFromInt(fl.y0)) - ORIGIN_Y) + 1 - fl.cy;
    return .{
        .u0 = q24(fl.cs * qx0 + fl.sn * qy0 + HALF_TILE),
        .v0 = q24(-fl.sn * qx0 + fl.cs * qy0 + HALF_TILE),
        .du = q24(2 * fl.cs),
        .dv = q24(-2 * fl.sn),
        .x0 = @intCast(fl.x0),
        .y0 = @intCast(fl.y0),
        .w = @intCast(fl.x1 - fl.x0),
        .h = @intCast(fl.y1 - fl.y0),
        .level = @intCast(fl.level),
        .tile = @intCast(i),
    };
}

/// First (or one past the last) plane coordinate whose pixel can reach canvas `c`.
fn planeSpan(c: f64, origin: f64, limit: i32, end: bool) i32 {
    const p = (c - 1) / 2 + origin;
    const v: i32 = @intFromFloat(if (end) @floor(p) + 2 else @floor(p));
    return std.math.clamp(v, 0, limit);
}

fn q24(x: f64) i32 {
    return @intFromFloat(@round(x * ONE));
}

fn count() usize {
    const t = tiles();
    var n: usize = 0;
    for (0..ENDVBL) |f| for (0..NT) |i| {
        if (setup(t[i], i, @intCast(f)) != null) n += 1;
    };
    return n;
}

const N_ENTRIES = blk: {
    @setEvalBranchQuota(10_000_000);
    break :blk count();
};

/// Every frame's turned tiles, frame by frame, in tile order (the draw order: a
/// piece over another replaces it). Frame f's are ENTRIES[FIRST[f]..FIRST[f + 1]].
pub const ENTRIES: [N_ENTRIES]Entry = table.entries;
pub const FIRST: [ENDVBL + 1]u16 = table.first;

const table = blk: {
    @setEvalBranchQuota(50_000_000);
    const t = tiles();
    var e: [N_ENTRIES]Entry = undefined;
    var first: [ENDVBL + 1]u16 = undefined;
    var n: usize = 0;
    for (0..ENDVBL) |f| {
        first[f] = n;
        for (0..NT) |i| if (setup(t[i], i, f)) |s| {
            e[n] = s;
            n += 1;
        };
    }
    first[ENDVBL] = n;
    break :blk .{ .entries = e, .first = first };
};
