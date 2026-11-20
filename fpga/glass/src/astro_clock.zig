// ASTROLABE's worker clock (astro.zig): ARM_NS for every request without a syscall.
//
// On this kernel CLOCK_MONOTONIC is a real syscall (~1 us: the clocksource is the A9's global
// timer, which ARM32's vDSO cannot read; `glass astro-bench` row `clock`), and the worker read
// it twice a request plus once every empty poll. The same global timer (64-bit, at the CPU's
// PERIPHCLK) is a few tens of ns through /dev/mem; its rate is taken against CLOCK_MONOTONIC
// once at start. Without the mapping (not the board, or /dev/mem refused) the syscall stays.
const std = @import("std");
const linux = std.os.linux;

const GTIMER_PAGE: u32 = 0xF8F0_0000; // the A9 MPCore private region (Zynq-7000 TRM, table 4-1)
const GTIMER_LO: usize = 0x200 / 4; // Global Timer Counter, low then high word
const CAL_NS: u64 = 20_000_000;

var regs: ?[*]volatile u32 = null;
var ns_q32: u64 = 0; // ns per tick, Q32.32
var base_ticks: u64 = 0;
var base_ns: u64 = 0;

pub fn sysNs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

fn ticks(r: [*]volatile u32) u64 {
    while (true) { // the high word read on both sides of the low one: no torn carry
        const hi = r[GTIMER_LO + 1];
        const lo = r[GTIMER_LO];
        if (r[GTIMER_LO + 1] == hi) return @as(u64, hi) << 32 | lo;
    }
}

/// Monotonic ns: the global timer once `init` found it, else CLOCK_MONOTONIC.
pub fn nowNs() u64 {
    const r = regs orelse return sysNs();
    const dt: u128 = ticks(r) -% base_ticks;
    return base_ns + @as(u64, @truncate((dt * ns_q32) >> 32));
}

/// Map the global timer and measure its rate (CAL_NS of sleep). Call once, from the worker.
pub fn init() void {
    const fd = linux.open("/dev/mem", .{ .ACCMODE = .RDONLY, .SYNC = true, .CLOEXEC = true }, 0);
    if (linux.errno(fd) != .SUCCESS) return;
    defer _ = linux.close(@intCast(fd));
    const rc = linux.mmap(null, 4096, .{ .READ = true }, .{ .TYPE = .SHARED }, @intCast(fd), GTIMER_PAGE);
    if (linux.errno(rc) != .SUCCESS) return;
    const r: [*]volatile u32 = @ptrFromInt(rc);
    const t0, const n0 = .{ ticks(r), sysNs() };
    const nap = linux.timespec{ .sec = 0, .nsec = CAL_NS };
    _ = linux.nanosleep(&nap, null);
    const t1, const n1 = .{ ticks(r), sysNs() };
    if (t1 <= t0 or n1 <= n0) return std.log.warn("ASTRO: the global timer does not count: CLOCK_MONOTONIC", .{});
    ns_q32 = @intCast((@as(u128, n1 - n0) << 32) / (t1 - t0));
    base_ticks, base_ns = .{ t1, n1 };
    regs = r;
}
