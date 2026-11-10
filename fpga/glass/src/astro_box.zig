// ASTROLABE's mailbox, the ARM's side (SPIKE, docs/ARM_FPU_COPROC.md): one request served.
//
// The 4 KiB block RAM (rtl/glass/zm_astro_mbox.v) at map.OFF_ASTRO holds the protocol words
// below and up to MAX_COUNT descriptors; ZIGGY's firmware (fpga/cycles/bastro.c, whose
// bastro_box.h repeats these numbers: tests/test_astro_box.py compares them) copies a
// cart's descriptors in, rings SEQ, and waits for DONE. Each word has ONE writer:
// ZIGGY writes SEQ, COUNT, MEM_* and the descriptors' inputs; glass writes MAGIC, BEAT,
// TAKEN, DONE, ARM_NS, RET and the descriptors' outputs (W_STATUS, W_R).
//
// The cart is not trusted: the descriptors' arrays are checked (astro_ops.check) against
// the cart's memory, and the memory itself against the DDR window, before a word is read.
// Arrays are FAR: they stay in the cart's memory in DDR and are staged through `mirror`
// (ordinary cached memory, indexed by cart address) around each descriptor.
const std = @import("std");
const ops = @import("astro_ops");
const abi = ops.abi;

pub const MAGIC: u32 = 0; // glass: ID while its worker runs, 0 when it stops
pub const VERSION: u32 = 1; // glass: PROTO
pub const BEAT: u32 = 2; // glass: +1 a poll while idle, so ZIGGY can tell a live worker
pub const SEQ: u32 = 3; // ZIGGY: the doorbell, written last
pub const TAKEN: u32 = 4; // glass: = SEQ once the request is read
pub const DONE: u32 = 5; // glass: = SEQ once every result is in place
pub const COUNT: u32 = 6; // ZIGGY: descriptors
pub const MEM_OFF: u32 = 7; // ZIGGY: the DDR window offset of cart address 0
pub const MEM_SIZE: u32 = 8; // ZIGGY: the cart memory's bytes
pub const ARM_NS: u32 = 9; // glass: what the request took on the ARM, ns
pub const RET: u32 = 10; // glass: hwAstro's answer (the first non-OK status)
pub const DESC0: u32 = 16; // descriptor i at DESC0 + i * DESC_WORDS
pub const ID: u32 = 0x4153_5452; // "ASTR"
pub const PROTO: u32 = 1;

comptime {
    if (DESC0 + abi.MAX_COUNT * abi.DESC_WORDS > 1024) @compileError("astro_box: descriptors overflow the mailbox");
}

/// The words of descriptor `i` ZIGGY copies in: W_OP always, then the scalars of a scalar op
/// or the array words (W_N .. W_C) and S0 of an array op. glass reads exactly these.
pub fn isScalar(op: u32) bool {
    return (op & abi.OP_MASK) < abi.OP_VADD;
}

pub const Server = struct {
    box: []volatile u32, // map.ASTRO_WORDS
    ddr: []volatile u32, // the cart CPU's DDR window (devmem.Board.ddr_words)
    mirror: []u8, // >= the cart memory, 8-aligned; index = cart address
    last: u32 = 0, // the last SEQ served
    clock: *const fn () u64 = zeroNs,

    fn zeroNs() u64 {
        return 0;
    }

    /// A request waiting? Then serve it whole: true. Never blocks.
    pub fn poll(s: *Server) bool {
        const seq = s.box[SEQ];
        if (seq == s.last or seq == 0) return false;
        const t0 = s.clock();
        s.box[TAKEN] = seq;
        s.last = seq;
        // ZIGGY withdraws a request nobody took in time (SEQ = 0, bastro_post.h) and runs it
        // itself: one read after TAKEN, and a withdrawn request is never served.
        if (s.box[SEQ] != seq) return false;
        const count = s.box[COUNT];
        const off = s.box[MEM_OFF];
        const size = s.box[MEM_SIZE];
        var ret: u32 = abi.ST_BAD_DESC;
        if (count <= abi.MAX_COUNT and memOk(s, off, size)) {
            const mem = ops.Mem{ .ptr = s.mirror.ptr, .size = size };
            ret = abi.ST_OK;
            for (0..count) |i| {
                const st = s.serveOne(mem, off, DESC0 + @as(u32, @intCast(i)) * abi.DESC_WORDS);
                if (ret == abi.ST_OK) ret = st;
            }
        }
        s.box[RET] = ret;
        s.box[ARM_NS] = @truncate(s.clock() -% t0);
        fence();
        s.box[DONE] = seq;
        return true;
    }

    fn memOk(s: *Server, off: u32, size: u32) bool {
        return off % 8 == 0 and size <= s.mirror.len and @as(u64, off) + size <= s.ddr.len * 4;
    }

    fn serveOne(s: *Server, mem: ops.Mem, off: u32, at: u32) u32 {
        var d = ops.Desc{ .w = [_]u32{0} ** abi.DESC_WORDS };
        d.w[abi.W_OP] = s.box[at + abi.W_OP];
        const words: []const u32 = if (isScalar(d.w[abi.W_OP])) &.{ 10, 11, 12, 13, 14, 15 } else &.{ 1, 2, 3, 4, 5, 6, 10, 11 };
        for (words) |w| d.w[w] = s.box[at + w];
        var res = ops.Result{};
        if (isScalar(d.w[abi.W_OP])) {
            res = ops.run(mem, d);
        } else {
            res.status = ops.check(mem, d);
            if (res.status == abi.ST_OK) {
                const sp = ops.spans(d);
                for (sp.in) |x| s.stage(off, x, .in);
                res = ops.run(mem, d);
                for (sp.out) |x| s.stage(off, x, .out);
            }
        }
        s.box[at + abi.W_STATUS] = res.status | abi.SERVED_ARM;
        const r: u64 = @bitCast(res.r);
        s.box[at + abi.W_R] = @truncate(r);
        s.box[at + abi.W_R + 1] = @truncate(r >> 32);
        return res.status;
    }

    /// One span between DDR and the mirror. Spans are 4-aligned (check() passed).
    fn stage(s: *Server, off: u32, x: ops.Span, dir: enum { in, out }) void {
        const first = (off + x.addr) / 4;
        const words = std.mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(s.mirror[x.addr..][0..x.bytes])));
        switch (dir) {
            .in => for (words, 0..) |*w, i| {
                w.* = s.ddr[first + i];
            },
            .out => for (words, 0..) |w, i| {
                s.ddr[first + i] = w;
            },
        }
    }
};

/// Every DDR and mailbox write before it lands before DONE does (ARMv7 dsb; a no-op elsewhere).
fn fence() void {
    if (@import("builtin").cpu.arch == .arm) asm volatile ("dsb" ::: .{ .memory = true });
}
