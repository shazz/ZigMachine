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
// clock after every chunk of samples (app.zig: 16 on ZIGGY, one ASTROLABE batch),
// so the frame rate holds on a fast machine and on a slow one alike.
//
// Two numbers, both from hostMicros alone, both summed over the frames' TRACING
// time (painting included, the machine's compositing and idle frames not):
//   - the RATE: first-picture pixels over the first picture's time; the
//     refinement passes are booked apart and never enter it;
//   - the time to CONVERGE: the first picture's time plus every pass's.
extern fn hostMicros() u32;

pub const BUDGET_US: u32 = 8000; // half a 60 Hz tick: the rest is the machine's
pub const FIXED_PIXELS: u32 = 512; // a frame's work when the host has no clock

pub const Bench = struct {
    clocked: bool, // the host's clock has answered non-zero at least once
    trace_us: u64, // the first picture's
    refine_us: u64, // the refinement passes'

    pub fn reset(self: *Bench) void {
        self.trace_us = 0;
        self.refine_us = 0;
    }

    /// Microseconds of work over all passes so far: the time to converge once they are done.
    pub fn totalMicros(self: *const Bench) u64 {
        return self.trace_us + self.refine_us;
    }

    fn book(self: *Bench, first: bool, dt: u32) void {
        if (first) self.trace_us += dt else self.refine_us += dt;
    }

    /// The frame's start time, or null when the host has no clock.
    pub fn begin(self: *Bench) ?u32 {
        const t = hostMicros();
        if (t != 0) self.clocked = true;
        return if (self.clocked) t else null;
    }

    /// Whether the frame begun at `t0` has used its budget; books the time spent
    /// to the first picture or to the refinement.
    pub fn spent(self: *Bench, t0: u32, first: bool) bool {
        const dt = hostMicros() -% t0;
        if (dt < BUDGET_US) return false;
        self.book(first, dt);
        return true;
    }

    /// Books a frame that ended for another reason (its pass completed).
    pub fn finish(self: *Bench, t0: u32, first: bool) void {
        self.book(first, hostMicros() -% t0);
    }

    pub fn pixelsPerSecond(self: *const Bench, pixels: u32) u32 {
        if (self.trace_us == 0) return 0;
        return @intCast(@min(@as(u64, pixels) * 1_000_000 / self.trace_us, 0xFF_FFFF));
    }
};
