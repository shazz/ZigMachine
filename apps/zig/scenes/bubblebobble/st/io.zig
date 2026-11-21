// --------------------------------------------------------------------------
// The ST hardware registers the game touches ($FF8000-$FFFFFF), as the
// translated code reads and writes them through cpu.zig's bus.
//
//   $FF8201/03   video base (high, mid): latched at the VBL (frame.zig)
//   $FF8205-09   video address counter: where the beam reads, from k.cy
//   $FF820A      sync mode: 50 Hz, internal sync
//   $FF8240-5E   the 16 colour registers; a write while the beam is in the
//                picture is logged with its line (the game's Timer B rasters)
//   $FF8800/02   the YM2149: register select / data (the game's own driver)
//   $FFFA01-2F   the MFP 68901: Timer B (event count = display lines), its
//                enable / mask / in-service bits
//   $FFFC00/02   the keyboard ACIA: status, the last byte the IKBD sent
// Anything else reads 0 and its writes are counted (`dropped`).
// --------------------------------------------------------------------------
const k = @import("cpu.zig");

pub const LINE_CYC: u64 = 512;
pub const FRAME_CYC: u64 = 313 * LINE_CYC;
/// The first displayed line of a 50 Hz frame, counted from the VBL.
pub const TOP_LINE: u64 = 63;
pub const LINES: usize = 200;

pub var palette: [16]u16 = .{0} ** 16;
pub var vbase_hi: u8 = 0;
pub var vbase_mid: u8 = 0;
pub var frame_start: u64 = 0;
/// The screen being displayed (latched at the VBL).
pub var shown_base: u32 = 0;

/// Palette writes inside the picture this frame: line, register, value.
pub const RasterWrite = struct { line: u8, reg: u8, value: u16 };
pub var rasters: [1024]RasterWrite = undefined;
pub var raster_n: usize = 0;
/// The palette as it stood when the picture began (line 0).
pub var palette_top: [16]u16 = .{0} ** 16;

pub var mfp: [0x30]u8 = .{0} ** 0x30;
pub var tb_count: u8 = 0;
pub var tb_data: u8 = 0;

pub var psg_sel: u8 = 0;
pub var psg: [16]u8 = .{0} ** 16;
pub var psg_writes: u32 = 0;

pub var kbd_byte: u8 = 0;
pub var in_irq: bool = false;
pub var dropped: u32 = 0;

pub fn reset() void {
    palette = .{0} ** 16;
    palette_top = .{0} ** 16;
    vbase_hi = 0;
    vbase_mid = 0;
    mfp = .{0} ** 0x30;
    tb_count = 0;
    tb_data = 0;
    psg = .{0} ** 16;
    kbd_byte = 0;
    in_irq = false;
    raster_n = 0;
    dropped = 0;
}

pub fn irqDone() void {
    in_irq = false;
}

pub fn videoBase() u32 {
    return @as(u32, vbase_hi) << 16 | @as(u32, vbase_mid) << 8;
}

/// The beam's line in the picture now (negative above it).
pub fn pictureLine() i64 {
    const into: i64 = @intCast(k.cy -% frame_start);
    return @divFloor(into, LINE_CYC) - @as(i64, TOP_LINE);
}

fn videoCounter() u32 {
    const l = pictureLine();
    if (l < 0) return shown_base;
    if (l >= LINES) return shown_base + 32000;
    const col = ((k.cy -% frame_start) % LINE_CYC);
    const bytes: u32 = @intCast(@min(col / 3, 160) & ~@as(u64, 1));
    return shown_base + @as(u32, @intCast(l)) * 160 + bytes;
}

pub fn rb(x: u32) u8 {
    return switch (x) {
        0xFF8201 => vbase_hi,
        0xFF8203 => vbase_mid,
        0xFF8205 => @truncate(videoCounter() >> 16),
        0xFF8207 => @truncate(videoCounter() >> 8),
        0xFF8209 => @truncate(videoCounter()),
        0xFF820A => 0x02,
        0xFF8800 => psg[psg_sel & 15],
        0xFFFA01...0xFFFA2F => mfpRead(x),
        0xFFFC00 => 0x02 | @as(u8, if (kbd_byte != 0) 0x01 else 0),
        0xFFFC02 => kbd_byte,
        0xFF8240...0xFF825F => @truncate(palette[(x - 0xFF8240) >> 1] >> @intCast(8 * (1 - (x & 1)))),
        else => blk: {
            dropped += 1;
            break :blk 0;
        },
    };
}

pub fn rw(x: u32) u16 {
    if (x >= 0xFF8240 and x < 0xFF8260) return palette[(x - 0xFF8240) >> 1];
    return @as(u16, rb(x)) << 8 | rb(x + 1);
}

pub fn wb(x: u32, v: u8) void {
    switch (x) {
        0xFF8201 => vbase_hi = v,
        0xFF8203 => vbase_mid = v,
        0xFF8800 => psg_sel = v,
        0xFF8802 => {
            psg[psg_sel & 15] = v;
            psg_writes += 1;
        },
        0xFFFA01...0xFFFA2F => mfpWrite(x, v),
        0xFF8240...0xFF825F => {
            const i = (x - 0xFF8240) >> 1;
            const sh: u4 = if (x & 1 == 0) 8 else 0;
            setColour(i, (palette[i] & ~(@as(u16, 0xFF) << sh)) | (@as(u16, v) << sh));
        },
        else => dropped += 1,
    }
}

pub fn ww(x: u32, v: u16) void {
    if (x >= 0xFF8240 and x < 0xFF8260) return setColour((x - 0xFF8240) >> 1, v);
    if (x == 0xFF8800) return wb(x, @truncate(v >> 8));
    if (x == 0xFF8802) return wb(x, @truncate(v >> 8));
    wb(x, @truncate(v >> 8));
    wb(x + 1, @truncate(v));
}

fn setColour(i: u32, v: u16) void {
    palette[i] = v & 0x777;
    const l = pictureLine();
    if (l < 0 or l >= LINES) return;
    if (raster_n < rasters.len) {
        rasters[raster_n] = .{ .line = @intCast(l), .reg = @intCast(i), .value = v & 0x777 };
        raster_n += 1;
    }
}

fn mfpRead(x: u32) u8 {
    if (x == 0xFFFA21) return tb_count;
    return mfp[x - 0xFFFA00];
}

fn mfpWrite(x: u32, v: u8) void {
    const r = x - 0xFFFA00;
    if (r == 0x1B) { // TBCR: starting the timer loads the counter
        if (mfp[r] & 0x0F == 0) tb_count = tb_data;
    } else if (r == 0x21) {
        tb_data = v;
        if (mfp[0x1B] & 0x0F == 0) tb_count = v;
    } else if (r == 0x0F) { // ISRA: in-service bits are cleared by writing 0
        mfp[r] &= v;
        return;
    }
    mfp[r] = v;
}

/// Timer B counts the end of a displayed line in event mode (TBCR = 8).
/// True when it reaches 0 and its interrupt is enabled and unmasked.
pub fn timerBLine() bool {
    if (mfp[0x1B] & 0x0F != 8) return false;
    tb_count -%= 1;
    if (tb_count != 0) return false;
    tb_count = tb_data;
    return mfp[0x07] & 1 != 0 and mfp[0x13] & 1 != 0;
}
