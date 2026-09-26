// An indexed image as tools/private_tools/swedish_newyear_assets.py stores it:
// 4 or 8 bits a pixel of LOCAL index (0 = transparent), and a LUT from local
// index to the scene's global colour id (gid, see frame.zig).
pub const NONE: u16 = 0xFFFF; // "transparent here": nothing is drawn

pub const Img = struct {
    w: i32,
    h: i32,
    bits: u8,
    data: []const u8,
    lut: []const u16,

    /// The gid at (x, y), or NONE where the image is transparent or (x, y) is
    /// outside it -- every CODEF drawImage clips to its source rectangle.
    pub fn at(self: *const Img, x: i32, y: i32) u16 {
        if (x < 0 or y < 0 or x >= self.w or y >= self.h) return NONE;
        const i = self.local(@intCast(x), @intCast(y));
        return if (i == 0) NONE else self.lut[i];
    }

    pub fn local(self: *const Img, x: usize, y: usize) u8 {
        const w: usize = @intCast(self.w);
        if (self.bits == 8) return self.data[y * w + x];
        const b = self.data[y * ((w + 1) / 2) + x / 2];
        return if (x & 1 == 0) b & 0x0F else b >> 4;
    }
};

/// floor() of an f64 into i32, saturating so a far-off sample never traps.
pub fn ifloor(v: f64) i32 {
    const f = @floor(v);
    if (!(f > -1.0e9)) return -1_000_000_000;
    if (f > 1.0e9) return 1_000_000_000;
    return @intFromFloat(f);
}
