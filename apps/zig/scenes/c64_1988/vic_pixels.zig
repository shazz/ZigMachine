// --------------------------------------------------------------------------
// One sprite data byte into a plane row: the inner loop of vic_draw.zig's sprite rows.
//
// A byte is 8 hires pixels (1 = the sprite's colour, code 2) or 4 multicolour pairs (01 $D025,
// 10 the sprite's colour, 11 $D026), each pixel 1 or 2 columns wide (X-expansion); 0 bits leave
// the plane alone. The codes per byte are a comptime table, and the stores are single bytes
// through a volatile pointer: the destination column is arbitrary, and a wider store LLVM
// would merge them into lands misaligned half the time (a trap on the board, ~210 cycles).
// --------------------------------------------------------------------------
pub const COLS = 400;
const PAL_X = 504; // PAL: X runs 0..$1F7, then wraps

/// [mcol][byte]: the byte's 8 pixel codes, 0 = transparent, else an index into the colours.
const CODES: [2][256][8]u8 = blk: {
    @setEvalBranchQuota(10000);
    var t: [2][256][8]u8 = undefined;
    for (0..256) |b| for (0..8) |p| {
        t[0][b][p] = if ((b >> (7 - p)) & 1 != 0) 2 else 0;
        t[1][b][p] = (b >> (6 - (p & 6))) & 3;
    };
    break :blk t;
};

inline fn put(dst: [*]u8, i: usize, ink: u8) void {
    @as(*volatile u8, @ptrCast(dst + i)).* = ink;
}

/// A byte wholly inside the plane row (no clipping): the usual case.
pub fn inner(dst: [*]u8, byte: u8, xe2: bool, mcol: bool, colours: *const [4]u8) void {
    const codes = &CODES[@intFromBool(mcol)][byte];
    if (mcol) {
        if (xe2) pairs(4, dst, codes, colours) else pairs(2, dst, codes, colours);
    } else {
        if (xe2) singles(2, dst, codes, colours) else singles(1, dst, codes, colours);
    }
}

inline fn pairs(comptime w: usize, dst: [*]u8, codes: *const [8]u8, colours: *const [4]u8) void {
    inline for (0..4) |k| {
        const v = codes[2 * k];
        if (v != 0) {
            const ink = colours[v];
            inline for (0..w) |e| put(dst, w * k + e, ink);
        }
    }
}

inline fn singles(comptime w: usize, dst: [*]u8, codes: *const [8]u8, colours: *const [4]u8) void {
    const ink = colours[2];
    inline for (0..8) |p| {
        if (codes[p] != 0) inline for (0..w) |e| put(dst, w * p + e, ink);
    }
}

/// The same, column by column, for a byte that crosses a border or the PAL wrap: columns
/// 0..39 show only with the left border open, 360..399 only with the right one.
pub fn edge(row: *[COLS]u8, c0: u32, byte: u8, xe: u32, mcol: bool, colours: *const [4]u8, left_open: bool, right_open: bool) void {
    const codes = &CODES[@intFromBool(mcol)][byte];
    var c = c0;
    for (codes) |v| {
        const ink = colours[v];
        for (0..xe) |_| {
            if (v != 0 and c < COLS and visible(c, left_open, right_open)) row[c] = ink;
            c += 1;
            if (c == PAL_X) c = 0;
        }
    }
}

fn visible(c: u32, left_open: bool, right_open: bool) bool {
    if (c < 40) return left_open; // X < 24: the left border
    if (c >= 360) return right_open; // X >= 344: the right border
    return true;
}
