// --------------------------------------------------------------------------
// The flames (8xx 17, 18, 19, 1C, 34, 35; Falcon timer $527C, mains $4D6E..$5A96): mode 804, an
// OFFSET MAP. A 256x256 texture (a photographed fireball, 255 colours; or its halftone twin, 64
// greys) is read through a 320x150 map of u16 = v<<8 | u, plus an offset that walks a
// 1024-entry path (one entry a 100 Hz timer tick, ~10 s a lap):
//
//     pixel(x, y) = tex[map[y*320 + x] + off]      lines 25..174, the rest black
//
//   817 texA + mapA (smooth warp)      818 texA + mapB (the warp plus turbulence)
//   819 texB + mapA                    81C 819 + "are you sitting comfortably?" in black
//   834 texA in four bands (15, 74, 39, 19 lines) with a white line between them, the map
//       read back 8, 16, 24 rows: the torn look;            835 the same on texB, black lines
//
// KESTREL: this IS CHISEL's MAP op (v<<8 | u maps, a u and v offset), which reads 8-bit
// textures. Both textures fit a palette exactly (255 and 64 colours), so they are converted to
// indices at init and the part draws on an 8-bit plane (screen.zig's plane 1), CHISEL doing
// every texel: the CPU only clears the letterbox and sets the registers. (On the CPU the random
// texel reads missed the 4 KB D$ about once a pixel: ~2.4 Mc a frame.) The offset's u and v wrap
// separately here; the Falcon's linear add let u carry into v: a one-texel slip.
// With the local rip all of this is the original's data; otherwise flames_gen.zig stands in.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const arena = @import("arena.zig");
const art = @import("art.zig");
const gen = @import("flames_gen.zig");
const v2 = zg.chisel_v2;

pub const W = 320;
const ROWS = 150;
const TOP = 25;
const TEX = 256 * 256;
const MAP = W * ROWS;
const PATH = 1024;
const WHITE: u8 = 255; // every palette: 0 black, 255 white

var tex: *[2][TEX]u8 = undefined;
var pals: [2][256]u16 = undefined;
var maps: *[2][MAP]u16 = undefined;
var path: [PATH]u16 = undefined;
var caption: *[W * 22]u8 = undefined; // 81C's text: non-zero = a black pixel, lines 89..110

pub fn init(font: []const u8) void {
    tex = arena.take([2][TEX]u8);
    maps = arena.take([2][MAP]u16);
    caption = arena.take([W * 22]u8);
    for (0..2) |t| {
        const src = if (t == 0) art.flame_tex_a else art.flame_tex_b;
        var q = Quantizer{ .pal = &pals[t] };
        for (0..TEX) |i| {
            const c = if (src.len == TEX * 2) art.be16(src, i * 2) else gen.texel(i & 255, i >> 8, t == 1);
            tex[t][i] = q.index(c);
        }
    }
    for (0..2) |m| {
        const src = if (m == 0) art.flame_map_a else art.flame_map_b;
        if (src.len >= MAP * 2) {
            for (0..MAP) |i| maps[m][i] = art.be16(src, i * 2);
        } else gen.genMap(&maps[m], m == 1);
    }
    if (art.flame_path.len == PATH * 2) {
        for (0..PATH) |i| path[i] = art.be16(art.flame_path, i * 2);
    } else gen.genPath(&path);
    if (art.flame_caption.len == caption.len) @memcpy(caption, art.flame_caption) else gen.genCaption(caption, font);
}

// 565 colours -> palette indices: 0 black, 255 white, the others in order of appearance; past
// 254 colours (a stand-in only: the rip's textures have 255 and 64) the nearest one.
const Quantizer = struct {
    pal: *[256]u16,
    n: usize = 1,
    last_c: u16 = 0,
    last_i: u8 = 0,

    fn index(self: *Quantizer, c: u16) u8 {
        if (self.n == 1) {
            self.pal[0] = 0;
            self.pal[WHITE] = 0xFFFF;
        }
        if (c == 0) return 0;
        if (c == 0xFFFF) return WHITE;
        if (c == self.last_c and self.last_i != 0) return self.last_i;
        var best: usize = 1;
        var best_d: u32 = std.math.maxInt(u32);
        for (1..self.n) |i| {
            const d = dist(self.pal[i], c);
            if (d == 0) return self.remember(c, i);
            if (d < best_d) {
                best_d = d;
                best = i;
            }
        }
        if (self.n < WHITE) {
            self.pal[self.n] = c;
            self.n += 1;
            return self.remember(c, self.n - 1);
        }
        return self.remember(c, best);
    }

    fn remember(self: *Quantizer, c: u16, i: usize) u8 {
        self.last_c = c;
        self.last_i = @intCast(i);
        return self.last_i;
    }
};

