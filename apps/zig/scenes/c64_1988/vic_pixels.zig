// --------------------------------------------------------------------------
// Sprite pixels: the codes of a data byte, and the keyed CPU copy of a run of expanded pixels.
//
// A byte is 8 hires pixels (1 = the sprite's colour, code 2) or 4 multicolour pairs (01 $D025,
// 10 the sprite's colour, 11 $D026); code 0 is transparent. The copy stores single bytes
// through a volatile pointer: the destination column is arbitrary, and a wider store LLVM
// would merge them into lands misaligned most of the time (a trap on the board, ~210 cycles).
// --------------------------------------------------------------------------
pub const COLS = 400;

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

pub fn codes(mcol: bool, byte: u8) *const [8]u8 {
    return &CODES[@intFromBool(mcol)][byte];
}

/// `n` pixels of `src` onto `dst`, 0s left out.
pub fn keyed(dst: [*]u8, src: [*]const u8, n: usize) void {
    for (0..n) |i| {
        const v = src[i];
        if (v != 0) @as(*volatile u8, @ptrCast(dst + i)).* = v;
    }
}
