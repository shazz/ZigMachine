// --------------------------------------------------------------------------
// The credits (8xx 2D..31, 33, 37, 38; Falcon timer $D334, mains $D090..$D268, $AB0C): mode 804,
// Mr Pink's particles. Each 82D..831 takes the NEXT of five name pictures (SH3's 3D lettering,
// 320x240 true colour, Pack-Ice) and a plaque (CODE / GRAPHICS / MUSIC) bottom right. The
// picture is cut into 4x4 blocks; 20 times a frame a random block still to place becomes a
// particle (a pool of 256) that FLIES IN: with r = L - age,
//
//     pos = home + v r + a r^2        v in [-200, 200) px a unit, a_x in [-50, 50), a_y in [-0.5, 9.5)
//
// (16.16 on the Falcon; a unit is 100 ticks, 2 s; L = 0.22 + rand 0.39), so it lands exactly
// on its home at r = 0 and is stamped into the background. 833 shakes the screen sideways (the
// JOLT table on HDB/HDE); 837/838 wipe it to black through a 16x16 mask tiled over the screen,
// eight frames growing (837 a centred square, 838 a cross).
// Here a frame copies the background (landed blocks + plaque) and plots the live particles.
// With the local rip the pictures (four of five: the MUSIC one's Pack-Ice stream does not depack
// yet) and plaques are the original's; otherwise lettered slabs and plaques stand in.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const arena = @import("arena.zig");
const art = @import("art.zig");
const tc = zg.tc;

const W = 320;
const H = 200;
const GW = W / 4;
const GH = H / 4;
const POOL = 256;
// Ticks a time unit (the timer adds 0.01 a call). Fitted to Hatari: a picture assembles in
// ~2.8 s and the 833 jolt lands while it is half built, which 256 particles of 0.22..0.61
// units give with a unit of 80 ticks (1.6 s).
const UNIT = 80;

const NAMES = [5][]const u8{ "DAMO", "SH3", "EARX", "MSG", "MR PINK" }; // stand-ins, in credit order
const PLAQUE = [5]u2{ 0, 1, 0, 2, 0 }; // CODE, GRAPHICS, CODE, MUSIC, CODE
const PLAQUE_TEXT = [3][]const u8{ "CODE", "GRAPHICS", "MUSIC" };

var pic: *[W * H]u16 = undefined; // the picture being assembled
var bg: *[W * H]u16 = undefined; // what has landed, plus the plaque
var todo: *[GW * GH]bool = undefined;

// Only what moved is redrawn (the original kept three dirty lists, one a screen buffer): each of
// the two buffers keeps the blocks it plotted last time (restored from bg next time) and how far
// it has caught up with the landing log. A new picture copies bg whole into both, once.
var landed: *[GW * GH]u16 = undefined;
var n_landed: usize = 0;
const Dirty = struct { x: i16, y: i16 };
const BufState = struct { pixels: ?[*]u16 = null, seen: usize = 0, n: usize = 0, full: bool = true, dirty: [POOL]Dirty = undefined };
var bufs: [2]BufState = .{ .{}, .{} };

fn bufOf(fb: tc.Fb) *BufState {
    const px: [*]u16 = @ptrCast(fb.pixels);
    for (&bufs) |*b| if (b.pixels == px) return b;
    for (&bufs) |*b| if (b.pixels == null) {
        b.pixels = px;
        return b;
    };
    return &bufs[0];
}
var left: u32 = 0;

const Particle = struct { home: u16 = 0, born: u32 = 0, life: u32 = 0, vx: i32 = 0, vy: i32 = 0, ax: i32 = 0, ay: i32 = 0, live: bool = false };
var pool: *[POOL]Particle = undefined;