fn dist(a: u16, b: u16) u32 {
    const dr: i32 = @as(i32, a >> 11) - (b >> 11);
    const dg: i32 = @as(i32, (a >> 5) & 63) - ((b >> 5) & 63);
    const db: i32 = @as(i32, a & 31) - (b & 31);
    return @intCast(dr * dr * 4 + dg * dg + db * db * 4);
}

pub const Flames = struct {
    tex: u1 = 0,
    map: u1 = 0,
    caption: bool = false,
    torn: bool = false,
    pos: u16 = 0, // path entry (the Falcon's $218966 / 2)

    pub fn command(self: *Flames, v: u8) void {
        const pos = self.pos;
        self.* = switch (v) {
            0x17 => .{},
            0x18 => .{ .map = 1 },
            0x19 => .{ .tex = 1 },
            0x1C => .{ .tex = 1, .caption = true },
            0x34 => .{ .torn = true },
            else => .{ .tex = 1, .torn = true }, // 0x35
        };
        self.pos = pos; // the walk goes on across the variants
    }

    pub fn tick(self: *Flames) void {
        self.pos = (self.pos + 1) % PATH;
    }

    /// Onto the 8-bit plane `fb` (320x200): its palette, the letterbox, CHISEL's MAP.
    pub fn draw(self: *const Flames, fb: *zg.LogicalFB) void {
        for (pals[self.tex], 0..) |c, i| {
            const rgba = rgbaOf(c);
            if (fb.palette[i] != rgba) fb.palette[i] = rgba;
        }
        @memset(fb.fb[0 .. TOP * W], 0);
        @memset(fb.fb[(TOP + ROWS) * W .. 200 * W], 0);
        const t = v2.Texture{ .pixels = &tex[self.tex], .stride = 256, .umask = 255, .vmask = 255 };
        const m = &maps[self.map];
        const off = path[self.pos];
        if (!self.torn) {
            v2.map(fb, t, 0, TOP, W, ROWS, m, W, off & 255, off >> 8, .{});
        } else {
            // Four bands; each new band rewinds the map a further 8 rows; a line between them.
            const bands = [4]u16{ 15, 74, 39, 19 };
            const ink: u8 = if (self.tex == 0) WHITE else 0;
            var y: usize = TOP;
            var src: usize = 0;
            for (bands, 0..) |n, k| {
                v2.map(fb, t, 0, @intCast(y), W, n, m[src * W ..], W, off & 255, off >> 8, .{});
                y += n;
                src += n;
                if (k < 3) {
                    @memset(fb.fb[y * W ..][0..W], ink);
                    y += 1;
                    src = src + 1 - 8;
                }
            }
        }
        if (self.caption) for (0..22) |y| {
            const row = fb.fb + (89 + y) * W;
            for (0..W) |x| if (caption[y * W + x] != 0) {
                row[x] = 0;
            };
        };
    }
};

fn rgbaOf(c: u16) u32 {
    const r: u32 = (c >> 11) * 255 / 31;
    const g: u32 = ((c >> 5) & 63) * 255 / 63;
    const b: u32 = (c & 31) * 255 / 31;
    return 0xFF00_0000 | b << 16 | g << 8 | r;
}

test "the quantizer keeps black at 0, white at 255 and gives a colour the same index twice" {
    var p: [256]u16 = undefined;
    var q = Quantizer{ .pal = &p };
    try std.testing.expectEqual(@as(u8, 0), q.index(0));
    try std.testing.expectEqual(@as(u8, WHITE), q.index(0xFFFF));
    const a = q.index(0x1234);
    _ = q.index(0x4321);
    try std.testing.expectEqual(a, q.index(0x1234));
    try std.testing.expectEqual(@as(u16, 0x1234), p[a]);
}
