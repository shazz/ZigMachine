// --------------------------------------------------------------------------
// One window line of the VIC-II's graphics: 40 cells in the mode $D011/$D016 select.
//
// Modes (ECM BMM MCM): 000 text, 001 multicolour text, 010 hires bitmap, 011 multicolour
// bitmap, 100 extended-colour text, 101..111 invalid (black, still foreground). A cell row
// starts on the bad line, (line & 7) == YSCROLL, where the VIC latches the row's 40 screen
// bytes and colour nibbles (vic.zig: `vm`, `cm`); a store to them later in the row shows only
// from the next row. This invitation keeps YSCROLL 3 and XSCROLL 0 with 25 rows and 40
// columns, which is all the model draws.
// Each line is built in an aligned buffer, four pixels a u32 store (a cell is two: the cart
// CPU is rv32, where u64 is a pair of registers), then copied to the plane.
// --------------------------------------------------------------------------

pub const Mem = struct {
    ram: *[65536]u8,
    col: *[1024]u8, // colour RAM, low nibbles
    chargen: *const [4096]u8,

    /// What the VIC reads at `addr` (14 bits) of bank `bank`: RAM, or the character ROM at
    /// $1000-$1FFF of banks 0 and 2.
    pub inline fn vic(self: Mem, bank: u8, addr: u16) u8 {
        const a = addr & 0x3FFF;
        if (bank & 1 == 0 and a & 0x3000 == 0x1000) return self.chargen[a & 0x0FFF];
        return self.ram[@as(u16, bank) * 0x4000 + a];
    }
};

pub const Ctx = struct {
    reg: *const [0x2F]u8,
    bank: u8,
    mem: Mem,
    vm: *const [40]u8, // the row's screen bytes, latched on its bad line
    cm: *const [40]u8, // and its colour nibbles

    pub fn screen(self: Ctx) u16 {
        return @as(u16, self.reg[0x18] >> 4) * 0x400;
    }
};

// EXP[n]: 0xFF in byte k where bit 3-k of nibble n is set (pixel k of four, little endian).
const EXP = blk: {
    var t: [16]u32 = undefined;
    for (0..16) |n| {
        var v: u32 = 0;
        for (0..4) |k| {
            if ((n >> (3 - k)) & 1 != 0) v |= @as(u32, 0xFF) << (8 * k);
        }
        t[n] = v;
    }
    break :blk t;
};

/// Four pixels of C64 colour `c` (palette index c + 1).
fn spread(c: u8) u32 {
    return @as(u32, (c & 15) + 1) * 0x0101_0101;
}

/// Where `m` is set `a`, else `b`.
inline fn sel(m: u32, a: u32, b: u32) u32 {
    return (m & a) | (~m & b);
}

/// One cell of hires pixels: `ink` where `data`'s bit is set, else `paper`.
inline fn hires(buf: *[80]u32, c: usize, data: u8, ink: u32, paper: u32) void {
    buf[2 * c] = sel(EXP[data >> 4], ink, paper);
    buf[2 * c + 1] = sel(EXP[data & 15], ink, paper);
}

/// Draw window line `wl` (0..199) into `dst` (320 palette indices).
pub fn draw(ctx: Ctx, wl: u16, dst: *[320]u8) void {
    var buf: [80]u32 = undefined;
    const reg = ctx.reg;
    const mode = (reg[0x11] >> 4 & 0x06) | (reg[0x16] >> 4 & 1); // ECM BMM MCM
    const cell_row = wl / 8;
    const rl = wl % 8;
    switch (mode) {
        0b000, 0b001, 0b100 => text(ctx, mode, rl, &buf),
        0b010, 0b011 => bitmap(ctx, mode == 0b011, cell_row, rl, &buf),
        else => @memset(&buf, spread(0)), // invalid: black
    }
    @memcpy(dst, @as(*const [320]u8, @ptrCast(&buf)));
}

fn text(ctx: Ctx, mode: u8, rl: u16, buf: *[80]u32) void {
    const reg = ctx.reg;
    const chars = @as(u16, (reg[0x18] >> 1) & 7) * 0x800 + rl;
    const bgs = [4]u32{ spread(reg[0x21]), spread(reg[0x22]), spread(reg[0x23]), spread(reg[0x24]) };
    for (0..40) |c| {
        const code = ctx.vm[c];
        const colour = ctx.cm[c] & 15;
        if (mode == 0b100) {
            const data = ctx.mem.vic(ctx.bank, chars + @as(u16, code & 63) * 8);
            hires(buf, c, data, spread(colour), bgs[code >> 6]);
            continue;
        }
        const data = ctx.mem.vic(ctx.bank, chars + @as(u16, code) * 8);
        if (mode == 0b001 and colour & 8 != 0) {
            multi(buf, c, data, .{ bgs[0], bgs[1], bgs[2], spread(colour & 7) });
        } else {
            hires(buf, c, data, spread(colour), bgs[0]);
        }
    }
}

fn bitmap(ctx: Ctx, mc: bool, cell_row: u16, rl: u16, buf: *[80]u32) void {
    const reg = ctx.reg;
    const bmp = @as(u16, reg[0x18] & 8) * 0x400 + cell_row * 320 + rl;
    const bg = spread(reg[0x21]);
    for (0..40) |c| {
        const s = ctx.vm[c];
        const data = ctx.mem.vic(ctx.bank, bmp + @as(u16, @intCast(c)) * 8);
        if (mc) {
            multi(buf, c, data, .{ bg, spread(s >> 4), spread(s & 15), spread(ctx.cm[c]) });
        } else {
            hires(buf, c, data, spread(s >> 4), spread(s & 15));
        }
    }
}

/// One cell of four double-width pixels: pair value p of `data` shows `cs[p]` (spread colours).
fn multi(buf: *[80]u32, c: usize, data: u8, cs: [4]u32) void {
    inline for (0..2) |h| {
        const nib = (data >> (4 - 4 * h)) & 15; // pairs 2h, 2h+1
        const hi = EXP[(nib & 0b1010) | ((nib & 0b1010) >> 1)]; // the pair's high bit, both pixels
        const lo = EXP[(nib & 0b0101) | ((nib & 0b0101) << 1)]; // and its low bit
        buf[2 * c + h] = sel(hi, sel(lo, cs[3], cs[2]), sel(lo, cs[1], cs[0]));
    }
}
