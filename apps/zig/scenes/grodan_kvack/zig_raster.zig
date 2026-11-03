// --------------------------------------------------------------------------
// grodan_kvack ZIG mode -- the copper: true-colour (24-bit) per-line palette
// writes on both planes, every one of the 280 rows, borders included (the
// borders are open on both planes, so each colour register paints the whole
// 400-px line, as an ST's does).
//
//   green plane, entry 0  the background: a dark gradient (the three sine-path
//                         copper bars over it are commented out, Matt 3 Nov)
//   main plane,  PINK     the rotozoomed layer's colour CYCLES per line: a
//                         pastel hue wheel, three steps a row, moving a frame
//   main plane,  BIG/VERT/SMALL  the original's three text rasters (ST-legal
//                         .pal rows) smoothed and stretched to 24-bit
//                         gradients over the overscan rows, built once
//
// Four slots on the main plane (copper's maximum), one on the green plane.
// The tables live in cart RAM (zg.mem), not in module-scope statics (which the
// cart link would materialise as data). Integers only, per frame and at init.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const copper = zg.copper;
const A = @import("assets.zig");
const L = @import("zig_layers.zig");

const ROWS: usize = zg.PHYSICAL_HEIGHT; // 280
pub const MAIN_ENTRIES = [_]u8{ A.PINK, A.BIG, A.VERT, A.SMALL };
pub const GREEN_ENTRIES = [_]u8{0};

var main_tables: *[MAIN_ENTRIES.len]copper.Table = undefined;
var green_tables: *[GREEN_ENTRIES.len]copper.Table = undefined;
var hue: *[256]u32 = undefined;
var base: *[ROWS]u32 = undefined; // the background gradient under the bars

inline fn rgb(r: u32, g: u32, b: u32) u32 {
    return r | g << 8 | b << 16 | 0xFF00_0000;
}
inline fn chan(c: u32, s: u5) u32 {
    return (c >> s) & 0xFF;
}

/// Allocate the tables, build the static ones and hand them to the copper
/// (borders opened from the same records). False when cart RAM is short.
pub fn install(main: *zg.LogicalFB, green: *zg.LogicalFB) bool {
    const m = zg.mem.mark();
    const mt = zg.mem.alloc(copper.Table, MAIN_ENTRIES.len) orelse return fail(m);
    const gt = zg.mem.alloc(copper.Table, GREEN_ENTRIES.len) orelse return fail(m);
    const hu = zg.mem.alloc(u32, 256) orelse return fail(m);
    const bs = zg.mem.alloc(u32, ROWS) orelse return fail(m);
    main_tables = mt[0..MAIN_ENTRIES.len];
    green_tables = gt[0..GREEN_ENTRIES.len];
    hue = hu[0..256];
    base = bs[0..ROWS];
    buildHue();
    for (base, 0..) |*c, r| c.* = rgb(0, @intCast(r / 20), @intCast(16 + r * 40 / ROWS));
    copper.install(main, &MAIN_ENTRIES, main_tables, .{ .flicker = true });
    copper.install(green, &GREEN_ENTRIES, green_tables, .{ .flicker = true });
    buildText();
    frame(0);
    return true;
}

fn fail(m: zg.mem.Mark) bool {
    zg.mem.release(m);
    return false;
}

/// A pastel hue wheel: three triangle waves 120 degrees apart, lifted to 96..255.
fn buildHue() void {
    for (hue, 0..) |*c, i| c.* = rgb(pastel(i), pastel(i + 85), pastel(i + 170));
}
fn pastel(i: usize) u32 {
    const p: u32 = @intCast(i & 255);
    const tri: u32 = if (p < 128) p * 2 else (255 - p) * 2; // 0..254
    return 96 + tri * 159 / 254;
}

/// The three text rasters over the overscan rows, as the original places its
/// content (+40 rows): smoothed from the .pal rows, so the colours leave the
/// ST's 3-bit grid.
fn buildText() void {
    const big = &main_tables[1];
    const vert = &main_tables[2];
    const small = &main_tables[3];
    const black = A.PALETTE[A.BLACK].toRGBA();
    const top: usize = @intCast(L.OY);
    for (0..ROWS) |r| {
        // VERT: the 200-row upraster stretched over all 280 rows (the border copies too).
        vert[r] = sample(&A.UP_ROWS, r * 199 * 256 / (ROWS - 1));
        big[r] = if (r >= top + 100 and r < top + 196)
            sample(&A.BIG_ROWS, (r - top - 100) * 256)
        else if (r >= top + 196) A.PALETTE[A.WHITE].toRGBA() else black;
        small[r] = if (r >= top + 8 and r < top + 16)
            sample(&A.UP_ROWS, 16 * 256 + (r - top - 8) * 128)
        else if (r >= top + 32 and r < top + 40)
            sample(&A.UP_ROWS, 64 * 256 + (r - top - 32) * 128)
        else black;
    }
}

/// Row `pos` (Q8) of a raster, smoothed: a 5-row box around it, linearly
/// interpolated between the two rows it falls between.
fn sample(rows: []const u32, pos: usize) u32 {
    const i = pos >> 8;
    const f: u32 = @intCast(pos & 255);
    var out: u32 = 0xFF00_0000;
    inline for (.{ 0, 8, 16 }) |s| {
        const c0 = box(rows, i, s);
        const c1 = box(rows, @min(i + 1, rows.len - 1), s);
        out |= ((c0 * (256 - f) + c1 * f) >> 8) << s;
    }
    return out;
}
fn box(rows: []const u32, i: usize, comptime s: u5) u32 {
    var sum: u32 = 0;
    var n: u32 = 0;
    var j = if (i >= 2) i - 2 else 0;
    while (j <= @min(i + 2, rows.len - 1)) : (j += 1) {
        sum += chan(rows[j], s);
        n += 1;
    }
    return sum / n;
}

const BAR_HALF: i32 = 14;
const BAR_COL = [3][3]u32{ .{ 255, 80, 40 }, .{ 60, 200, 255 }, .{ 255, 220, 60 } };

/// This tick's per-line colours: the pink hue cycle (and the background, bars off).
pub fn frame(tick: u32) void {
    const pink = &main_tables[0];
    for (pink, 0..) |*c, r| c.* = hue[(r * 3 + @as(usize, tick) * 2) & 255];
    const bg = &green_tables[0];
    @memcpy(bg, base);
    // The three sine-path bars, off (Matt, 3 Nov: "remove the horizontal raster bars"):
    // the background is the dark gradient alone. Kept commented to bring them back.
    // for (BAR_COL, 0..) |col, i| {
    //     const a: trig.Angle = tick *% (11_930_465 + @as(u32, @intCast(i)) * 3_000_000) +% @as(u32, @intCast(i)) * 0x5555_5555;
    //     const centre: i32 = 140 + (trig.sin(a) * 118 >> 16);
    //     var d: i32 = -BAR_HALF;
    //     while (d <= BAR_HALF) : (d += 1) {
    //         const r = centre + d;
    //         if (r < 0 or r >= ROWS) continue;
    //         // A rounded profile: 1 - (d / half)^2, Q8.
    //         const t: u32 = @intCast(256 - @divTrunc(d * d * 256, BAR_HALF * BAR_HALF));
    //         const o = bg[@intCast(r)];
    //         bg[@intCast(r)] = rgb(mix(chan(o, 0), col[0], t), mix(chan(o, 8), col[1], t), mix(chan(o, 16), col[2], t));
    //     }
    // }
}
inline fn mix(a: u32, b: u32, t: u32) u32 {
    return (a * (256 - t) + b * t) >> 8;
}
