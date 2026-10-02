// The 16 colour registers as a part keeps them in memory (movem.l to $FF8240).
const st = @import("../swedish_newyear/st.zig");

pub fn at(r: *const st.Ram, a: u32) [16]u16 {
    var pal: [16]u16 = undefined;
    for (&pal, 0..) |*c, i| c.* = r.w(a + 2 * @as(u32, @intCast(i)));
    return pal;
}
