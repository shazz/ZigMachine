// --------------------------------------------------------------------------
// SysInfo — the speed tests, run one a frame so the page shows each result as
// it lands (and a frame never holds more than one test).
//
// Timed with env.hostMicros (decisions.md 2026-10-10: a host clock for
// BENCHMARKS only). A test repeats its kernel until BUDGET_US have passed, so
// a fast host and a slow board both get a reading well above the browser's
// ~0.1 ms clock grain. A host without the clock answers 0: each kernel then
// runs ONCE and its result says n/a, which keeps the gate's frames identical.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const k = @import("kernels.zig");
const st = @import("stref.zig");

extern fn hostMicros() u32;

pub const BUDGET_US: u32 = 4000;
const MAX_REPS: u32 = 4096;

pub const Test = enum(u8) { int_add, int_mul, f32_mul, clear_cpu, clear_blit, copy_cpu, copy_blit, scatter };
pub const COUNT = @typeInfo(Test).@"enum".fields.len;

/// What the kernels work on: two spare planes, the blitter, a 64 KB buffer.
pub const Target = struct {
    os: *zg.ZigOS,
    blit: *zg.Blitter,
    scratch: *[k.SCATTER_BYTES]u8,
};

pub const Bench = struct {
    results: [COUNT]st.Result,
    next: u8, // the test the next step() runs; COUNT = all done
    clocked: bool, // hostMicros has answered non-zero
    sink: u32, // every kernel's result lands here, so none is optimised away

    pub fn reset(self: *Bench) void {
        self.results = [_]st.Result{.{}} ** COUNT;
        self.next = COUNT; // nothing runs until start()
        self.clocked = false;
        self.sink = 0;
    }

    pub fn start(self: *Bench) void {
        self.results = [_]st.Result{.{}} ** COUNT;
        self.next = 0;
    }

    /// Every kernel once, untimed, at start: a JIT host (the browser's wasm
    /// engine) compiles its optimised code in the background after a function's
    /// first runs, so tests run frames later time that code, not the first tier.
    pub fn warmUp(self: *Bench, t: Target) void {
        for (0..COUNT) |i| self.runOnce(@enumFromInt(i), t, 0);
    }

    pub fn running(self: *const Bench) bool {
        return self.next < COUNT;
    }

    /// Run the next test, all its reps, and book the time.
    pub fn step(self: *Bench, t: Target) void {
        if (!self.running()) return;
        const which: Test = @enumFromInt(self.next);
        var t0 = self.now();
        if (self.clocked) { // one untimed rep first: a JIT host compiles the loop on its first run
            self.runOnce(which, t, 0);
            t0 = self.now();
        }
        var reps: u32 = 0;
        var spent: u32 = 0;
        while (true) {
            self.runOnce(which, t, reps);
            reps += 1;
            if (!self.clocked) break; // no clock: one rep, n/a
            spent = self.now() -% t0;
            if (spent >= BUDGET_US or reps >= MAX_REPS) break;
        }
        self.results[self.next] = .{ .reps = reps, .us = if (self.clocked) @max(spent, 1) else 0 };
        self.next += 1;
    }

    fn now(self: *Bench) u32 {
        const t = hostMicros();
        if (t != 0) self.clocked = true;
        return t;
    }

    fn runOnce(self: *Bench, which: Test, t: Target, rep: u32) void {
        const seed = rep *% 0x0101_0101 +% self.next;
        const planes = &t.os.lfbs;
        switch (which) {
            .int_add => self.sink +%= k.intAdd(seed),
            .int_mul => self.sink +%= k.intMul(seed),
            .f32_mul => self.sink +%= k.f32MulAdd(seed),
            .clear_cpu => k.clearCpu(&planes[1], seed),
            .clear_blit => k.clearBlit(t.blit, &planes[1], @truncate(seed)),
            .copy_cpu => k.copyCpu(&planes[2], &planes[1]),
            .copy_blit => k.copyBlit(t.blit, &planes[2], &planes[1]),
            .scatter => k.scatter(t.scratch, seed),
        }
        std.mem.doNotOptimizeAway(self.sink);
    }
};

/// The host's clock, for the app's frame timer: 0 = no clock.
pub fn micros() u32 {
    return hostMicros();
}

/// A stock ST's time for one rep of `which` (us), or null: no ST row.
pub fn stMicros(which: Test) ?u64 {
    return switch (which) {
        .int_add => st.stMicros(st.ST_INT_CYCLES, k.INT_N),
        .clear_cpu, .clear_blit => st.stMicros(st.ST_CLEAR_CYCLES, k.PLANE_BYTES / 4),
        .copy_cpu, .copy_blit => st.stMicros(st.ST_COPY_CYCLES, k.PLANE_BYTES / 4),
        .scatter => st.stMicros(st.ST_SCATTER_CYCLES, k.SCATTER_N),
        .int_mul, .f32_mul => null,
    };
}