pub const Credits = struct {
    next: u8 = 0, // which picture the next 82D..831 takes
    t: u32 = 0, // ticks
    seed: u32 = 0x1234,
    wipe: ?u8 = null, // 837/838: the mask frame (0..7)
    cross: bool = false,

    pub fn command(self: *Credits, v: u8, font: []const u8) void {
        switch (v) {
            0x2D...0x31 => {
                self.load(font);
                self.wipe = null;
            },
            0x37, 0x38 => {
                self.wipe = 0;
                self.cross = v == 0x38;
            },
            else => {}, // 833: the jolt (show.zig), the credits run on
        }
    }

    fn load(self: *Credits, font: []const u8) void {
        const k = self.next % 5;
        self.next += 1;
        picture(k, font);
        @memset(bg, 0);
        plaque(PLAQUE[k], font);
        left = 0;
        for (0..GH) |by| for (0..GW) |bx| {
            var any = false;
            for (0..4) |y| for (0..4) |x| {
                any = any or pic[(by * 4 + y) * W + bx * 4 + x] != 0;
            };
            todo[by * GW + bx] = any;
            left += @intFromBool(any);
        };
        for (pool) |*p| p.live = false;
        n_landed = 0;
        for (&bufs) |*b| b.full = true;
    }

    fn rand(self: *Credits) u32 {
        self.seed = self.seed *% 0x10DCD +% 1;
        return self.seed >> 8;
    }

    /// The timer slot: time on, 20 spawn tries, land what has arrived.
    pub fn tick(self: *Credits) void {
        self.t += 1;
        if (self.wipe) |*f| f.* = @min(8, f.* + 1);
        for (0..20) |_| self.spawn();
        for (pool) |*p| if (p.live and self.t >= p.born + p.life) {
            stamp(p.home);
            landed[n_landed] = p.home;
            n_landed += 1;
            p.live = false;
        };
    }

    fn spawn(self: *Credits) void {
        if (left == 0) return;
        const slot = for (pool) |*p| {
            if (!p.live) break p;
        } else return;
        var b = self.rand() % (GW * GH);
        while (!todo[b]) b = (b + 1) % (GW * GH);
        todo[b] = false;
        left -= 1;
        slot.* = .{
            .home = @intCast(b),
            .born = self.t,
            .life = (22 + self.rand() % 39) * UNIT / 100,
            .vx = @as(i32, @intCast(self.rand() % 400)) - 200,
            .vy = @as(i32, @intCast(self.rand() % 400)) - 200,
            .ax = @as(i32, @intCast(self.rand() % 100)) - 50,
            .ay = @as(i32, @intCast(self.rand() % 1000)) - 50, // tenths: -0.5..9.5 -> x 1/100 below
            .live = true,
        };
    }

    pub fn draw(self: *const Credits, fb: tc.Fb, front: tc.Fb) void {
        if (self.wipe) |f| {
            for (&bufs) |*b| b.full = true;
            return wipeDraw(fb, front, f, self.cross);
        }
        const b = bufOf(fb);
        if (b.full) {
            for (0..H) |y| @memcpy(fb.pixels[y * fb.stride ..][0..W], bg[y * W ..][0..W]);
            b.* = .{ .pixels = b.pixels, .seen = n_landed, .full = false };
        } else {
            for (b.dirty[0..b.n]) |d| restore(fb, d.x, d.y);
            for (landed[b.seen..n_landed]) |k| restore(fb, @intCast((k % GW) * 4), @intCast((k / GW) * 4));
            b.seen = n_landed;
        }
        b.n = 0;
        for (pool) |*p| if (p.live) {
            const r: i32 = @as(i32, @intCast(p.born + p.life)) - @as(i32, @intCast(self.t)); // ticks
            const bx: i32 = @intCast((p.home % GW) * 4);
            const by: i32 = @intCast((p.home / GW) * 4);
            const x = bx + @divTrunc(p.vx * r, UNIT) + @divTrunc(p.ax * r * r, UNIT * UNIT);
            const y = by + @divTrunc(p.vy * r, UNIT) + @divTrunc(p.ay * r * r, UNIT * UNIT * 100);
            plot(fb, p.home, x, y);
            b.dirty[b.n] = .{ .x = @intCast(std.math.clamp(x, -8, W)), .y = @intCast(std.math.clamp(y, -8, H)) };
            b.n += 1;
        };
    }
};

// The 4x4 at (x0, y0) from the background (clipped).
fn restore(fb: tc.Fb, x0: i32, y0: i32) void {
    for (0..4) |y| for (0..4) |x| {
        const sx = x0 + @as(i32, @intCast(x));
        const sy = y0 + @as(i32, @intCast(y));
        if (sx < 0 or sy < 0 or sx >= W or sy >= H) continue;
        const i = @as(usize, @intCast(sy)) * W + @as(usize, @intCast(sx));
        fb.pixels[@as(usize, @intCast(sy)) * fb.stride + @as(usize, @intCast(sx))] = bg[i];
    };
}

fn stamp(b: u16) void {
    const bx = (b % GW) * 4;
    const by = (b / GW) * 4;
    for (0..4) |y| for (0..4) |x| {
        const i = (by + y) * W + bx + x;
        if (pic[i] != 0) bg[i] = pic[i];
    };
}

fn plot(fb: tc.Fb, b: u16, x0: i32, y0: i32) void {
    const bx = (b % GW) * 4;
    const by = (b / GW) * 4;
    for (0..4) |y| for (0..4) |x| {
        const sx = x0 + @as(i32, @intCast(x));
        const sy = y0 + @as(i32, @intCast(y));
        if (sx < 0 or sy < 0 or sx >= W or sy >= H) continue;
        const c = pic[(by + y) * W + bx + x];
        if (c != 0) fb.pixels[@as(usize, @intCast(sy)) * fb.stride + @as(usize, @intCast(sx))] = c;
    };
}

