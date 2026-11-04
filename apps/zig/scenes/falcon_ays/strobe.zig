// --------------------------------------------------------------------------
// "reservoirgods" (8xx 14/15; Falcon timer $49E6, mains $4946/$4968 -> $498A): mode 804, a
// moire flash. A halftone-dot picture of the letters (320x65 bytes, 0..127) and a radial
// halftone field (read 640 wide) swaying sideways on a 1024-entry path are added and looked up
// in a 512-entry LUT (black to 256, black -> red -> white to 383, then white) whose base starts
// 125 entries up and falls 5 a tick: the letters flash out as moire and are black after 25
// ticks. Every 814/815 restarts the flash, so the alternating commands strobe on the beat.
//     pixel(x, y) = LUT[base + letters[x, 8 + y] + field[x + sway, y]]     lines 75..125
// With the local rip the letters, field, path and LUT are the original's; otherwise the system
// font through a dot screen, a generated field, a sine sway and ramps stand in.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const arena = @import("arena.zig");
const art = @import("art.zig");
const tc = zg.tc;

const W = 320;
const LH = 65;
const FW = 640;
const FH = 65;
const ROWS = 51;
const TOP = 75;

// The ripped letters and field are read where they are embedded (no copy: cart RAM is tight).
var letters: *const [W * LH]u8 = undefined;
var field: *const [FW * FH]u8 = undefined;
var sway: [1024]u16 = undefined;
var lut: [512]u16 = undefined;

pub fn init(font: []const u8) void {
    if (art.rg_letters.len == W * LH) {
        letters = @ptrCast(art.rg_letters.ptr);
    } else {
        const l = arena.take([W * LH]u8);
        genLetters(l, font);
        letters = l;
    }
    if (art.rg_field.len >= FW * FH) {
        field = @ptrCast(art.rg_field.ptr);
    } else {
        const f = arena.take([FW * FH]u8);
        genField(f);
        field = f;
    }
    for (0..1024) |i| sway[i] = if (art.rg_sway.len == 2048) art.be16(art.rg_sway, i * 2) else genSway(i);
    for (0..512) |i| lut[i] = if (art.rg_lut.len == 1024) art.be16(art.rg_lut, i * 2) else genLut(i);
}

pub const Strobe = struct {
    base: u16 = 125,
    pos: u16 = 0,

    /// 814 / 815: the flash starts again (the walk goes on).
    pub fn restart(self: *Strobe) void {
        self.base = 125;
    }

    pub fn tick(self: *Strobe) void {
        self.base -|= 5;
        self.pos = (self.pos + 1) & 1023;
    }

    pub fn draw(self: *const Strobe, fb: tc.Fb) void {
        const s = @min(sway[self.pos], FW - W);
        for (0..ROWS) |y| {
            const l = letters[(8 + y) * W ..][0..W];
            const f = field[y * FW + s ..][0..W];
            const row = fb.pixels + (TOP + y) * fb.stride;
            for (0..W) |x| row[x] = lut[@min(511, self.base + @as(u16, l[x]) + f[x])];
        }
    }
};

// --- stand-ins ---

fn dot(x: usize, y: usize, level: u32) bool {
    const cx = @as(i32, @intCast(x % 4)) * 2 - 3;
    const cy = @as(i32, @intCast(y % 4)) * 2 - 3;
    return @as(u32, @intCast(cx * cx + cy * cy)) * 128 < level * 18;
}

// "reservoirgods" in the system font, 24x48 a letter, through a dot screen: 127 on the dots.
fn genLetters(out: *[W * LH]u8, font: []const u8) void {
    @memset(out, 0);
    for ("reservoirgods", 0..) |ch, k| for (0..48) |y| for (0..24) |x| {
        if (font.len < (@as(usize, ch) + 1) * 64) continue;
        if (font[@as(usize, ch) * 64 + (y / 6) * 8 + x / 3] == 0) continue;
        const px = 4 + k * 24 + x;
        if (px < W and dot(px, y, 110)) out[(10 + y) * W + px] = 127;
    };
}

// Rings of dots, brighter toward the middle.
fn genField(out: *[FW * FH]u8) void {
    for (0..FH) |y| for (0..FW) |x| {
        const dx: i32 = @as(i32, @intCast(x)) - 320;
        const dy: i32 = @as(i32, @intCast(y)) - 32;
        const r: u32 = @intCast(dx * dx + dy * dy * 4);
        const level: u32 = 127 -| r / 900;
        out[y * FW + x] = if (dot(x, y, level)) 127 else 0;
    };
}

fn genSway(i: usize) u16 {
    const s = zg.fixtrig.sin(@as(u32, @intCast(i)) << 22);
    return @intCast(160 + @divFloor(s * 158, zg.fixtrig.ONE));
}

fn genLut(i: usize) u16 {
    if (i <= 256) return 0;
    if (i >= 384) return 0xFFFF;
    const t: u32 = @intCast(i - 256); // 1..127
    if (t < 64) return tc.rgb565(@intCast(t * 4), @intCast(t / 2), 0);
    return tc.rgb565(255, @intCast(32 + (t - 64) * 3), @intCast((t - 64) * 4));
}
