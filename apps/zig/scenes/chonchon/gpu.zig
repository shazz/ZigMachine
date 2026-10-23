// --------------------------------------------------------------------------
// The chunky compositor's two backends, shared by chonchon and chonchon2.
//
// Surfaces are planes: SHOWN (plane 0, the only one FRESCO composites), BG
// (plane 1: expand(background) built once at init) and WORK (plane 2: the
// frame being composed). BG and WORK stay DISABLED, so they cost no FRESCO.
// A tick composes WORK = BG + what moved, then ONE copy puts it on SHOWN, so a
// half-built frame is never on the shown plane.
//
// Chisel is the board's: every op one CHISEL op, the CPU only stores whole
// u32 words into WORK (never reads a plane back). Soft is the same contract in
// arrays for the native equivalence tests; it asserts the board's rules: every
// rectangle on its surface, and no copy reads the surface it writes (CHISEL
// would run such a copy in its slow ordered mode).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

pub const W: usize = 320;
pub const H: usize = 200;
pub const SHOWN: u8 = 0;
pub const BG: u8 = 1;
pub const WORK: u8 = 2;

/// Minterms for a FILL combined with the destination (CON2.FILL_MT, D = LF(0, COLOR, D)).
pub const MT_AND: u8 = 0x88; // B & C
pub const MT_OR: u8 = 0xEE; // B | C

fn applyMt(mt: u8, b: u8, c: u8) u8 {
    return switch (mt) {
        MT_AND => b & c,
        MT_OR => b | c,
        else => unreachable,
    };
}

pub const Chisel = struct {
    blit: zg.Blitter,
    fbs: [3]*zg.LogicalFB,
    ops: usize = 0,

    pub fn init(self: *Chisel, fbs: [3]*zg.LogicalFB) void {
        self.blit = .{};
        self.blit.init();
        self.fbs = fbs;
        self.ops = 0;
    }

    /// The whole of `src` onto `dst` (two different planes).
    pub fn copy(self: *Chisel, dst: u8, src: u8) void {
        self.ops += 1;
        self.blit.blitCopy(self.fbs[dst], 0, 0, self.fbs[src], 0, 0, W, H);
    }

    pub fn image(self: *Chisel, dst: u8, dx: u16, dy: u16, pixels: []const u8, src_w: u16, sx: u16, sy: u16, w: u16, h: u16, key: ?u8) void {
        self.ops += 1;
        self.blit.blitImage(self.fbs[dst], @intCast(dx), @intCast(dy), pixels, src_w, sx, sy, w, h, key);
    }

    pub fn fill(self: *Chisel, dst: u8, x: u16, y: u16, w: u16, h: u16, v: u8) void {
        self.ops += 1;
        self.blit.fill(self.fbs[dst], @intCast(x), @intCast(y), w, h, v);
    }

    /// Every index in the box becomes LF(COLOR = v, index) for minterm `mt`.
    pub fn fillMt(self: *Chisel, dst: u8, x: u16, y: u16, w: u16, h: u16, v: u8, mt: u8) void {
        self.ops += 1;
        self.blit.fillEx(self.fbs[dst], @intCast(x), @intCast(y), w, h, v, .{ .mt = @enumFromInt(mt) });
    }

    /// The CPU's store view of a surface: 80 words a row. Stores only.
    pub fn words(self: *Chisel, dst: u8) [*]u32 {
        return @ptrCast(@alignCast(self.fbs[dst].fb));
    }
};

pub const Soft = struct {
    surf: [3][W * H]u8 align(4) = undefined,
    ops: usize = 0,

    fn rect(x: u16, y: u16, w: u16, h: u16) void {
        std.debug.assert(w > 0 and h > 0 and @as(usize, x) + w <= W and @as(usize, y) + h <= H);
    }

    pub fn copy(self: *Soft, dst: u8, src: u8) void {
        std.debug.assert(dst != src);
        self.ops += 1;
        self.surf[dst] = self.surf[src];
    }

    pub fn image(self: *Soft, dst: u8, dx: u16, dy: u16, pixels: []const u8, src_w: u16, sx: u16, sy: u16, w: u16, h: u16, key: ?u8) void {
        rect(dx, dy, w, h);
        std.debug.assert(@as(usize, sx) + w <= src_w and (@as(usize, sy) + h) * src_w <= pixels.len);
        self.ops += 1;
        for (0..h) |j| {
            const d = (@as(usize, dy) + j) * W + dx;
            const s = (@as(usize, sy) + j) * src_w + sx;
            for (0..w) |i| {
                const v = pixels[s + i];
                if (key == null or v != key.?) self.surf[dst][d + i] = v;
            }
        }
    }

    pub fn fill(self: *Soft, dst: u8, x: u16, y: u16, w: u16, h: u16, v: u8) void {
        rect(x, y, w, h);
        self.ops += 1;
        for (0..h) |j| {
            const d = (@as(usize, y) + j) * W + x;
            @memset(self.surf[dst][d .. d + w], v);
        }
    }

    pub fn fillMt(self: *Soft, dst: u8, x: u16, y: u16, w: u16, h: u16, v: u8, mt: u8) void {
        rect(x, y, w, h);
        self.ops += 1;
        for (0..h) |j| {
            const d = (@as(usize, y) + j) * W + x;
            for (self.surf[dst][d .. d + w]) |*p| p.* = applyMt(mt, v, p.*);
        }
    }

    pub fn words(self: *Soft, dst: u8) [*]u32 {
        return @ptrCast(&self.surf[dst]);
    }
};

/// The one planar -> chunky rule both carts share: 16 pixels of an ST
/// 4-plane group (8 bytes, big-endian plane words) as 4 u32 words of indices,
/// pixel 0 in the low byte. NIB[n] spreads a plane nibble (leftmost pixel in
/// bit 3) over 4 index bytes.
const NIB: [16]u32 = blk: {
    var t: [16]u32 = undefined;
    for (0..16) |n| {
        var v: u32 = 0;
        for (0..4) |i| v |= @as(u32, (n >> (3 - i)) & 1) << (8 * i);
        t[n] = v;
    }
    break :blk t;
};

pub inline fn expandGroup(out: [*]u32, g: *const [8]u8) void {
    inline for (0..4) |k| {
        const byte = k / 2; // 0,0,1,1
        const sh = if (k % 2 == 0) 4 else 0;
        out[k] = NIB[(g[byte] >> sh) & 15] |
            NIB[(g[2 + byte] >> sh) & 15] << 1 |
            NIB[(g[4 + byte] >> sh) & 15] << 2 |
            NIB[(g[6 + byte] >> sh) & 15] << 3;
    }
}

/// expand() of a whole 32000-byte screen, for init (BG) and the tests.
pub fn expandScreen(out: [*]u32, screen: *const [32000]u8) void {
    for (0..4000) |g| expandGroup(out + g * 4, screen[g * 8 ..][0..8]);
}
