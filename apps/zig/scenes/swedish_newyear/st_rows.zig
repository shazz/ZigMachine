// --------------------------------------------------------------------------
// One physical line of a part's frame, as st_show.zig and tcb1_mirror.zig read
// it, without the machine (frame.zig needs zigos): the native tests use it too.
// A line shows pixels [lo, hi) of the screen, read from `addr` with its first
// pixel at physical x `x0`; the rest of the line is colour 0.
// --------------------------------------------------------------------------
pub const PW: usize = 400; // frame.PW, checked in st_show.zig
pub const PH: usize = 280; // frame.PH

pub const Row = struct { addr: u32, x0: i32, lo: u16, hi: u16 };
pub const Rows = [PH]?Row;

/// The 16-pixel groups [lo, hi] of `ln` that show, or null when none does.
pub fn groups(ln: Row) ?struct { lo: usize, hi: usize } {
    if (ln.hi <= ln.lo or @as(i32, ln.hi) <= ln.x0) return null;
    const k0: i32 = @max(0, @as(i32, ln.lo) - ln.x0);
    return .{ .lo = @intCast(@divFloor(k0, 16)), .hi = @intCast(@divFloor(@as(i32, ln.hi) - 1 - ln.x0, 16)) };
}
