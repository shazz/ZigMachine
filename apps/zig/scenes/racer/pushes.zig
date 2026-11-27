// --------------------------------------------------------------------------
// RACER: car-vs-car in ARCADE (R82 bug pass, Matt 27 Nov: "cars overlap"). freds72's contacts
// (contacts.zig, CLASSIC, untouched) push only the player, against the first car in range, with
// colliders 0.25 + 0.312 units long: the cars are drawn 2x that (the GT) times the track's car scale,
// and the AI cars never see each other, so in ARCADE they drove through each other. Here EVERY pair of
// cars on the same deck pushes, at the size they are DRAWN: a car is a row of circles along its
// footprint (the shadow's box, carfile.Foot, times the car scale: Car.body), as wide as the car.
// Overlapping circles are moved apart by half the overlap each (no car is ever drawn inside another),
// and a closing speed along the separation is exchanged with a little bounce (equal masses). The
// deepest circle pair of each car pair decides. Integer, PICO-8 16.16. No ZigOS import.
// --------------------------------------------------------------------------
const car = @import("car.zig");
const fix = @import("fix.zig");
const ground = @import("ground.zig");
const vec = @import("vec.zig");
const V = vec.V;
const lit = fix.lit;

/// A car's footprint in the physics (Q16 world units): half its width, half its length, the box's centre forward of pos.
pub const Body = struct { hw: i32 = 0, hl: i32 = 0, cz: i32 = 0 };
const BOUNCE = lit(0.6); // (1 + e) / 2 with e = 0.2: a closing speed mostly absorbed, a little given back
pub var break_push = false; // the harness' --break push (key !): ARCADE back to freds72's player-only contacts

/// The circles' centres of car `c`: three along its length (one when it is no longer than wide).
fn circles(c: *const car.Car, out: *[3]V) []V {
    const fwd = c.axes().fwd;
    const mid = vec.add(c.pos, fwd, c.body.cz);
    const reach = c.body.hl - c.body.hw;
    if (reach <= 0) {
        out[0] = mid;
        return out[0..1];
    }
    out[0] = vec.add(mid, fwd, -reach);
    out[1] = mid;
    out[2] = vec.add(mid, fwd, reach);
    return out[0..3];
}

/// One tick's pushes between every pair of `cars` (after all of them moved). Returns the contacts the player (car 0) had:
/// the impact sound's count, as freds72's contacts are.
pub fn update(cars: []car.Car) u32 {
    var n: u32 = 0;
    for (cars, 0..) |*a, i| {
        for (cars[i + 1 ..]) |*b| {
            if (pair(a, b) and i == 0) n += 1;
        }
    }
    return n;
}

fn pair(a: *car.Car, b: *car.Car) bool {
    const o = overlap(a, b);
    if (o.depth == 0) return false;
    separate(a, b, o.axis, o.depth);
    return true;
}

pub const Overlap = struct { depth: i32 = 0, axis: V = .{ 0, 0, 0 } };

/// How deep two cars' bodies overlap (0: apart, another deck, or no body) and the axis from a to b.
pub fn overlap(a: *const car.Car, b: *const car.Car) Overlap {
    if (a.body.hw == 0 or b.body.hw == 0) return .{};
    if (fix.abs(a.pos[1] -% b.pos[1]) > ground.DECK_Y) return .{}; // another deck (a crossing)
    const far = a.body.hl + b.body.hl + fix.abs(a.body.cz) + fix.abs(b.body.cz);
    if (fix.abs(a.pos[0] -% b.pos[0]) > far or fix.abs(a.pos[2] -% b.pos[2]) > far) return .{};
    var ca: [3]V = undefined;
    var cb: [3]V = undefined;
    const r = a.body.hw + b.body.hw;
    var o = Overlap{};
    for (circles(a, &ca)) |p| for (circles(b, &cb)) |q| {
        var d = vec.between(p, q);
        d[1] = 0;
        const l = vec.len(d);
        if (r - l > o.depth) o = .{ .depth = r - l, .axis = if (l == 0) a.axes().right else vec.scale(d, fix.div(fix.ONE, l)) };
    };
    return o;
}

fn separate(a: *car.Car, b: *car.Car, n: V, depth: i32) void {
    a.pos = vec.add(a.pos, n, -(depth >> 1));
    b.pos = vec.add(b.pos, n, depth - (depth >> 1));
    const closing = vec.dot(vec.between(a.vel, b.vel), n); // < 0: b comes toward a along n
    if (closing >= 0) return;
    const j = fix.mul(BOUNCE, closing);
    a.vel = vec.add(a.vel, n, j);
    b.vel = vec.add(b.vel, n, -j);
}
