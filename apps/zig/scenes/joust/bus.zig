// --------------------------------------------------------------------------
// The 68000's bus as the transcribed routines see it: the program image and
// the screen (with the RAM below it), big-endian, by absolute address.
//
// Every access of every routine lands here, so it is cut for the board's rv32:
// the 24-bit address in u32 (an i64 compare is two instructions and a carry
// there), one function per access size, and St's rd/wr/get/g wrappers inline
// so a byte, word or long read is ONE call with the size folded away
// (state.zig). An access outside both regions reads 0, writes nothing, and is
// counted in st.oob, as before.
// --------------------------------------------------------------------------
const std = @import("std");
const State = @import("state.zig");
const screen = @import("screen.zig");
const St = State.St;

const BASE: u32 = @intCast(State.BASE);
const SCREEN: u32 = @intCast(State.SCREEN);
const LO: u32 = SCREEN - State.BELOW;

inline fn bus(a: i64) u32 {
    return @as(u32, @truncate(@as(u64, @bitCast(a)))) & 0xFFFFFF;
}

inline fn where(st: *St, x: u32, comptime n: u8) ?*[n]u8 {
    if (x >= BASE and x + n <= BASE + State.MEM_LEN) return State.mem[x - BASE ..][0..n];
    if (x >= LO and x + n <= SCREEN + 32000) return State.scr[x - LO ..][0..n];
    st.oob += 1;
    return null;
}

pub fn rd8(st: *St, a: i64) i64 {
    const b = where(st, bus(a), 1) orelse return 0;
    return b[0];
}

pub fn rd16(st: *St, a: i64) i64 {
    const b = where(st, bus(a), 2) orelse return 0;
    return std.mem.readInt(u16, b, .big);
}

pub fn rd32(st: *St, a: i64) i64 {
    const b = where(st, bus(a), 4) orelse return 0;
    return std.mem.readInt(u32, b, .big);
}

pub fn wr8(st: *St, a: i64, v: i64) void {
    const x = bus(a);
    const b = where(st, x, 1) orelse return;
    if (x >= SCREEN) screen.touch(x - SCREEN, 1); // where() said yes: on the screen
    b[0] = @truncate(@as(u64, @bitCast(v)));
}

pub fn wr16(st: *St, a: i64, v: i64) void {
    const x = bus(a);
    const b = where(st, x, 2) orelse return;
    if (x >= SCREEN) screen.touch(x - SCREEN, 2);
    std.mem.writeInt(u16, b, @truncate(@as(u64, @bitCast(v))), .big);
}

pub fn wr32(st: *St, a: i64, v: i64) void {
    const x = bus(a);
    const b = where(st, x, 4) orelse return;
    if (x >= SCREEN) screen.touch(x - SCREEN, 4);
    std.mem.writeInt(u32, b, @truncate(@as(u64, @bitCast(v))), .big);
}

/// Any other size (none in the transcriptions today): byte by byte, one bounds check.
pub fn rdN(st: *St, a: i64, n: u8) i64 {
    const x = bus(a);
    const b = whereN(st, x, n) orelse return 0;
    var v: i64 = 0;
    for (b[0..n]) |c| v = (v << 8) | c;
    return v;
}

pub fn wrN(st: *St, a: i64, n: u8, v: i64) void {
    const x = bus(a);
    const b = whereN(st, x, n) orelse return;
    if (x >= SCREEN) screen.touch(x - SCREEN, n);
    var y: u64 = @bitCast(v);
    var i: usize = n;
    while (i > 0) {
        i -= 1;
        b[i] = @truncate(y);
        y >>= 8;
    }
}

fn whereN(st: *St, x: u32, n: u8) ?[*]u8 {
    if (x >= BASE and x + n <= BASE + State.MEM_LEN) return State.mem[x - BASE ..].ptr;
    if (x >= LO and x + n <= SCREEN + 32000) return State.scr[x - LO ..].ptr;
    st.oob += 1;
    return null;
}
