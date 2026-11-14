// ASTROLABE's worker on the board (SPIKE, docs/ARM_FPU_COPROC.md): a thread pinned to the
// second Cortex-A9 that busy-polls the mailbox and serves each request (astro_box.zig) with
// the VFPv3's f64 (glass is built -Dcpu=cortex_a9, hard-float: `zig build` targets
// arm-linux-musleabihf).
//
// Polling: a spin while requests come (the first answer is what a cart's per-op latency is
// made of), a 1 ms nap after IDLE_MS without one, so an idle console does not burn a core.
// The first request after a nap waits up to that millisecond: bastro.c's TAKE timeout is
// longer. For the least jitter the core can be kept from Linux altogether (isolcpus=1 in the
// kernel's bootargs: docs/ARM_FPU_COPROC.md, "Jitter"); glass then still pins itself there.
const std = @import("std");
const linux = std.os.linux;
const map = @import("map.zig");
const box = @import("astro_box.zig");

pub const CORE: usize = 1;
pub const IDLE_MS: u64 = 2000;
pub const MIRROR_BYTES: usize = 8 << 20; // the cart's whole memory (memmap ROM_RAM_TOP)

fn nowNs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

/// Pin the calling thread to CORE (astro_bench.zig measures from there too).
pub fn pinSelf() void {
    pin(CORE);
}

fn pin(core: usize) void {
    var set: linux.cpu_set_t = std.mem.zeroes(linux.cpu_set_t);
    set[core / @bitSizeOf(usize)] |= @as(usize, 1) << @intCast(core % @bitSizeOf(usize));
    linux.sched_setaffinity(0, &set) catch |err| std.log.warn("ASTRO: pin to core {d}: {t} (runs unpinned)", .{ core, err });
}

/// Serve forever. Exported for `glass astro` (a foreground worker, for the lead's measurements).
pub fn serve(regs: []volatile u32, ddr: []volatile u32, mirror: []u8) noreturn {
    pin(CORE);
    const words = regs[map.OFF_ASTRO / 4 ..][0..map.ASTRO_WORDS];
    var s = box.Server{ .box = words, .ddr = ddr, .mirror = mirror, .last = words[box.SEQ], .clock = nowNs };
    words[box.VERSION] = box.PROTO;
    words[box.MAGIC] = box.ID;
    var last_req = nowNs();
    const nap = linux.timespec{ .sec = 0, .nsec = 1_000_000 };
    while (true) {
        if (s.poll()) {
            last_req = nowNs();
            continue;
        }
        if (nowNs() - last_req < IDLE_MS * 1_000_000) continue;
        words[box.BEAT] +%= 1;
        _ = linux.nanosleep(&nap, null);
    }
}

/// The board's worker thread, started once at glass's start (main.zig). A PL without the
/// mailbox reads its page as 0 and drops writes: the thread still runs, and nobody calls it.
pub fn startThread(regs: []volatile u32, ddr: []volatile u32) void {
    const S = struct {
        var mirror: [MIRROR_BYTES]u8 align(8) = undefined;
        fn loop(r: []volatile u32, d: []volatile u32) void {
            serve(r, d, &mirror);
        }
    };
    const t = std.Thread.spawn(.{}, S.loop, .{ regs, ddr }) catch |err| return std.log.warn("ASTRO: worker thread: {t}", .{err});
    t.detach();
}
