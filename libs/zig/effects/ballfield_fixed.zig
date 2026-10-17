// --------------------------------------------------------------------------
// Ballfield in integers: the same field as ballfield.zig, for a cart CPU whose
// FPU is single precision, where every f64 add, compare and (worst) divide is a
// soft-float call. A TNT1 frame steps up to 1100 balls, two f64 divides each.
//
// What makes it exact where it matters: on every Union screen speed and ratio
// are whole numbers and w + h is even, so z stays an INTEGER (spawned, stepped
// by speed, wrapped by depth) and x, y only ever change by whole numbers after
// the spawn. So:
//   - x, y, and the projections px, py are Q32 in an i64 (the spawn keeps the
//     random's 32 bits whole: r * 2w in Q32 is just raw * 2w);
//   - x / z * ratio is one multiply by a TABLED reciprocal 2^48 / z (the table
//     is built at compile time) in an i128, rounded to Q32: 2e-10 of a canvas
//     pixel, where the f64 path's own rounding is 1e-13;
//   - the tile, round(z / (depth / tiles)), is a table over z, built with the
//     original f64 expression, so its .5 ties fall exactly where the JS did.
//
// The Field is generic over comptime Params; it errors at compile time on a
// fractional speed or ratio (use ballfield.Field there). No ZigOS import: it
// tests natively (ballfield_test.zig).
// --------------------------------------------------------------------------
const ballfield = @import("ballfield.zig");

pub const Params = ballfield.Params;
pub const Q = 32; // fraction bits of x, y, px, py

pub const Ball = struct { x: i64, y: i64, z: i32, px: i64, py: i64 };

/// A tile to draw at canvas (x, y) in Q32. `tile` can equal `tiles` (far plane).
pub const Draw = struct { x: i64, y: i64, tile: u32 };

/// Canvas Q32 value to the nearest ST pixel, Math.round(c / 2).
pub fn halfRound(q: i64) i32 {
    return @intCast((q + (1 << Q)) >> (Q + 1));
}

pub fn Field(comptime p: Params) type {
    if (p.speed != @floor(p.speed) or p.ratio != @floor(p.ratio)) @compileError("ballfield_fixed: speed and ratio must be whole numbers");
    if (@rem(p.w + p.h, 2) != 0) @compileError("ballfield_fixed: w + h must be even");
    const depth: i32 = @divExact(p.w + p.h, 2);
    const speed: i32 = @intFromFloat(p.speed);
    const ratio: i64 = @intFromFloat(p.ratio);
    const mid_x: i32 = @intFromFloat(@floor(@as(f64, @floatFromInt(p.w)) / 2 + 0.5)); // Math.round(w/2)
    const mid_y: i32 = @intFromFloat(@floor(@as(f64, @floatFromInt(p.h)) / 2 + 0.5));
    const drift_x: i64 = @as(i64, (p.centx - mid_x) >> 4) << Q;
    const drift_y: i64 = @as(i64, (p.centy - mid_y) >> 4) << Q;

    const tables = struct {
        const inv: [depth + 1]u64 = blk: {
            @setEvalBranchQuota(depth * 100 + 1000);
            var t: [depth + 1]u64 = undefined;
            t[0] = 0; // z = 0 never projects
            for (1..depth + 1) |z| t[z] = (1 << 48) / z;
            break :blk t;
        };
        const tile: [depth + 1]u8 = blk: {
            @setEvalBranchQuota(depth * 100 + 1000);
            const inter = @as(f64, @floatFromInt(depth)) / @as(f64, @floatFromInt(p.tiles));
            var t: [depth + 1]u8 = undefined;
            for (&t, 0..) |*v, z| v.* = @intFromFloat(@floor(@as(f64, @floatFromInt(z)) / inter + 0.5));
            break :blk t;
        };
    };

    return struct {
        /// The constructor's placement from three raw 32-bit random values
        /// (XorShift32.threeRaw): Math.random() is raw / 2^32.
        pub fn spawn(raw: [3]u32) Ball {
            const wx: i64 = @as(i64, p.w) * 2;
            const wy: i64 = @as(i64, p.h) * 2;
            return .{
                .x = @as(i64, raw[0]) * wx - ((@as(i64, mid_x) * 2 - 10) << Q),
                .y = @as(i64, raw[1]) * wy - ((@as(i64, mid_y) * 2 - 10) << Q),
                .z = @intCast((@as(u64, raw[2]) * @as(u64, @intCast(depth)) + (1 << 31)) >> 32),
                .px = 0,
                .py = 0,
            };
        }

        /// One ball's share of draw(): move it, and return what gets drawn, if anything.
        pub fn step(b: *Ball) ?Draw {
            const last_x = b.px;
            const last_y = b.py;
            var visible = true;
            b.x += drift_x;
            visible = wrap(&b.x, mid_x, p.w) and visible;
            b.y += drift_y;
            visible = wrap(&b.y, mid_y, p.h) and visible;
            b.z -= speed;
            if (b.z > depth) {
                b.z -= depth;
                visible = false;
            }
            if (b.z < 0) {
                b.z += depth;
                visible = false;
            }
            if (b.z == 0) {
                b.px = -1 << Q; // x/0: no test against the canvas passes
                b.py = -1 << Q;
            } else {
                const inv: i128 = tables.inv[@intCast(b.z)];
                b.px = (@as(i64, mid_x) << Q) + project(b.x, inv);
                b.py = (@as(i64, mid_y) << Q) + project(b.y, inv);
            }
            const w: i64 = @as(i64, p.w) << Q;
            const h: i64 = @as(i64, p.h) << Q;
            if (!(visible and last_x > 0 and last_x < w and last_y > 0 and last_y < h)) return null;
            return .{ .x = last_x, .y = last_y, .tile = tables.tile[@intCast(b.z)] };
        }

        /// x / z * ratio in Q32: (x * ratio) * (2^48 / z) >> 48, rounded.
        fn project(v: i64, inv: i128) i64 {
            return @intCast((@as(i128, v) * ratio * inv + (1 << 47)) >> 48);
        }

        /// `if (v > mid<<1) v -= size<<1; if (v < -mid<<1) v += size<<1;` true if neither fired.
        fn wrap(v: *i64, mid: i32, size: i32) bool {
            var kept = true;
            if (v.* > (@as(i64, mid) * 2) << Q) {
                v.* -= (@as(i64, size) * 2) << Q;
                kept = false;
            }
            if (v.* < -(@as(i64, mid) * 2) << Q) {
                v.* += (@as(i64, size) * 2) << Q;
                kept = false;
            }
            return kept;
        }
    };
}
