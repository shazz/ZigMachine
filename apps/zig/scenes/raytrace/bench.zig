// The benchmark clock: how much tracing a frame does, and the measured rate.
//
// hostMicros() is a free-running microsecond counter the HOST provides
// (performance.now() in docs/sealed-loader.js, the cycle counter on the FPGA
// board through fpga/tools/host_gen.py's HOST_MICROS hook). A host that does
// not provide it answers 0 (the harnesses' and host_gen's no-op stub), and the
// cart then does a FIXED amount of work a frame instead, which is what keeps
// the gate's frame counts and fingerprints deterministic. decisions.md
// 2026-10-10: a benchmark aid only, never a screen's choreography.
//
// With a clock, a frame traces until BUDGET_US of it is spent, reading the
// clock every CHECK_EVERY pixels, so the frame rate holds on a fast machine and
// on a slow one alike; the rate is pixels traced over microseconds spent
// tracing (painting the blocks included, the machine's compositing not).
extern fn hostMicros() u32;

pub const BUDGET_US: u32 = 8000; // half a 60 Hz tick: the rest is the machine's
pub const CHECK_EVERY: u32 = 16;
pub const FIXED_PIXELS: u32 = 512; // a frame's work when the host has no clock

/// Whether a frame begun at `t0` has used its budget, booking nothing (the
/// f32 cart's refinement passes, which are not part of the benchmark).
pub fn over(t0: u32) bool {
    return hostMicros() -% t0 >= BUDGET_US;
}

pub const Bench = struct {
    clocked: bool, // the host's clock has answered non-zero at least once
    trace_us: u64,

    pub fn reset(self: *Bench) void {
        self.trace_us = 0;
    }

    /// The frame's start time, or null when the host has no clock.
    pub fn begin(self: *Bench) ?u32 {
        const t = hostMicros();
        if (t != 0) self.clocked = true;
        return if (self.clocked) t else null;
    }

    /// Whether the frame begun at `t0` has used its budget; books the time spent.
    pub fn spent(self: *Bench, t0: u32) bool {
        const dt = hostMicros() -% t0;
        if (dt < BUDGET_US) return false;
        self.trace_us += dt;
        return true;
    }

    /// Books a frame that ended for another reason (the picture completed).
    pub fn finish(self: *Bench, t0: u32) void {
        self.trace_us += hostMicros() -% t0;
    }

    pub fn pixelsPerSecond(self: *const Bench, pixels: u32) u32 {
        if (self.trace_us == 0) return 0;
        return @intCast(@min(@as(u64, pixels) * 1_000_000 / self.trace_us, 0xFF_FFFF));
    }

    pub fn nanosPerPixel(self: *const Bench, pixels: u32) u32 {
        if (pixels == 0) return 0;
        return @intCast(@min(self.trace_us * 1000 / pixels, 999_999));
    }
};
