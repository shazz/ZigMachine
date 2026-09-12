// --------------------------------------------------------------------------
// CUDDLY STARWARS — the tables that drive the motion, built at comptime from
// the original's own parameters (prototypes/codef/360/screen.js). Pure: no
// ZigOS, so a scratch `zig test` can compare them against the JavaScript.
// --------------------------------------------------------------------------

/// JavaScript's Math.round: a half always goes up, negatives included.
pub fn jsRound(x: f64) f64 {
    const r = @floor(x);
    return if (x - r >= 0.5) r + 1 else r;
}

// --------------------------------------------------------------------------
// dist1: the scroller's per-column vertical offsets. init() makes twelve
// sinus() calls, each appending `iterations` values of size 50:
//   type 0: Math.round(50*Math.sin(c)/2 + 0.5)
//   type 2: Math.round(50*Math.abs(Math.sin(c)))
// with c accumulating 2*PI/iterations (accumulated, not multiplied: kept).
// --------------------------------------------------------------------------
const Sinus = struct { iterations: u32, abs: bool };

const SINUS_SIZE: f64 = 50;
const SINUS_CALLS = [_]Sinus{
    .{ .iterations = 100, .abs = false },
    .{ .iterations = 100, .abs = false },
    .{ .iterations = 50, .abs = false },
    .{ .iterations = 60, .abs = true },
    .{ .iterations = 30, .abs = false },
    .{ .iterations = 50, .abs = false },
    .{ .iterations = 30, .abs = false },
    .{ .iterations = 72, .abs = false },
    .{ .iterations = 60, .abs = false },
    .{ .iterations = 50, .abs = false },
    .{ .iterations = 30, .abs = false },
    .{ .iterations = 100, .abs = false },
};

fn sinusLength() usize {
    var n: usize = 0;
    for (SINUS_CALLS) |s| n += s.iterations;
    return n;
}

pub const dist: [sinusLength()]i8 = blk: {
    @setEvalBranchQuota(100_000);
    var out: [sinusLength()]i8 = undefined;
    var n: usize = 0;
    for (SINUS_CALLS) |s| {
        const increase: f64 = 3.141592653589793 * 2.0 / @as(f64, @floatFromInt(s.iterations));
        var counter: f64 = 0;
        for (0..s.iterations) |_| {
            const v = if (s.abs)
                jsRound(SINUS_SIZE * @abs(@sin(counter)))
            else
                jsRound(SINUS_SIZE * @sin(counter) / 2.0 + 0.5);
            out[n] = @intFromFloat(v);
            n += 1;
            counter += increase;
        }
    }
    break :blk out;
};

/// `dist1.push(sindata.slice(0, 540))` appends ONE element (an array), so the
/// JS dist1 is one longer than the values. It is never read, but it moves the
/// wrap: dcount resets to 20 once it exceeds dist1.length - 80.
pub const DIST_LIMIT: usize = dist.len + 1 - 80;
pub const DIST_RESET: usize = 20;

// --------------------------------------------------------------------------
// The starwars perspective. init() precomputes, for i = -160..199,
//   scale = 250/(250+i),  y = Math.round((i+350)*scale)
// and each frame, for the n-th entry whose y differs from the previous one,
//   fakesscanvas.drawPart(tmpcanvas, 160, y, 0, 310-n, 320, 1-n/360, 1, 0, 0.8*scale, 1)
// on a mid-handled 320x420 text canvas: source row 310-n, stretched 0.8*scale
// about x=160, drawn ph = 1-n/360 tall centred on y. Rows 300..399 of that
// canvas are then copied to screen rows 100..199.
//
// Measured against Chrome rendering the original (mean error 0.23/255): each
// dest row takes the draw's vertical AREA coverage times a BILINEAR sample of
// the text canvas. Flattened here into one entry per (draw, screen row).
// --------------------------------------------------------------------------
pub const FOV: f64 = 250;
pub const SS_ENTRIES: usize = 360; // i = -160..199
pub const TMP_FIRST_ROW: i32 = 300; // tmpcanvas.drawPart(orgcanvas, 0, 100, 0, 300, 320, 100)
pub const BAND_ROWS: usize = 100;

pub const PerspectiveRow = struct {
    band_row: u16, // screen row - 100
    coverage: f64, // how much of the row the ph-tall draw covers
    src_row: i32, // upper text-canvas row of the bilinear pair
    src_frac: f64, // weight of src_row + 1
    zoom: f64, // 0.8 * scale
    x_first: u16, // screen columns whose centres fall inside the stretched row
    x_last: u16,
};

const MAX_ROWS = SS_ENTRIES * 3;

fn buildPerspective() struct { rows: [MAX_ROWS]PerspectiveRow, len: usize } {
    var rows: [MAX_ROWS]PerspectiveRow = undefined;
    var len: usize = 0;
    var savey: f64 = 0;
    for (0..SS_ENTRIES) |n| {
        const i: f64 = @as(f64, @floatFromInt(n)) - 160;
        const scale = FOV / (FOV + i);
        const y = jsRound((i + 350) * scale);
        defer savey = y;
        if (y == savey) continue;
        const src_top: i32 = 310 - @as(i32, @intCast(n));
        if (src_top < 0) continue; // drawPart: parth += party goes <= 0 and it returns
        const ph = 1 - @as(f64, @floatFromInt(n)) * (1.0 / 360.0);
        const zoom = scale * 0.8;
        const top = y - ph / 2;
        const bot = y + ph / 2;
        const left = 160 - 160 * zoom;
        const right = 160 + 160 * zoom;
        const x_first: u16 = @intFromFloat(@max(0, @ceil(left - 0.5)));
        const x_last: u16 = @intFromFloat(@min(319, @floor(right - 0.5)));
        var row = @floor(top);
        while (row < @ceil(bot)) : (row += 1) {
            const coverage = @min(bot, row + 1) - @max(top, row);
            const band = @as(i32, @intFromFloat(row)) - TMP_FIRST_ROW;
            if (coverage <= 0 or band < 0 or band >= BAND_ROWS) continue;
            const sy = @as(f64, @floatFromInt(src_top)) + (row + 0.5 - top) - 0.5;
            rows[len] = .{
                .band_row = @intCast(band),
                .coverage = coverage,
                .src_row = @intFromFloat(@floor(sy)),
                .src_frac = sy - @floor(sy),
                .zoom = zoom,
                .x_first = x_first,
                .x_last = x_last,
            };
            len += 1;
        }
    }
    return .{ .rows = rows, .len = len };
}

const built = blk: {
    @setEvalBranchQuota(1_000_000);
    break :blk buildPerspective();
};

pub const perspective: [built.len]PerspectiveRow = built.rows[0..built.len].*;

/// Text-canvas rows the perspective ever samples; the rest of the 420 are never seen.
pub const TEXT_ROWS: usize = blk: {
    var hi: i32 = 0;
    for (perspective) |p| hi = @max(hi, p.src_row + 2);
    break :blk @intCast(hi);
};
