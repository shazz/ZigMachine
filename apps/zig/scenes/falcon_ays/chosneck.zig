// --------------------------------------------------------------------------
// The "chosneck" logo (8xx 08, 16, 12; Falcon timer $30A8, mains $2CC4, $4B10, $3E1C): mode 805.
//   808  a band of 42 rows x 160 at row 29: idx = flareA[x + oA] + flareB[x + oB] + logo[x],
//        then a 256-entry LUT (black below 64, brown -> gold -> white). The two flares are
//        frames of a pre-rendered rotating six-point star (12 frames, 320x43 bytes, 0..63), one
//        counting up and one down every 4 ticks, sliding sideways on a 1024-entry offset path
//        (78 + 26.3 (sin t + sin 2t + sin 4t)), 300 entries apart. A flare alone stays black:
//        the logo (0/127) only lights where a flare passes, and two flares meeting glow.
//   816  a feedback blur of that band: back = the shown frame, each pixel averaged with its
//        right neighbour (the outro smear).
//   812  a zoom feedback: each pixel pair of the next frame is a pair of the shown one through
//        a 1.25x zoom map whose rows the RGB path read doubled, past the 100-line picture
//        (into what earlier parts left below it): the green streak that slides down.
// With the local rip the flare frames, the logo and the LUT are the original's; otherwise a
// generated star, the system font and a ramp stand in. The offset path is generated (exact).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const arena = @import("arena.zig");
const art = @import("art.zig");
const accents = @import("accents.zig");
const tc = zg.tc;
const fixtrig = zg.fixtrig;

const FW = 320; // flare frame width
const FH = 43;
const FRAMES = 12;
const LW = 160;
const LH = 44;
const BAND = 42;
const ROW0 = 29; // the band's first row in the 160x100 picture

// The ripped frames and logo are read where they are embedded (no copy: cart RAM is tight);
// only a stand-in is generated into the arena.
var flares: *const [FRAMES][FW * FH]u8 = undefined;
var logo: *const [LW * LH]u8 = undefined;
var offsets: [1024]u16 = undefined;
var lut: [256]u32 = undefined;

pub fn init(font: []const u8) void {
    if (art.chos_flares.len == FRAMES * FW * FH) {
        flares = @ptrCast(art.chos_flares.ptr);
    } else {
        const f = arena.take([FRAMES][FW * FH]u8);
        for (0..FRAMES) |k| genFlare(&f[k], k);
        flares = f;
    }
    if (art.chos_logo.len >= LW * LH) {
        logo = @ptrCast(art.chos_logo.ptr);
    } else {
        const l = arena.take([LW * LH]u8);
        genLogo(l, font);
        logo = l;
    }
    for (0..1024) |i| {
        const t: u32 = @as(u32, @intCast(i)) << 22;
        const s = fixtrig.sin(t) + fixtrig.sin(t *% 2) + fixtrig.sin(t *% 4);
        offsets[i] = if (art.chos_offsets.len == 2048) art.be16(art.chos_offsets, i * 2) else @intCast(78 + @divFloor(s * 263, 10 * fixtrig.ONE));
    }
    for (0..256) |i| {
        const c = if (art.chos_lut.len >= 512) art.be16(art.chos_lut, i * 2) else genLut(i);
        lut[i] = @as(u32, c) | @as(u32, c) << 16;
    }
}

pub const Chosneck = struct {
    k1: u8 = 0,
    k2: u8 = 0,
    p1: u16 = 0,
    p2: u16 = 300,
    ticks: u8 = 0,

    /// The timer slot ($30A8).
    pub fn tick(self: *Chosneck) void {
        self.p1 = (self.p1 + 1) & 1023;
        self.p2 = (self.p2 + 1) & 1023;
        self.ticks += 1;
        if (self.ticks < 4) return;
        self.ticks = 0;
        self.k1 = (self.k1 + 1) % FRAMES;
        self.k2 = (self.k2 + FRAMES - 1) % FRAMES;
    }

    pub fn draw(self: *const Chosneck, fb: tc.Fb) void {
        clearPairs(fb);
        const a = &flares[self.k1];
        const b = &flares[self.k2];
        const oa = offsets[self.p1];
        const ob = offsets[self.p2];
        for (0..BAND) |r| {
            const row: [*]u32 = @ptrCast(@alignCast(fb.pixels + (ROW0 + r) * fb.stride));
            const ra = a[r * FW + oa ..][0..LW];
            const rb = b[r * FW + ob ..][0..LW];
            const rl = logo[(r + 1) * LW ..][0..LW];
            for (0..LW) |x| row[x] = lut[@as(usize, ra[x]) + rb[x] + rl[x]];
        }
    }
};

