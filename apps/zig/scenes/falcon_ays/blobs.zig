// --------------------------------------------------------------------------
// The blobs (8xx 0B..11, 21; Falcon mains $346C..$38BE -> $39DC, timer $3C7E): mode 805,
// 160x100. Two windows on ONE 320x200 height field (0..127) are added and the sum picks a
// colour:
//
//     pixel(x, y) = LUT[ F[a + y*sa + x] + F[b + y*sb + x] ]
//
// The Falcon code loads both read pointers from the same variable ($215B4C), so every variant
// sums one field at two offsets: either the field as ripped or its 180-degree turn (the init
// stores both). a and b walk four 512-entry Lissajous paths (exact sine sums, generated here);
// the timer steps both one entry every 3 ticks. The rows advance 160 entries plus the variant's
// extra BYTES / 2 (d4, d5: 320 = straight; 300 shears the window 10 px a row, 318/322 one px):
// (the "light streak" variants). The LUTs are black up to a sum of 128 and white near 255: the
// colour only shows where the two copies overlap, a metaball threshold. 811 adds a 6-line tear
// band; 821 swaps in the inverted LUT. Per pixel: two byte loads, an add, a LUT load, one u32
// store (the pixel pair). Notes: prototypes/falcon_ays_re/notes_blobs_credits.txt.
//
// The field and LUTs are the original's in a build with the local rip (art.zig); otherwise
// five generated spotlight shapes and ramps from the decoded LUT colours stand in.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const arena = @import("arena.zig");
const art = @import("art.zig");
const fixtrig = zg.fixtrig;

pub const FW = 320;
pub const FH = 200;
pub const VW = 160;
pub const VH = 100;
const FIELD = FW * FH;
const PATH_LEN = 512;
const TEAR_LEN = 1024;

// [0] as ripped ($1D7342), [1] turned 180 ($1F6742); 1 KB of zeros past each: a sheared window
// (row stride 328) reads past the field, into what followed it on the Falcon.
var fields: *[2][FIELD + 1024]u8 = undefined;
var paths: *[4][PATH_LEN]u16 = undefined;
var tear_rows: [TEAR_LEN]u8 = undefined;

pub const Lut = enum(u8) { purple, cyan, red, gold, inverted, green };
const LUTS = 6;
var luts: *[LUTS][256]u32 = undefined;

const Variant = struct { field: u1, pa: u16, pb: u16, path_a: u2, path_b: u2, sa: u16, sb: u16, lut: Lut };

// 80B..810 (notes: the variants table), in 8xx order.
const VARIANTS = [6]Variant{
    .{ .field = 1, .pa = 0x154, .pb = 0x172, .path_a = 2, .path_b = 1, .sa = 320, .sb = 320, .lut = .purple },
    .{ .field = 0, .pa = 0x2C4, .pb = 0x064, .path_a = 3, .path_b = 2, .sa = 300, .sb = 320, .lut = .cyan },
    .{ .field = 0, .pa = 0x1CA, .pb = 0x34C, .path_a = 2, .path_b = 3, .sa = 320, .sb = 320, .lut = .red },
    .{ .field = 1, .pa = 0x238, .pb = 0x2A2, .path_a = 3, .path_b = 1, .sa = 318, .sb = 322, .lut = .green },
    .{ .field = 1, .pa = 0x22C, .pb = 0x232, .path_a = 0, .path_b = 1, .sa = 312, .sb = 328, .lut = .gold },
    .{ .field = 0, .pa = 0x3C0, .pb = 0x064, .path_a = 0, .path_b = 1, .sa = 312, .sb = 328, .lut = .purple },
};

/// Build the fields, paths, tear table and LUTs (once, at init; integer only).
pub fn init() void {
    paths = arena.take([4][PATH_LEN]u16);
    luts = arena.take([LUTS][256]u32);
    fields = arena.take([2][FIELD + 1024]u8);
    frozen = arena.take([VW * VH]u8);
    @memset(&fields[0], 0);
    if (art.blob_field.len == FIELD) @memcpy(fields[0][0..FIELD], art.blob_field) else genField(fields[0][0..FIELD]);
    @memset(&fields[1], 0);
    for (0..FIELD) |i| fields[1][i] = fields[0][FIELD - 1 - i];
    genPaths();
    for (0..TEAR_LEN) |i| {
        const p: u32 = @as(u32, @intCast(i)) << 22; // 1024 steps a turn
        const s = fixtrig.sin(p) + fixtrig.sin(p *% 4);
        tear_rows[i] = if (art.blob_tear.len == 2048) @intCast(art.be16(art.blob_tear, i * 2) / 320) else @intCast(45 + @divFloor(s * 45, 2 * fixtrig.ONE));
    }
    for (0..LUTS) |l| for (0..256) |i| {
        const c = if (art.blob_luts.len >= LUT_OFF[5] + 512) art.be16(art.blob_luts, LUT_OFF[l] + i * 2) else genLut(@enumFromInt(l), i);
        luts[l][i] = @as(u32, c) | @as(u32, c) << 16;
    };
}

