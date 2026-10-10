// 3-vectors over a number back-end M (fixed.zig or float.zig).
pub fn Vec(comptime M: type) type {
    const T = M.T;
    return struct {
        const V = @This();
        x: T,
        y: T,
        z: T,

        pub fn of(x: T, y: T, z: T) V {
            return .{ .x = x, .y = y, .z = z };
        }
        pub fn add(a: V, b: V) V {
            return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
        }
        pub fn sub(a: V, b: V) V {
            return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
        }
        pub fn scale(a: V, s: T) V {
            return .{ .x = M.mul(a.x, s), .y = M.mul(a.y, s), .z = M.mul(a.z, s) };
        }
        pub fn dot(a: V, b: V) T {
            return M.mul(a.x, b.x) + M.mul(a.y, b.y) + M.mul(a.z, b.z);
        }
        /// o + d*t: the point t along a ray.
        pub fn at(o: V, d: V, t: T) V {
            return o.add(d.scale(t));
        }
        pub fn len(a: V) T {
            return M.len3(a.x, a.y, a.z);
        }
        pub fn unit(a: V) V {
            return a.scale(M.div(M.ONE, a.len()));
        }
    };
}
