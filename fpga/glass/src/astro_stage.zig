// ASTROLABE's staging for one request (docs/hardware/studies/ARM_FPU_COPROC.md section 4): the cart's arrays
// between its memory in DDR and glass's cached mirror, each byte moved at most once a call.
//
// Before: every descriptor copied its inputs in and its outputs out, word by word through the
// uncached window, so a march step of 48 descriptors over 21 arrays moved each array 3-7 times.
// Now `fresh` remembers which mirror bytes hold the cart's current values this call (read in,
// or written by a kernel) and `dirty` which of them DDR has not seen yet: an input is read only
// where it is not fresh, an output only marked, and `flush` writes the dirty bytes back once,
// before DONE. Reading a range that a kernel already wrote would clobber its result with DDR's
// stale copy: the fresh set is what makes skipping the read correct, not just fast.
//
// The copies are injectable (astro_copy's bursts on the board, counters in the tests).
const std = @import("std");
const copy = @import("astro_copy.zig");
const abi = @import("astro_ops").abi;

pub const CAP: usize = 256; // ranges a set holds
comptime {
    // 3 in + 2 out spans a descriptor: every span of a full request fits even unmerged
    if (abi.MAX_COUNT * 5 > CAP) @compileError("astro_stage: CAP below a full request's spans");
}

/// Byte ranges [lo, hi) of cart memory, sorted, disjoint and not touching (merged).
pub const Set = struct {
    lo: [CAP]u32 = undefined,
    hi: [CAP]u32 = undefined,
    len: usize = 0,

    pub fn add(s: *Set, lo: u32, hi: u32) void {
        var a = lo;
        var b = hi;
        var i: usize = 0;
        while (i < s.len and s.hi[i] < a) i += 1; // the first range that touches or follows
        var j = i;
        while (j < s.len and s.lo[j] <= b) : (j += 1) { // every range [lo, hi] touches: merged
            a = @min(a, s.lo[j]);
            b = @max(b, s.hi[j]);
        }
        const removed = j - i;
        if (removed == 0) {
            std.debug.assert(s.len < CAP);
            std.mem.copyBackwards(u32, s.lo[i + 1 .. s.len + 1], s.lo[i..s.len]);
            std.mem.copyBackwards(u32, s.hi[i + 1 .. s.len + 1], s.hi[i..s.len]);
            s.len += 1;
        } else if (removed > 1) {
            std.mem.copyForwards(u32, s.lo[i + 1 ..], s.lo[j..s.len]);
            std.mem.copyForwards(u32, s.hi[i + 1 ..], s.hi[j..s.len]);
            s.len -= removed - 1;
        }
        s.lo[i] = a;
        s.hi[i] = b;
    }
};

pub const Load = *const fn (dst: [*]u32, src: [*]const volatile u32, n: usize) void;
pub const Store = *const fn (dst: [*]volatile u32, src: [*]const u32, n: usize) void;

pub const Stage = struct {
    fresh: Set = .{},
    dirty: Set = .{},
    load: Load = copy.load,
    store: Store = copy.store,

    /// A new request: nothing in the mirror is trusted.
    pub fn begin(st: *Stage) void {
        st.fresh.len = 0;
        st.dirty.len = 0;
    }

    /// The mirror's [addr, addr + bytes) is to hold the cart's values: read what is not fresh.
    /// `win` = the DDR window from cart address 0 (4-aligned, as addr and bytes are).
    pub fn need(st: *Stage, win: [*]const volatile u32, mirror: [*]u32, addr: u32, bytes: u32) void {
        if (bytes == 0) return;
        var at = addr;
        const end = addr + bytes;
        for (st.fresh.lo[0..st.fresh.len], st.fresh.hi[0..st.fresh.len]) |lo, hi| {
            if (hi <= at) continue;
            if (lo >= end) break;
            if (lo > at) st.load(mirror + at / 4, win + at / 4, (lo - at) / 4);
            at = @max(at, hi);
            if (at >= end) break;
        }
        if (at < end) st.load(mirror + at / 4, win + at / 4, (end - at) / 4);
        st.fresh.add(addr, end);
    }

    /// A kernel wrote the mirror's [addr, addr + bytes): fresh, and owed to DDR.
    pub fn wrote(st: *Stage, addr: u32, bytes: u32) void {
        if (bytes == 0) return;
        st.fresh.add(addr, addr + bytes);
        st.dirty.add(addr, addr + bytes);
    }

    /// Every dirty range back to DDR, once. The caller fences before DONE.
    pub fn flush(st: *Stage, win: [*]volatile u32, mirror: [*]const u32) void {
        for (st.dirty.lo[0..st.dirty.len], st.dirty.hi[0..st.dirty.len]) |lo, hi|
            st.store(win + lo / 4, mirror + lo / 4, (hi - lo) / 4);
        st.begin();
    }
};