// $AB0C: the shown frame, then each 16x16 cell's mask drawn black (frame f of 8, growing).
fn wipeDraw(fb: tc.Fb, front: tc.Fb, f: u8, cross: bool) void {
    for (0..H) |y| @memcpy(fb.pixels[y * fb.stride ..][0..W], front.pixels[y * front.stride ..][0..W]);
    const half: usize = @as(usize, f) + 1; // 1..9: 2..16 px (clamped)
    for (0..H) |y| for (0..W) |x| {
        const cx = x & 15;
        const cy = y & 15;
        const dx = if (cx < 8) 7 - cx else cx - 8;
        const dy = if (cy < 8) 7 - cy else cy - 8;
        const on = if (cross) (dx < half / 2 + 1 or dy < half / 2 + 1) and dx < half and dy < half else dx < half and dy < half;
        if (on and f > 0) fb.pixels[y * fb.stride + x] = 0;
    };
}

// --- the pictures ---

fn picture(k: usize, font: []const u8) void {
    const src = switch (k) {
        0 => art.credit_1,
        1 => art.credit_2,
        2 => art.credit_3,
        3 => art.credit_4,
        else => art.credit_5,
    };
    if (src.len >= W * H * 2) {
        for (0..W * H) |i| pic[i] = art.be16(src, i * 2);
        return;
    }
    // Stand-in: a tilted green slab with the name in pink, outlined.
    @memset(pic, 0);
    const green = tc.rgb565(70, 180, 110);
    const pink = tc.rgb565(230, 160, 190);
    const edge = tc.rgb565(90, 140, 160);
    const name = NAMES[k];
    for (0..H) |y| for (0..W) |x| {
        const sy: i32 = @as(i32, @intCast(y)) - 60 + @divTrunc(@as(i32, @intCast(x)), 4);
        if (x < 30 or x > 290 or sy < 20 or sy > 76) continue;
        const border = x < 34 or x > 286 or sy < 24 or sy > 72;
        var c = if (border) edge else green;
        const lx = (x - 40) / 4;
        const ly: i32 = @divTrunc(sy - 28, 5);
        if (x >= 40 and ly >= 0 and ly < 8 and lx / 8 < name.len) {
            const ch = name[lx / 8];
            if (font.len >= (@as(usize, ch) + 1) * 64 and font[@as(usize, ch) * 64 + @as(usize, @intCast(ly)) * 8 + lx % 8] != 0) c = pink;
        }
        pic[y * W + x] = c;
    };
}

fn plaque(which: u2, font: []const u8) void {
    const src = switch (which) {
        0 => art.plaque_code,
        1 => art.plaque_graphics,
        else => art.plaque_music,
    };
    if (src.len > 6) {
        const w: usize = art.be16(src, 2);
        const h: usize = art.be16(src, 4);
        if (src.len >= 6 + w * h * 2) {
            for (0..h) |y| for (0..w) |x| {
                bg[(H - h + y) * W + W - w + x] = art.be16(src, 6 + (y * w + x) * 2);
            };
            return;
        }
    }
    const s = PLAQUE_TEXT[which];
    const w = s.len * 16 + 8;
    const teal = tc.rgb565(60, 120, 120);
    const pink = tc.rgb565(200, 110, 150);
    for (0..40) |y| for (0..w) |x| {
        const lx = (x -| 4) / 2;
        const ly = (y -| 4) / 4;
        const ch = if (lx / 8 < s.len) s[lx / 8] else ' ';
        const ink = x >= 4 and y >= 4 and ly < 8 and font.len >= (@as(usize, ch) + 1) * 64 and font[@as(usize, ch) * 64 + ly * 8 + lx % 8] != 0;
        bg[(H - 40 + y) * W + W - w + x] = if (ink) pink else teal;
    };
}

test "a particle lands on its home: r = 0 puts it at the block" {
    const p = Particle{ .home = 5, .born = 0, .life = 30, .vx = 150, .vy = -120, .ax = 20, .ay = 300, .live = true };
    const r: i32 = 0;
    try std.testing.expectEqual(@as(i32, 0), @divTrunc(p.vx * r, UNIT) + @divTrunc(p.ax * r * r, UNIT * UNIT));
}

/// The big tables from the arena (once, at init).
pub fn initTables() void {
    pic = arena.take([W * H]u16);
    bg = arena.take([W * H]u16);
    todo = arena.take([GW * GH]bool);
    landed = arena.take([GW * GH]u16);
    pool = arena.take([POOL]Particle);
    for (pool) |*q| q.* = .{};
}
