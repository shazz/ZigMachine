// --------------------------------------------------------------------------
// Ballfield: CODEF's `ballfield` (codef_bobfield.js), a 3D field of ball bobs
// flying at the viewer.
//
// Each ball is a point (x, y, z) around the centre. Every draw() moves z towards
// the viewer by `speed` (wrapping past 0 back to the far plane), projects it as
// centre + (x / z) * ratio, and draws the POSITION IT PROJECTED LAST TIME with a
// tile picked by its NEW depth: round(z / (depth / tiles)). A ball that wrapped
// this step, or whose last projection lay outside the canvas (strict edges), is
// not drawn. The drift term (centre - middle) >> 4 is JS int32 arithmetic and is
// 0 whenever the centre is the middle, as every Union screen has it.
//
// The ball state stays in canvas units and f64, in the JS's own operation order,
// so a scene driven by the same random numbers draws the same balls. Scenes own
// the ball array (up to however many their keys ask for) and do the drawing.
//
// No ZigOS import: it tests natively (ballfield_test.zig).
// --------------------------------------------------------------------------

pub const Ball = struct { x: f64, y: f64, z: f64, px: f64, py: f64 };

/// new ballfield(dest, nb, speed, w, h, centx, centy, ratio, offsetx, offsety, balls, nbballs)
pub const Params = struct {
    w: i32,
    h: i32,
    centx: i32,
    centy: i32,
    speed: f64,
    ratio: f64,
    tiles: u32, // nbballs, at least 1
    // offsetx/offsety (0 on every Union screen) are the scene's to add when drawing
};

/// A tile to draw at canvas (x, y). `tile` can equal `tiles` at the far plane,
/// where CODEF's drawTile reads past a one-row sheet and draws nothing.
pub const Draw = struct { x: f64, y: f64, tile: u32 };

pub const Field = struct {
    p: Params,
    mid_x: i32, // Math.round(w/2)
    mid_y: i32,
    depth: f64, // (w+h)/2
    inter: f64, // drawBall's ((w+h)/2) / nbballs

    pub fn init(p: Params) Field {
        const depth = @as(f64, @floatFromInt(p.w + p.h)) / 2;
        return .{ .p = p, .mid_x = roundHalf(p.w), .mid_y = roundHalf(p.h), .depth = depth, .inter = depth / @as(f64, @floatFromInt(p.tiles)) };
    }

    /// The constructor's placement from three Math.random() values.
    pub fn spawn(self: *const Field, r: [3]f64) Ball {
        const w: f64 = @floatFromInt(self.p.w);
        const h: f64 = @floatFromInt(self.p.h);
        return .{
            .x = r[0] * w * 2 - @as(f64, @floatFromInt(self.mid_x * 2)) + 10,
            .y = r[1] * h * 2 - @as(f64, @floatFromInt(self.mid_y * 2)) + 10,
            .z = @floor(r[2] * self.depth + 0.5),
            .px = 0,
            .py = 0,
        };
    }

    /// One ball's share of draw(): move it, and return what gets drawn, if anything.
    pub fn step(self: *const Field, b: *Ball) ?Draw {
        const last_x = b.px;
        const last_y = b.py;
        var visible = true;
        b.x += @as(f64, @floatFromInt((self.p.centx - self.mid_x) >> 4));
        visible = wrap(&b.x, self.mid_x, self.p.w) and visible;
        b.y += @as(f64, @floatFromInt((self.p.centy - self.mid_y) >> 4));
        visible = wrap(&b.y, self.mid_y, self.p.h) and visible;
        b.z -= self.p.speed;
        if (b.z > self.depth) {
            b.z -= self.depth;
            visible = false;
        }
        if (b.z < 0) {
            b.z += self.depth;
            visible = false;
        }
        if (b.z == 0) {
            // x/0 is +-Infinity or NaN in JS: no test against the canvas passes
            b.px = -1;
            b.py = -1;
        } else {
            b.px = @as(f64, @floatFromInt(self.mid_x)) + (b.x / b.z) * self.p.ratio;
            b.py = @as(f64, @floatFromInt(self.mid_y)) + (b.y / b.z) * self.p.ratio;
        }
        const w: f64 = @floatFromInt(self.p.w);
        const h: f64 = @floatFromInt(self.p.h);
        if (!(visible and last_x > 0 and last_x < w and last_y > 0 and last_y < h)) return null;
        return .{ .x = last_x, .y = last_y, .tile = @intFromFloat(@floor(b.z / self.inter + 0.5)) };
    }
};

/// `if (v > mid<<1) v -= size<<1; if (v < -mid<<1) v += size<<1;` true if neither fired.
fn wrap(v: *f64, mid: i32, size: i32) bool {
    var kept = true;
    if (v.* > @as(f64, @floatFromInt(mid << 1))) {
        v.* -= @as(f64, @floatFromInt(size << 1));
        kept = false;
    }
    if (v.* < @as(f64, @floatFromInt(-mid << 1))) {
        v.* += @as(f64, @floatFromInt(size << 1));
        kept = false;
    }
    return kept;
}

/// Math.round(n / 2) for a non-negative int.
fn roundHalf(n: i32) i32 {
    return @intFromFloat(@floor(@as(f64, @floatFromInt(n)) / 2 + 0.5));
}

/// A Math.random() stand-in both a scene and its JS replay can reproduce:
/// xorshift32 (13, 17, 5) over [0, 1).
pub const XorShift32 = struct {
    s: u32,

    pub fn init(seed: u32) XorShift32 {
        return .{ .s = if (seed == 0) 1 else seed };
    }

    pub fn next(self: *XorShift32) f64 {
        self.s ^= self.s << 13;
        self.s ^= self.s >> 17;
        self.s ^= self.s << 5;
        return @as(f64, @floatFromInt(self.s)) / 4294967296.0;
    }

    pub fn three(self: *XorShift32) [3]f64 {
        return .{ self.next(), self.next(), self.next() };
    }
};
