// --------------------------------------------------------------------------
// RACER: the minimap, drawn into the top HUD band's right end (28 x 10 pixels at x = 290, y = 1):
// the racing line from above, the longer side of the track along the band, one pixel an AI car in
// its livery, the player 2 x 2 in white. It is a few hundred byte stores a frame and no plane of
// its own (planes are what the board pays for). The band is 12 rows high, so the oval is small;
// a bigger map would have to cover the view. Integer only; the pixel buffer is a parameter, so
// the native test draws into a plain array. No ZigOS import.
// --------------------------------------------------------------------------
const carmodel = @import("carmodel.zig");
const palette = @import("palette.zig");
const trk = @import("trk.zig");

pub const X0 = 290;
pub const Y0 = 1;
pub const W = 28;
pub const H = 10;
pub const MAXPTS = 256;
const LINE_COLOUR: u8 = 16 + 3; // asphalt, light 3

pub const Map = struct {
    pts: [MAXPTS][2]u8 = undefined,
    n: usize = 0,
    swap: bool = false, // the world's x runs along the band (the track is wider than long)
    min: [2]i32 = .{ 0, 0 },
    scale: i64 = 0, // Q16 pixels a world unit

    pub fn init(t: *const trk.Track) Map {
        var m = Map{};
        var lo = [2]i32{ 0x7fff_ffff, 0x7fff_ffff };
        var hi = [2]i32{ -0x7fff_ffff, -0x7fff_ffff };
        for (t.line) |s| {
            for ([2]usize{ 0, 2 }, 0..) |c, i| {
                lo[i] = @min(lo[i], s.pos[c]);
                hi[i] = @max(hi[i], s.pos[c]);
            }
        }
        const dx: i64 = @max(hi[0] - lo[0], 1);
        const dz: i64 = @max(hi[1] - lo[1], 1);
        m.swap = dx > dz;
        const long = @max(dx, dz);
        const short = @min(dx, dz);
        m.scale = @min(@divTrunc(@as(i64, W - 3) << 32, long), @divTrunc(@as(i64, H - 3) << 32, short));
        m.min = lo;
        m.n = @min(t.line.len, MAXPTS);
        for (t.line[0..m.n], 0..) |s, i| m.pts[i] = m.to(s.pos);
        return m;
    }

    /// World position (Q16) -> pixel inside the map's box, relative to (X0, Y0).
    pub fn to(self: *const Map, pos: [3]i32) [2]u8 {
        const a: i64 = @as(i64, pos[0] - self.min[0]) * self.scale >> 32;
        const b: i64 = @as(i64, pos[2] - self.min[1]) * self.scale >> 32;
        const x, const y = if (self.swap) .{ a, b } else .{ b, a };
        return .{ @intCast(@min(x + 1, W - 1)), @intCast(@min(y + 1, H - 1)) };
    }

    /// Draw the whole map: background, the line, then `cars` (AI cars first, the player's position last).
    pub fn draw(self: *const Map, px: []u8, stride: usize, cars: []const [3]i32) void {
        for (0..H) |y| @memset(px[(Y0 + y) * stride + X0 ..][0..W], palette.PAPER);
        for (self.pts[0..self.n]) |p| put(px, stride, p, LINE_COLOUR);
        for (cars[1..], 0..) |c, k| put(px, stride, self.to(c), @intCast(16 + (carmodel.RAMP_LIVERY + k % carmodel.LIVERIES) * 8 + 6));
        const p = self.to(cars[0]);
        for ([2]u8{ 0, 1 }) |dy| for ([2]u8{ 0, 1 }) |dx| put(px, stride, .{ @min(p[0] + dx, W - 1), @min(p[1] + dy, H - 1) }, palette.INK);
    }
};

fn put(px: []u8, stride: usize, p: [2]u8, c: u8) void {
    px[(Y0 + p[1]) * stride + X0 + p[0]] = c;
}
