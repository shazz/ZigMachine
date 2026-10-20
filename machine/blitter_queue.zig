// --------------------------------------------------------------------------
// ZigMachine — the blitter's QUEUE (1.8.0): COMMAND 5 runs a list of op
// descriptors the program stored in the QUEUE ring, so many small ops cost one
// hwBlit(). The format and the rules are memmap.zig's BLIT_CMD_QUEUE comment.
//
// The machine runs the list at once, as every blitter op: each descriptor's
// words go into the register block itself (the working copy), its op runs with
// runOp(), and the block is put back as the program left it at the end. On the
// board CHISEL runs the same list from its own copy of the ring and of the block
// (rtl/blitter/zm_blit_q.v) while the cart goes on; only the pixels may differ
// in WHEN they appear, never in what they are.
// --------------------------------------------------------------------------
const std = @import("std");
const memmap = @import("sdk/memmap.zig");
const blitter = @import("blitter.zig");

const BLOCK_BYTES: usize = 24 * 4; // the words a descriptor can set (0x00..0x5F of the block)

inline fn at(off: usize) *align(1) u32 {
    return @ptrFromInt(memmap.HW_VIDEO_BASE + off);
}
inline fn r16(off: usize) u16 {
    return @truncate(at(off).* & 0xFFFF);
}
inline fn ring(i: usize) u32 {
    return std.mem.littleToNative(u32, at(memmap.OFF_BLIT_QUEUE + i * 4).*);
}

// Word k of the working copy. Word 0 holds COMMAND (the header's) and STATUS (not
// a register): a descriptor sets its MINTERM and CON bytes only.
fn setWord(k: usize, v: u32) void {
    const p: [*]u8 = @ptrFromInt(memmap.HW_VIDEO_BASE + memmap.OFF_BLIT + k * 4);
    const bytes = std.mem.toBytes(std.mem.nativeToLittle(u32, v));
    if (k == 0) {
        p[1] = bytes[1];
        p[2] = bytes[2];
    } else @memcpy(p[0..4], &bytes);
}

fn finish(cycles: u32) void {
    at(memmap.BLIT_CYCLES).* = std.mem.nativeToLittle(u32, cycles);
    const st: *u8 = @ptrFromInt(memmap.HW_VIDEO_BASE + memmap.BLIT_STATUS);
    st.* = 0;
}

pub fn run() void {
    const start: usize = r16(memmap.BLIT_Q_START);
    const end = start + r16(memmap.BLIT_Q_COUNT);
    if (end == start or end > memmap.BLIT_QUEUE_WORDS) return finish(0); // refused
    const block: [*]u8 = @ptrFromInt(memmap.HW_VIDEO_BASE + memmap.OFF_BLIT);
    var saved: [BLOCK_BYTES]u8 = undefined;
    @memcpy(&saved, block[0..BLOCK_BYTES]);
    var total: u32 = 0;
    var i = start;
    while (i < end) {
        const hdr = ring(i);
        i += 1;
        var mask: u32 = hdr & 0xFF_FFFF;
        if (@popCount(mask) > end - i) break; // cut short by Q_COUNT: the list ends, unrun
        while (mask != 0) : (mask &= mask - 1) {
            setWord(@ctz(mask), ring(i));
            i += 1;
        }
        const cmd: u8 = @truncate(hdr >> 24);
        block[0] = cmd;
        if (cmd == memmap.BLIT_CMD_NOP) continue;
        blitter.runOp(cmd);
        total +%= std.mem.littleToNative(u32, at(memmap.BLIT_CYCLES).*);
    }
    @memcpy(block[0..BLOCK_BYTES], &saved);
    finish(total);
}