// Byte offsets of each LUT in art.blob_luts (DATA $4992C..): cyan $4992C, gold $49D2C,
// purple $4A12C, red $4A52C, inverted $4A92C, green $4AD2C; in Lut order.
const LUT_OFF = [LUTS]usize{ 0x800, 0x000, 0xC00, 0x400, 0x1000, 0x1400 };

pub const Blobs = struct {
    v: Variant = VARIANTS[0],
    tear: bool = false,
    state: u8 = 0, // the variant the Falcon's state word holds (0: another part ran)
    ticks: u8 = 0,
    tear_i: u16 = 0,

    /// 8xx 0B..10 set a variant (its phases restart); 11 adds the tear; 21 inverts the LUT.
    pub fn command(self: *Blobs, cmd: u8) void {
        switch (cmd) {
            // The Falcon re-inits a variant only when its state word ($2EEB26) says another part
            // ran since: 813's freeze and the flashes leave it, so 80E after 813 goes on moving.
            0x0B...0x10 => if (self.state != cmd) {
                self.v = VARIANTS[cmd - 0x0B];
                self.tear = false;
                self.state = cmd;
            },
            0x11 => self.tear = true,
            0x21 => self.v.lut = .inverted,
            else => {},
        }
    }

    /// The timer slot ($3C7E, 100 Hz): every 3rd call both windows move one path entry (2 bytes).
    pub fn tick(self: *Blobs) void {
        self.tear_i = (self.tear_i + 1) % TEAR_LEN;
        self.ticks += 1;
        if (self.ticks < 3) return;
        self.ticks = 0;
        self.v.pa = (self.v.pa + 2) & 0x3FF;
        self.v.pb = (self.v.pb + 2) & 0x3FF;
    }

    /// 160 pixel pairs a row into rows 0..99 of a 320-wide buffer (mode 805 doubles the lines).
    pub fn draw(self: *const Blobs, fb: zg.tc.Fb) void {
        const lut = &luts[@intFromEnum(self.v.lut)];
        const f = &fields[self.v.field];
        var a: usize = paths[self.v.path_a][self.v.pa >> 1];
        var b: usize = paths[self.v.path_b][self.v.pb >> 1];
        for (0..VH) |y| {
            const row: [*]u32 = @ptrCast(@alignCast(fb.pixels + y * fb.stride));
            const ra = f[a..][0..VW];
            const rb = f[b..][0..VW];
            for (0..VW) |x| row[x] = lut[@as(usize, ra[x]) + rb[x]];
            a += 160 + self.v.sa / 2;
            b += 160 + self.v.sb / 2;
        }
        if (self.tear) tearBand(fb, tear_rows[self.tear_i]);
    }
};

// 822 / 836 ($6CA6 / $6CC8): the blob sums frozen at the command, then pushed 6 a tick to the
// top (822: white, or 80F's orange "beams") or the bottom (836: black) of the running LUT.
var frozen: *[VW * VH]u8 = undefined;

pub const Fade = struct {
    up: bool,
    lut: Lut,

    pub fn start(b: *const Blobs, up: bool) Fade {
        const f = &fields[b.v.field];
        var a: usize = paths[b.v.path_a][b.v.pa >> 1];
        var c: usize = paths[b.v.path_b][b.v.pb >> 1];
        for (0..VH) |y| {
            for (0..VW) |x| frozen[y * VW + x] = @intCast(@min(255, @as(u16, f[a + x]) + f[c + x]));
            a += 160 + b.v.sa / 2;
            c += 160 + b.v.sb / 2;
        }
        return .{ .up = up, .lut = b.v.lut };
    }

    pub fn tick(self: *const Fade) void {
        for (frozen) |*i| {
            if (self.up and i.* <= 0xF8) i.* += 6;
            if (!self.up and i.* >= 6) i.* -= 6;
        }
    }

    pub fn draw(self: *const Fade, fb: zg.tc.Fb) void {
        const lut = &luts[@intFromEnum(self.lut)];
        for (0..VH) |y| {
            const row: [*]u32 = @ptrCast(@alignCast(fb.pixels + y * fb.stride));
            for (0..VW) |x| row[x] = lut[frozen[y * VW + x]];
        }
    }
};

// 811's band ($45C4): six rows from `top` shifted left in place by 2, 6, 14, 8, 4, 2 pixels.
fn tearBand(fb: zg.tc.Fb, top: u8) void {
    const shifts = [6]usize{ 2, 6, 14, 8, 4, 2 };
    for (shifts, 0..) |s, k| {
        const y = @as(usize, top) + k;
        if (y >= VH) break;
        const row: [*]u32 = @ptrCast(@alignCast(fb.pixels + y * fb.stride));
        std.mem.copyForwards(u32, row[0 .. VW - s], row[s..VW]);
    }
}

