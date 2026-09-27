// --------------------------------------------------------------------------
// SET ZONE / RESET ZONE / ZONE(n) and COLLIDE(n,w,h), transcribed from the
// STOS sprite trap (#5 functions 24-26 and 5, RAM $3CB46-$3CBD8, $3B0F4).
//
//   SET ZONE z,x1,y1 TO x2,y2   128 zones; refused unless x1 < x2, y1 < y2
//   ZONE(n)    the LOWEST-numbered zone holding sprite n's hot spot, edges
//              included (x1 <= x <= x2, y1 <= y <= y2); 0 if none or if the
//              sprite is off
//   COLLIDE(n,w,h)  bit k set for every other sprite k (0 = the pointer)
//              whose hot spot lies within w pixels across and h down of
//              sprite n's, edges included
// --------------------------------------------------------------------------
const sprite = @import("sprite.zig");

pub const N: usize = 128;
const Z = struct { set: bool = false, x1: i32 = 0, x2: i32 = 0, y1: i32 = 0, y2: i32 = 0 };
var zones: [N]Z = [_]Z{.{}} ** N;
/// SET ZONEs the original would have refused (its wrapper then errors).
pub var refused: u32 = 0;

pub fn resetAll() void {
    zones = [_]Z{.{}} ** N;
}

pub fn set(z: i32, x1: i32, y1: i32, x2: i32, y2: i32) void {
    if (z < 1 or z > N or x1 >= x2 or y1 >= y2) {
        refused += 1;
        return;
    }
    zones[@intCast(z - 1)] = .{ .set = true, .x1 = x1, .x2 = x2, .y1 = y1, .y2 = y2 };
}

pub fn zone(n: i32) i32 {
    const s = sprite.spr[@intCast(n & 15)];
    if (!s.on) return 0;
    for (zones, 0..) |z, i| {
        if (!z.set) continue;
        if (s.x >= z.x1 and s.x <= z.x2 and s.y >= z.y1 and s.y <= z.y2) return @intCast(i + 1);
    }
    return 0;
}

pub fn collide(n: i32, w: i32, h: i32) i32 {
    const me = sprite.spr[@intCast(n & 15)];
    var bits: i32 = 0;
    if (!me.on) return 0;
    for (sprite.spr, 0..) |s, k| {
        if (k == @as(usize, @intCast(n & 15)) or !s.on) continue;
        if (s.x >= me.x - w and s.x <= me.x + w and s.y >= me.y - h and s.y <= me.y + h)
            bits |= @as(i32, 1) << @intCast(k);
    }
    return bits;
}
