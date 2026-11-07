// The border colour of a physical row, and where a colour written mid-line first shows.
const vic = @import("vic.zig");
const Out = vic.Out;
const COLS = vic.COLS;

/// Where a border colour written at `cyc` first shows: 8 pixels a cycle, the first new pixel
/// at VICE column 8 * cyc - 103 (1988's wipe), so physical column 8 * cyc - 95.
pub fn splitColumn(cyc: u8) i32 {
    return 8 * @as(i32, cyc) - 95;
}

pub fn row(out: *Out, r: usize, start: u8, split: u8, after: u8) void {
    out.border[r] = start & 15;
    out.split_x[r] = 0;
    if (split == 0) return;
    const x = splitColumn(split);
    if (x <= 0) {
        out.border[r] = after & 15;
    } else if (x < COLS) {
        out.split_x[r] = @intCast(x);
        out.split_c[r] = after & 15;
    }
}