// The four paths, exact: theta = 2 pi i / 512, S(k) = sin(k theta), entry = y * 320 + x.
fn genPaths() void {
    for (0..PATH_LEN) |i| {
        const t: u32 = @as(u32, @intCast(i)) << 23;
        const s = struct {
            fn f(th: u32, k: u32, amp: i32) i32 {
                return @divFloor(fixtrig.sin(th *% k) * amp, fixtrig.ONE);
            }
        }.f;
        const xy = [4][2]i32{
            .{ 80 + s(t, 2, 40) + s(t, 8, 40), 50 + s(t, 1, 25) + s(t, 4, 25) },
            .{ 80 + s(t, 1, 40) + s(t, 4, 40), 50 + s(t, 2, 25) + s(t, 8, 25) },
            .{ 80 + s(t, 1, 80), 50 + s(t, 2, 25) + s(t, 4, 25) },
            .{ 80 + s(t, 1, 40) + s(t, 2, 40), 50 + s(t, 4, 50) },
        };
        for (0..4) |p| {
            const x: u32 = @intCast(std.math.clamp(xy[p][0], 0, 160));
            const y: u32 = @intCast(std.math.clamp(xy[p][1], 0, 99));
            paths[p][i] = @intCast(y * FW + x);
        }
    }
}

// --- the stand-ins (no ripped data) ---

// Five spotlight shapes along the bottom (the measured peaks of DATA $38F2C): a bright
// elliptical core, a glow three times taller than wide fading upward. Integer only.
fn genField(f: *[FIELD]u8) void {
    @memset(f, 0);
    const cx = [5]i32{ 66, 110, 162, 213, 265 };
    const cy = [5]i32{ 163, 162, 160, 157, 151 };
    const r = [5]i32{ 7, 7, 8, 12, 15 };
    const peak = [5]i32{ 28, 70, 108, 150, 170 };
    for (0..5) |k| {
        var y: i32 = 0;
        while (y < FH) : (y += 1) {
            var x: i32 = 0;
            while (x < FW) : (x += 1) {
                const dx = x - cx[k];
                const dy = y - cy[k];
                const ry: i32 = if (dy < 0) r[k] * 4 else r[k] * 2;
                const q = @divTrunc(dx * dx * 256, r[k] * r[k] * 4) + @divTrunc(dy * dy * 256, ry * ry);
                if (q >= 1024) continue;
                const v = @divTrunc(peak[k] * (1024 - q) * (1024 - q), 1024 * 1024);
                const i: usize = @intCast(y * FW + x);
                f[i] = @intCast(@min(127, @as(i32, f[i]) + v));
            }
        }
    }
}

// Piecewise ramps through the decoded LUT colours: black up to 128, then the colour, then white.
fn genLut(l: Lut, i: usize) u16 {
    const stops: [3]u32 = switch (l) {
        .purple => .{ 0x501C98, 0xE060C0, 0xE8B0D8 },
        .cyan => .{ 0x104878, 0x40B0E0, 0xA0E8F8 },
        .red => .{ 0x801810, 0xF84028, 0xF8C4A8 },
        .gold => .{ 0x704010, 0xE8A030, 0xF8E090 },
        .green => .{ 0x104820, 0x30C060, 0xA0F0C0 },
        .inverted => return if (i < 128) 0xFFFF else if (i < 255) ramp(0xF0D0D8, 0xF08498, i - 128, 127) else 0,
    };
    if (i <= 128) return 0;
    const t = i - 128; // 1..127
    if (t < 32) return ramp(0, stops[0], t, 32);
    if (t < 64) return ramp(stops[0], stops[1], t - 32, 32);
    if (t < 96) return ramp(stops[1], stops[2], t - 64, 32);
    return ramp(stops[2], 0xFFFFFF, t - 96, 31);
}

fn ramp(c0: u32, c1: u32, t: usize, n: usize) u16 {
    var c: [3]u8 = undefined;
    for (0..3) |k| {
        const sh: u5 = @intCast(16 - 8 * k);
        const a: i32 = @intCast((c0 >> sh) & 255);
        const b: i32 = @intCast((c1 >> sh) & 255);
        c[k] = @intCast(a + @divTrunc((b - a) * @as(i32, @intCast(@min(t, n))), @as(i32, @intCast(n))));
    }
    return zg.tc.rgb565(c[0], c[1], c[2]);
}

test "the generated field stays in 0..127, so two layers index a 256-entry LUT" {
    genField(fields[0][0..FIELD]);
    var hi: u8 = 0;
    for (fields[0][0..FIELD]) |v| hi = @max(hi, v);
    try std.testing.expect(hi == 127);
}

test "the paths keep a 160x100 window inside the 320x200 field" {
    genPaths();
    for (paths) |p| for (p) |o| try std.testing.expect(o % FW <= 160 and o / FW <= 99);
}

test "LUTs: black up to a sum of 128, white at the top (the metaball threshold)" {
    try std.testing.expectEqual(@as(u16, 0), genLut(.purple, 128));
    try std.testing.expect(genLut(.purple, 160) != 0);
    try std.testing.expectEqual(@as(u16, 0xFFFF), genLut(.red, 254));
    try std.testing.expectEqual(@as(u16, 0xFFFF), genLut(.inverted, 10));
}
