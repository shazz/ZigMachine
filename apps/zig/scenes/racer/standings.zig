// --------------------------------------------------------------------------
// RACER: who is ahead. A car that has crossed the finish is ahead of every car that has not; two
// finishers rank by the tick they crossed (then by how far past the line they are); the others
// by their track u. A tie goes to the higher car index, so the player (index 0) loses ties, as in
// the original (`if plyr_u > npc_u then rank - 1`: an equal u does not pass the car).
// Records (best lap, best race) are in RAM only: records.zig is the one place a file would bind
// to once the question of a cart writing a file (Q6) is answered. No ZigOS import.
// --------------------------------------------------------------------------
pub const MAXCARS = 8;

pub fn ahead(a: usize, b: usize, u: []const i32, finish: []const u32) bool {
    const fa = finish[a];
    const fb = finish[b];
    if (fa != 0 and fb != 0 and fa != fb) return fa < fb;
    if (fa != 0 and fb == 0) return true;
    if (fa == 0 and fb != 0) return false;
    if (u[a] != u[b]) return u[a] > u[b];
    return a > b;
}

/// Car indices first to last, into `out`; returns the first `n`.
pub fn order(u: []const i32, finish: []const u32, n: usize, out: *[MAXCARS]u8) []const u8 {
    for (out[0..n], 0..) |*o, i| o.* = @intCast(i);
    for (1..n) |i| {
        const x = out[i];
        var j = i;
        while (j > 0 and ahead(x, out[j - 1], u, finish)) : (j -= 1) out[j] = out[j - 1];
        out[j] = x;
    }
    return out[0..n];
}

/// 1-based place of car `car` among `n`.
pub fn place(car: usize, u: []const i32, finish: []const u32, n: usize) u32 {
    var p: u32 = 1;
    for (0..n) |k| p += @intFromBool(k != car and ahead(k, car, u, finish));
    return p;
}