// Mode 805 shows rows 0..99; the band's picture is black around it.
fn clearPairs(fb: tc.Fb) void {
    for (0..100) |y| {
        if (y >= ROW0 and y < ROW0 + BAND) continue;
        const row: [*]u32 = @ptrCast(@alignCast(fb.pixels + y * fb.stride));
        @memset(row[0..LW], 0);
    }
}

/// 816 ($4B10): the band from the shown frame, each pixel averaged with its right neighbour.
pub fn blur(dst: tc.Fb, src: tc.Fb) void {
    accents.average(dst, src, ROW0, ROW0 + BAND);
}

/// 812 ($3E1C, RGB path): pair (x, y) of the next frame = pair (zx, zy) of the shown one, a
/// 1.25x zoom (columns 17..144) whose source rows were read doubled: 20..178, past row 99.
pub fn zoom(dst: tc.Fb, src: tc.Fb) void {
    for (0..100) |y| {
        const sy = 2 * (10 + y * 4 / 5);
        const s: [*]const u32 = @ptrCast(@alignCast(src.pixels + sy * src.stride));
        const d: [*]u32 = @ptrCast(@alignCast(dst.pixels + y * dst.stride));
        for (0..LW) |x| d[x] = s[17 + x * 127 / 159];
    }
}

// --- stand-ins ---

// A six-point star (three lines through the centre, rotated 5 degrees a frame), 0..63.
fn genFlare(f: *[FW * FH]u8, k: usize) void {
    const base: u32 = @intCast(k * (0x1_0000_0000 / 72));
    for (0..FH) |y| for (0..FW) |x| {
        const dx: i32 = @as(i32, @intCast(x)) - 160;
        const dy: i32 = (@as(i32, @intCast(y)) - 21) * 2;
        var best: i32 = 0;
        for (0..3) |l| {
            const a = base +% @as(u32, @intCast(l)) * (0x1_0000_0000 / 6);
            const perp: i32 = @intCast(@abs(@divFloor(dx * fixtrig.sin(a) - dy * fixtrig.cos(a), fixtrig.ONE)));
            const along: i32 = @intCast(@abs(@divFloor(dx * fixtrig.cos(a) + dy * fixtrig.sin(a), fixtrig.ONE)));
            const v = 63 - perp * 8 - @divTrunc(along, 3);
            best = @max(best, v);
        }
        const r2 = dx * dx + dy * dy;
        const glow: i32 = 63 - @divTrunc(r2, 40);
        f[y * FW + x] = @intCast(std.math.clamp(@max(best, glow), 0, 63));
    };
}

// "chosneck" in the system font, 20x40 a letter (scaled 2.5x5), ink 127.
fn genLogo(logo_out: *[LW * LH]u8, font: []const u8) void {
    @memset(logo_out, 0);
    for ("chosneck", 0..) |ch, k| for (0..40) |y| for (0..20) |x| {
        if (font.len < (@as(usize, ch) + 1) * 64) continue;
        if (font[@as(usize, ch) * 64 + (y / 5) * 8 + x * 2 / 5] != 0) logo_out[(2 + y) * LW + k * 20 + x] = 127;
    };
}

fn genLut(i: usize) u16 {
    if (i < 64) return 0;
    const t: u32 = @intCast(i);
    if (t < 128) return tc.rgb565(@intCast(80 + (t - 64) * 152 / 64), @intCast(30 + (t - 64) * 146 / 64), @intCast(10 + (t - 64) * 62 / 64));
    if (t < 160) return tc.rgb565(@intCast(232 + (t - 128) * 23 / 32), @intCast(176 + (t - 128) * 79 / 32), @intCast(72 + (t - 128) * 183 / 32));
    return 0xFFFF;
}
