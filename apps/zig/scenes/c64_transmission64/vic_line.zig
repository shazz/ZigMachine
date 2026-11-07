// --------------------------------------------------------------------------
// One window line of the VIC-II's graphics: 40 cells in the mode $D011/$D016 select.
//
// Modes (ECM BMM MCM): 000 text, 001 multicolour text, 010 hires bitmap, 011 multicolour
// bitmap, 100 extended-colour text, 101..111 invalid (black, still foreground). A cell row
// starts on the bad line, (line & 7) == YSCROLL, where the VIC latches the row's 40 screen
// bytes and colour nibbles (vic.zig: `vm`, `cm`); a store to them later in the row shows only
// from the next row. This invitation keeps YSCROLL 3 and XSCROLL 0 with 25 rows and 40
// columns, which is all the model draws.
// Each line is built in an aligned buffer, eight pixels a store, then copied to the plane.
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

const ONES: u64 = 0x0101_0101_0101_0101;

// EXP[b]: 0xFF in byte k where bit 7-k of b is set (pixel k of the byte, little endian).
const EXP = blk: {
    @setEvalBranchQuota(4000);
    var t: [256]u64 = undefined;
    for (0..256) |b| {
        var v: u64 = 0;
        for (0..8) |k| {
            if ((b >> (7 - k)) & 1 != 0) v |= @as(u64, 0xFF) << (8 * k);
        }
        t[b] = v;
    }
    break :blk t;
};

// Pair k (0 = leftmost) of a multicolour byte.
inline fn pair(b: u8, k: u3) u2 {
    return @intCast((b >> (6 - 2 * @as(u3, k))) & 3);
}

fn spread(c: u8) u64 {
    return @as(u64, (c & 15) + 1) * ONES;
}

/// Draw window line `wl` (0..199) into `dst` (320 palette indices).
pub fn draw(ctx: Ctx, wl: u16, dst: *[320]u8) void {
    var buf: [40]u64 = undefined;
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

fn text(ctx: Ctx, mode: u8, rl: u16, buf: *[40]u64) void {
    const reg = ctx.reg;
    const chars = @as(u16, (reg[0x18] >> 1) & 7) * 0x800 + rl;
    const bgs = [4]u64{ spread(reg[0x21]), spread(reg[0x22]), spread(reg[0x23]), spread(reg[0x24]) };
    for (0..40) |c| {
        const code = ctx.vm[c];
        const colour = ctx.cm[c] & 15;
        if (mode == 0b100) {
            const bits = EXP[ctx.mem.vic(ctx.bank, chars + @as(u16, code & 63) * 8)];
            buf[c] = (bits & spread(colour)) | (~bits & bgs[code >> 6]);
            continue;
        }
        const data = ctx.mem.vic(ctx.bank, chars + @as(u16, code) * 8);
        if (mode == 0b001 and colour & 8 != 0) {
            const cs = [4]u8{ reg[0x21], reg[0x22], reg[0x23], colour & 7 };
            buf[c] = multi(data, &cs);
        } else {
            const bits = EXP[data];
            buf[c] = (bits & spread(colour)) | (~bits & bgs[0]);
        }
    }
}

fn bitmap(ctx: Ctx, mc: bool, cell_row: u16, rl: u16, buf: *[40]u64) void {
    const reg = ctx.reg;
    const bmp = @as(u16, reg[0x18] & 8) * 0x400 + cell_row * 320 + rl;
    for (0..40) |c| {
        const s = ctx.vm[c];
        const data = ctx.mem.vic(ctx.bank, bmp + @as(u16, @intCast(c)) * 8);
        if (mc) {
            const cs = [4]u8{ reg[0x21], s >> 4, s & 15, ctx.cm[c] };
            buf[c] = multi(data, &cs);
        } else {
            const bits = EXP[data];
            buf[c] = (bits & spread(s >> 4)) | (~bits & spread(s & 15));
        }
    }
}

// Four double-width pixels from the 2-bit pairs of `data`.
fn multi(data: u8, cs: *const [4]u8) u64 {
    var v: u64 = 0;
    inline for (0..4) |k| {
        const idx: u64 = (cs[pair(data, k)] & 15) + 1;
        v |= (idx | idx << 8) << (16 * k);
    }
    return v;
}
