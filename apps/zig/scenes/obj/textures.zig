// --------------------------------------------------------------------------
// OBJ demo: the two 128x128 textures CHISEL's AFFINE reads (cart RAM, 32 KB,
// built once at init with integers; U_MASK = V_MASK = 127, so they wrap).
//   WALL    LearnOpenGL's wall.jpg (learnopengl.com/img/textures/wall.jpg), cut
//           to 128x128 and 64 colours offline (assets/obj/wall.idx: indices
//           1..64; wall.pal: their RGB), copied in
//   NATRIUM RNO's env map from Natrium (ENVMAP's), 13 grey levels at 1..13
//   ENV     a chrome sphere map: sky (1..32) above the horizon, ground
//           (33..64) below, each brightest at the horizon, and a sun disc up left
//           (kept, not used: ENVMAP reads NATRIUM)
// The palettes that go with them are in palette.zig (texRamps, envRamp).
// No ZigOS import: obj/tests.zig tests it natively.
// --------------------------------------------------------------------------
pub const SIZE: usize = 128;
pub const BYTES: usize = SIZE * SIZE;
pub const MASK: u16 = SIZE - 1;

/// ENVMAP's map: RNO's own sphere map from Natrium ($52492, 128x128, levels 0..12),
/// read through palette.zig's 13 greys at 1..13 (the ST's 000/333/555/777 it dithered).
pub const NATRIUM = @embedFile("../../assets/screens/rno_natrium/env_tex.bin");

pub fn natrium(t: []u8) void {
    for (t[0..BYTES], NATRIUM[0..BYTES]) |*d, s| d.* = 1 + s;
}

pub const WALL = @embedFile("../../assets/obj/wall.idx");
pub const WALL_PAL = @embedFile("../../assets/obj/wall.pal");

pub fn wall(t: []u8) void {
    @memcpy(t[0..BYTES], WALL[0..BYTES]);
}

pub fn tiles(t: []u8) void {
    for (0..SIZE) |y| for (0..SIZE) |x| {
        const gold = ((x >> 4) ^ (y >> 4)) & 1;
        const cx: i32 = @intCast(x & 15);
        const cy: i32 = @intCast(y & 15);
        // 0 at the cell's centre, 7 on its rim (the larger of the two axes)
        const d = @max(@abs(2 * cx - 15), @abs(2 * cy - 15)) >> 1;
        t[y * SIZE + x] = @intCast(1 + 32 * gold + 31 - 4 * d);
    };
}

pub fn env(t: []u8) void {
    for (0..SIZE) |y| for (0..SIZE) |x| {
        const yi: i32 = @intCast(y);
        const dx: i32 = @as(i32, @intCast(x)) - 44;
        const dy: i32 = yi - 34;
        const sun = isqrt(@intCast(dx * dx + dy * dy)) < 9;
        // the horizon at row 64 (v = 0.5: a normal pointing straight at the eye)
        const ramp: i32 = if (yi < 64) @divTrunc(yi * 31, 63) else 31 - @divTrunc((yi - 64) * 31, 63);
        t[y * SIZE + x] = if (sun) 32 else @intCast(1 + @as(i32, if (yi < 64) 0 else 32) + ramp);
    };
}

fn isqrt(n: u32) u32 {
    var r: u32 = 0;
    while ((r + 1) * (r + 1) <= n) r += 1;
    return r;
}
