// --------------------------------------------------------------------------
// Part 3's dots ($40AA's work, $41BD, $45E6/$460B, $4630/$4685, $3991): 35 points on three
// Lissajous sums, drawn as depth-sized dots into a charset "bitmap" (32 x 24 cells, chars
// 0..255 per 64-line band, the NMI switching charsets between bands), double-buffered in VIC
// banks 0 and 3; the nearest depth becomes a sprite instead.
//
// The state is the original's zero page (`zp`), indexed the way the 6510 did: the three
// coordinate lists sit at $25/$48/$6B, so a dot count past 35 reads the next list, as on the
// C64. Every frame: erase the buffer's previous dots (each slot remembers its routine and
// address), compute the coordinates ($41BD: the shape's generated code), plot (routine by
// depth $BA..$BF and sub-position), the depth-$C0 ones go to the sprite list instead.
// --------------------------------------------------------------------------
const data3 = @import("data3.zig");

/// Where the main loop's generator was in the depth section when an IRQ ran the code: dots
/// below `k` already new, dot `k`'s first `y` bytes (LDA's operand from 2, ADC's from 5).
pub const Split = struct { k: u8, y: u8 };
pub const DOTS = 35; // $41BD computes 35 points
const SHAPES_END = 0xF0; // 10 shape records of 24 bytes at $C600

/// An erase-list slot ($0400,x / $0440,x the routine, $0480,x / $04C0,x its address; $0500..
/// for the second buffer): the routine as its depth page and sub-position.
pub const Slot = struct { page: u8, k: u8, lo: u8, hi: u8 };

