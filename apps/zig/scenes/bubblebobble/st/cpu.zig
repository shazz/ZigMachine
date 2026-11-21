// --------------------------------------------------------------------------
// The 68000 the translated game runs on (../gen/, tools/bubblebobble/st_recomp.py):
// the registers, the five condition flags, the cycle clock, and the bus.
//
// The bus is the ST's: the first 512 KB are RAM (`mem`, the cart allocates
// it), $FF8000-$FFFFFF the hardware registers (io.zig). Words and longs are
// big-endian, as the game stores them. The flags are kept as five booleans
// and set by the helpers below exactly as the 68000 sets them.
// --------------------------------------------------------------------------
const io = @import("io.zig");
const tos = @import("tos.zig");
const alu = @import("alu.zig");

pub const RAM: u32 = 0x80000;

pub var d: [8]u32 = .{0} ** 8;
pub var a: [8]u32 = .{0} ** 8;
pub var fx: bool = false;
pub var fneg: bool = false;
pub var fz: bool = false;
pub var fv: bool = false;
pub var fc: bool = false;
/// Supervisor-mode bits of SR other than the flags (the game never reads them).
pub var sr_hi: u16 = 0x2700;

/// 68000 cycles since power-on, and the time the running code must stop at
/// (the next interrupt): the translated code checks it on every loop.
pub var cy: u64 = 0;
pub var limit: u64 = 0;
/// Program counters the translation does not know (a jump into data): counted, harness checks 0.
pub var bad_pcs: u32 = 0;
pub var last_bad: u32 = 0;

pub var mem: []u8 = &.{};

// ---- the bus ---------------------------------------------------------------
pub inline fn rb(addr: u32) u8 {
    const x = addr & 0xFFFFFF;
    if (x < RAM) return mem[x];
    return io.rb(x);
}
pub inline fn rw(addr: u32) u16 {
    const x = addr & 0xFFFFFE;
    if (x < RAM) return @as(u16, mem[x]) << 8 | mem[x + 1];
    return io.rw(x);
}
pub inline fn rl(addr: u32) u32 {
    return @as(u32, rw(addr)) << 16 | rw(addr +% 2);
}
pub inline fn wb(addr: u32, v: u8) void {
    const x = addr & 0xFFFFFF;
    if (x < RAM) mem[x] = v else io.wb(x, v);
}
pub inline fn ww(addr: u32, v: u16) void {
    const x = addr & 0xFFFFFE;
    if (x < RAM) {
        mem[x] = @truncate(v >> 8);
        mem[x + 1] = @truncate(v);
    } else io.ww(x, v);
}
pub inline fn wl(addr: u32, v: u32) void {
    ww(addr, @truncate(v >> 16));
    ww(addr +% 2, @truncate(v));
}

// ---- registers ---------------------------------------------------------------
pub inline fn dv(comptime T: type, n: u3) T {
    return @truncate(d[n]);
}
pub inline fn av(comptime T: type, n: u3) T {
    return @truncate(a[n]);
}
/// A sized write to a data register: the bits above the size are kept.
pub inline fn setD(comptime T: type, n: u3, v: T) void {
    const m: u32 = ~@as(u32, ~@as(T, 0));
    d[n] = (d[n] & m) | v;
}
pub inline fn sx8(v: u8) u32 {
    return @bitCast(@as(i32, @as(i8, @bitCast(v))));
}
pub inline fn sx16(v: u16) u32 {
    return @bitCast(@as(i32, @as(i16, @bitCast(v))));
}

// ---- the stack ---------------------------------------------------------------
pub inline fn push32(v: u32) void {
    a[7] -%= 4;
    wl(a[7], v);
}
pub inline fn pop32() u32 {
    const v = rl(a[7]);
    a[7] +%= 4;
    return v;
}
pub fn getSr() u16 {
    var s: u16 = sr_hi & 0xFF00;
    if (fx) s |= 0x10;
    if (fneg) s |= 0x08;
    if (fz) s |= 0x04;
    if (fv) s |= 0x02;
    if (fc) s |= 0x01;
    return s;
}
pub fn setSr(s: u16) void {
    sr_hi = s & 0xFF00;
    fx = s & 0x10 != 0;
    fneg = s & 0x08 != 0;
    fz = s & 0x04 != 0;
    fv = s & 0x02 != 0;
    fc = s & 0x01 != 0;
}
/// An exception's frame: the PC, then SR on top.
pub fn exception(ret: u32) void {
    push32(ret);
    a[7] -%= 2;
    ww(a[7], getSr());
}
pub fn rte() u32 {
    setSr(rw(a[7]));
    a[7] +%= 2;
    io.irqDone();
    return pop32();
}

pub fn trap(n: u32, ret: u32) u32 {
    return tos.trap(n, ret);
}

/// A jump the translation has no label for.
pub fn bad(pc: u32) u32 {
    bad_pcs += 1;
    last_bad = pc;
    limit = cy; // stop the frame: the harness reports it
    return pc;
}

/// A loop that only polls RAM waits for an interrupt: the time until it passes at once.
pub inline fn idle() void {
    if (cy < limit) cy = limit;
}

// ---- the flags (alu.zig) --------------------------------------------------------
pub const logic = alu.logic;
pub const add = alu.add;
pub const sub = alu.sub;
pub const cmp = alu.cmp;
pub const addx = alu.addx;
pub const divu = alu.divu;
pub const btst = alu.btst;
pub const bset = alu.bset;
pub const bclr = alu.bclr;
pub const bchg = alu.bchg;
pub const asl = alu.asl;
pub const asr = alu.asr;
pub const lsl = alu.lsl;
pub const lsr = alu.lsr;
pub const roxl = alu.roxl;
pub const roxr = alu.roxr;
