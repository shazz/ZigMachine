// `glass astro-bench`: what ASTROLABE's ARM side costs, measured on the board (SPIKE,
// docs/ARM_FPU_COPROC.md). Runs beside a running glass and any bitstream: it reads the
// register block, the mailbox page and the cart's DDR window, and writes only REG_SCRATCH
// and the mailbox's last word (no protocol word: a running worker is not disturbed).
//
// Each figure is one access (or one f64 op), timed in batches of BATCH on core 1 with
// CLOCK_MONOTONIC, over ROUNDS batches: min / median / p99 / max in ns. The spread is the
// Linux jitter a cart would see.
const std = @import("std");
const linux = std.os.linux;
const map = @import("map.zig");
const devmem = @import("devmem.zig");

const BATCH = 64;
const ROUNDS = 4000;

fn nowNs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

const Kind = enum { gp0_read, gp0_write, mbox_read, mbox_write, ddr_read, f64_add, f64_div, f64_sqrt, f64_sin };

var sink: u32 = 0;
var fsink: f64 = 1.0;

fn batch(k: Kind, regs: []volatile u32, ddr: []volatile u32) void {
    const last = map.OFF_ASTRO / 4 + map.ASTRO_WORDS - 1;
    var x: f64 = fsink;
    for (0..BATCH) |i| switch (k) {
        .gp0_read => sink +%= regs[map.REG_SCRATCH / 4],
        .gp0_write => regs[map.REG_SCRATCH / 4] = @intCast(i),
        .mbox_read => sink +%= regs[last],
        .mbox_write => regs[last] = @intCast(i),
        .ddr_read => sink +%= ddr[(i * 1031) % ddr.len],
        .f64_add => x = x + 1.0000001,
        .f64_div => x = 1.0 / (x + 1.0),
        .f64_sqrt => x = @sqrt(x + 2.0),
        .f64_sin => x = @sin(x + 0.5),
    };
    fsink = x;
}

fn measure(k: Kind, regs: []volatile u32, ddr: []volatile u32, ns: []u64) void {
    for (ns) |*n| {
        const t0 = nowNs();
        batch(k, regs, ddr);
        n.* = nowNs() - t0;
    }
    std.mem.sort(u64, ns, {}, std.sort.asc(u64));
}

pub fn run() !u8 {
    const board = try devmem.open();
    @import("astro.zig").pinSelf();
    var ns: [ROUNDS]u64 = undefined;
    std.debug.print("ASTRO bench: ns per access/op, {d} x {d} (min med p99 max)\n", .{ ROUNDS, BATCH });
    for (std.enums.values(Kind)) |k| {
        measure(k, board.regs_words, board.ddr_words, &ns);
        const at = struct {
            fn f(v: []const u64, q: usize) f64 {
                return @as(f64, @floatFromInt(v[@min(v.len - 1, v.len * q / 1000)])) / BATCH;
            }
        }.f;
        std.debug.print("ASTRO {s:<10} {d:8.1} {d:8.1} {d:8.1} {d:8.1}\n", .{ @tagName(k), at(&ns, 0), at(&ns, 500), at(&ns, 990), at(&ns, 1000) });
    }
    std.debug.print("ASTRO mailbox magic {X:0>8} beat {d}\n", .{ board.regs_words[map.OFF_ASTRO / 4], board.regs_words[map.OFF_ASTRO / 4 + 2] });
    return 0;
}