pub const Dots = struct {
    zp: [256]u8,
    lists: [2][64]Slot,
    rec: [24]u8 = undefined, // the shape record the code was generated from
    old: [24]u8 = undefined, // the one before (its depth code still runs once: see coords)
    shape: u8 = 0, // $3A65
    bad_depth: u32 = 0, // a depth past $C0 (the C64 would run garbage): a test pins 0

    pub fn init(d: data3.Part3) Dots {
        var s = Dots{ .zp = d.zp().*, .lists = undefined };
        for (0..64) |x| {
            s.lists[0][x] = .{ .page = 0, .k = 0, .lo = 0, .hi = 0x20 }; // $38F9: $9460 on $2000
            s.lists[1][x] = .{ .page = 0, .k = 0, .lo = 0, .hi = 0xE0 };
        }
        return s;
    }

    /// $3A64 (the main loop): the next shape's record becomes the generated code's operands.
    pub fn generate(self: *Dots, d: data3.Part3) void {
        self.old = self.rec;
        self.rec = d.bank3()[0x0600 + @as(usize, self.shape) ..][0..24].*;
        const z = &self.zp;
        z[0x10] = self.rec[0];
        z[0x11] = self.rec[1];
        z[0x12] = self.rec[8];
        z[0x13] = self.rec[9];
        z[0x14] = self.rec[17]; // $C610 then $C611 both into $14: $15 is never set
        self.shape +%= 0x18;
        if (self.shape == SHAPES_END) self.shape = 0;
    }

    /// $41BD: x ($25), y ($48) as 9-bit sums halved; depth ($6B) halved with LSR, its carry
    /// chained into the next dot's ADC (one CLC for the whole axis). Then the phases move on.
    /// `split` is set on the one frame the depth code is half generated (null otherwise).
    pub fn coords(self: *Dots, d: data3.Part3, split: ?Split) void {
        const t = d.bank3();
        const r = self.rec;
        const z = &self.zp;
        inline for (.{ .{ 0x10, 0x000, 4, 0x25, 2 }, .{ 0x12, 0x200, 12, 0x48, 10 } }) |ax| {
            const px = z[ax[0]];
            const py = z[ax[0] + 1];
            for (0..DOTS) |i| {
                const a = t[ax[1] + @as(usize, r[ax[2]] +% @as(u8, @truncate(i * r[ax[2] + 2]))) + px];
                const b = t[ax[1] + @as(usize, r[ax[2] + 1] +% @as(u8, @truncate(i * r[ax[2] + 3]))) + py];
                z[ax[3] + i] = @intCast((@as(u16, a) + b) >> 1);
            }
            z[ax[0]] = px +% r[ax[4]];
            z[ax[0] + 1] = py +% r[ax[4] + 1];
        }
        const px = z[0x14];
        const py = z[0x15];
        var c: u16 = 0;
        for (0..DOTS) |i| {
            const ra = if (newByte(split, i, 2)) self.rec else self.old;
            const rb = if (newByte(split, i, 5)) self.rec else self.old;
            const a = t[0x400 + @as(usize, ra[20] +% @as(u8, @truncate(i * ra[22]))) + px];
            const b = t[0x400 + @as(usize, rb[21] +% @as(u8, @truncate(i * rb[23]))) + py];
            const s: u16 = (@as(u16, a) + b + c) & 0xFF; // ADC: 8 bits (u8 a + b would trap)
            c = s & 1;
            z[0x6B + i] = @intCast(s >> 1);
        }
        const rt = if (split != null) self.old else self.rec; // the tail is generated last
        z[0x14] = px +% rt[18];
        z[0x15] = py +% rt[19];
    }

    /// $3968: the sprite list emptied.
    pub fn clearSprites(self: *Dots) void {
        self.zp[0xF8] = 0;
        self.zp[0xF9] = 0;
        self.zp[0xFA] = 0;
        @memset(self.zp[0xE8..0xF8], 0);
    }

    /// $45E6 / $460B: each slot up to `count` runs its erase routine (stores of A = 0).
    pub fn erase(self: *Dots, buf: usize, count: u8, ram: *[65536]u8, d: data3.Part3) void {
        if (count >= 0x80) return;
        var x: usize = count;
        while (true) : (x -= 1) {
            const s = self.lists[buf][x];
            run(d.routine(s.page, s.k, true), ram, @as(u16, s.hi) << 8 | s.lo);
            if (x == 0) break;
        }
    }

    /// $4630 / $4685: plot dots `count`..0 into buffer `buf` (0: bank 0 via $F808, 1: bank 3
    /// via $FA00); depth $C0 goes to the sprite list ($3991) instead.
    pub fn plot(self: *Dots, buf: usize, count: u8, ram: *[65536]u8, d: data3.Part3) void {
        if (count >= 0x80) return;
        const t = d.bank3();
        var c: u16 = 0; // CLC once; the sprite path leaves CMP's carry for the next ADC
        var x: usize = count;
        while (true) : (x -= 1) {
            const s: u16 = 0xBA + @as(u16, self.zp[0x6B + x]) + c;
            const page: u8 = @truncate(s);
            if (page == 0xC0) {
                c = self.addSprite(x);
            } else if (page < 0xBA or page > 0xC0) {
                self.bad_depth += 1;
                c = 0;
            } else {
                const xc = self.zp[0x25 + x];
                const yc = self.zp[0x48 + x];
                const k = (xc & 7) | t[0x3900 + @as(usize, yc)];
                const hi = t[(if (buf == 0) @as(usize, 0x3808) else 0x3A00) + yc];
                const lo = (yc & 7) | (xc & 0xF8); // $0600,x
                self.lists[buf][x] = .{ .page = page - 0xBA, .k = k, .lo = lo, .hi = hi };
                run(d.routine(page - 0xBA, k, false), ram, @as(u16, hi) << 8 | lo);
                c = 0; // ANC #7
            }
            if (x == 0) break;
        }
    }

    // $3991: up to 8 sprites; X = $38 + x (bit 8 into $FA), Y = $32 + y. Returns the carry.
    fn addSprite(self: *Dots, x: usize) u16 {
        const z = &self.zp;
        const n = z[0xF8];
        if (n == 0x10) return 1; // CPY #$10 equal
        z[0xF9] = SPR_EN[n];
        const sx: u16 = 0x38 + @as(u16, z[0x25 + x]);
        z[0xE8 + @as(usize, n)] = @truncate(sx);
        if (sx > 0xFF) z[0xFA] |= SPR_MSB[n];
        const sy: u16 = 0x32 + @as(u16, z[0x48 + x]);
        z[0xE9 + @as(usize, n)] = @truncate(sy);
        z[0xF8] = n + 2;
        return sy >> 8;
    }
};

const SPR_EN = [16]u8{ 1, 1, 3, 3, 7, 7, 0x0F, 0x0F, 0x1F, 0x1F, 0x3F, 0x3F, 0x7F, 0x7F, 0xFF, 0xFF }; // $39BA
const SPR_MSB = [16]u8{ 1, 1, 2, 2, 4, 4, 8, 8, 0x10, 0x10, 0x20, 0x20, 0x40, 0x40, 0x80, 0x80 }; // $39CA

fn newByte(split: ?Split, i: usize, byte: u8) bool {
    const s = split orelse return true;
    return i < s.k or (i == s.k and s.y >= byte);
}

/// One parsed routine at `base` (the ($16) pointer): STA ($16),Y of a value or of it ORed in.
fn run(r: []const u8, ram: *[65536]u8, base: u16) void {
    var i: usize = 0;
    while (i < r.len) : (i += 3) {
        const a = base +% (@as(u16, r[i] >> 3) << 8) +% r[i + 1];
        const v: u8 = if (r[i] & 4 != 0) 0 else r[i + 2]; // the erase loop's A is 0
        ram[a] = if (r[i] & 1 != 0) ram[a] | v else v;
    }
}
