// --------------------------------------------------------------------------
// SysInfo page 5 — SPEED TESTS: each test's time a rep on this machine, and
// its speed in % of a reference machine, as SysInfo shows a stock ST = 100 %.
// The reference is switched with Up / Down or C (refs.zig: ST, STE, Mega STE,
// TT030, Falcon030, CT60, each from a published CoreMark result); the results
// are not re-run, only the percentages recomputed. stref.zig says how the ST's
// own time is counted. The f32 test is set against the integer multiply-add on
// the same machine instead: an ST has no FPU, and that ratio is what shows
// whether f32 runs in hardware here or in software.
// --------------------------------------------------------------------------
const grid = @import("grid.zig");
const pages = @import("pages.zig");
const bench = @import("bench.zig");
const st = @import("stref.zig");
const k = @import("kernels.zig");
const refs = @import("refs.zig");

const ROW0: usize = 5;

// In bench.Test's order; the work is the kernels' own constants.
const Row = struct { name: []const u8, units: u32, what: []const u8 };
const ROWS = [bench.COUNT]Row{
    .{ .name = "INTEGER ADD/EOR", .units = k.INT_N, .what = "LOOPS" },
    .{ .name = "INTEGER MUL-ADD", .units = k.INT_N, .what = "LOOPS" },
    .{ .name = "F32 MUL-ADD", .units = k.INT_N, .what = "LOOPS" },
    .{ .name = "CLEAR, CPU LOOP", .units = k.PLANE_BYTES, .what = "BYTES" },
    .{ .name = "CLEAR, BLITTER", .units = k.PLANE_BYTES, .what = "BYTES" },
    .{ .name = "COPY, CPU LOOP", .units = k.PLANE_BYTES, .what = "BYTES" },
    .{ .name = "COPY, BLITTER", .units = k.PLANE_BYTES, .what = "BYTES" },
    .{ .name = "STORE SCATTER", .units = k.SCATTER_N, .what = "BYTES" },
};

pub fn fill(g: *grid.Grid, c: *const pages.Ctx) void {
    const ref = refs.REFS[c.ref];
    pages.heading(g, 2, 0, "SPEED TESTS:");
    g.print(2, grid.COL2, "REFERENCE: {s} = 100 %", .{ref.name});
    g.print(3, grid.COL2, "{s}", .{ref.source});
    g.put(4, 0, "TEST", .under);
    g.put(4, 20, "WORK", .under);
    g.put(4, 36, "TIME A REP", .under);
    g.put(4, 54, "SPEED", .under);
    for (ROWS, 0..) |r, i| line(g, c.bench, i, r, ref);
    footer(g, c.bench, ref, c.ref);
}

fn line(g: *grid.Grid, b: *const bench.Bench, i: usize, r: Row, ref: refs.Ref) void {
    const row = ROW0 + i;
    const which: bench.Test = @enumFromInt(i);
    const res = b.results[i];
    g.put(row, 0, r.name, .plain);
    g.print(row, 20, "{d} {s}", .{ r.units, r.what });
    if (b.next == i) return g.put(row, 36, "RUNNING...", .inverse);
    if (b.next < i or res.reps == 0) return g.put(row, 36, "-", .plain);
    var t: [24]u8 = undefined;
    const us = st.perRep10(res) orelse return g.put(row, 36, pages.N_A, .plain);
    g.print(row, 36, "{s} US", .{pages.tenths(&t, us)});
    speed(g, row, b, which, res, ref);
}

fn speed(g: *grid.Grid, row: usize, b: *const bench.Bench, which: bench.Test, res: st.Result, ref: refs.Ref) void {
    if (bench.stMicros(which)) |st_us| {
        const pct = refs.percent(refs.refMicros(st_us, ref), res.reps, res.us) orelse return;
        return g.print(row, 54, "{d:>8} % OF {s}", .{ pct, ref.name });
    }
    if (which != .f32_mul) return g.put(row, 54, "(F32'S REFERENCE)", .plain);
    const base = b.results[@intFromEnum(bench.Test.int_mul)];
    const x = st.timesRef(res, base) orelse return;
    g.print(row, 54, "{d}.{d:0>2} x INT MUL-ADD", .{ x / 100, x % 100 });
}

fn footer(g: *grid.Grid, b: *const bench.Bench, ref: refs.Ref, i: u8) void {
    if (!b.clocked and !b.running() and b.results[0].reps != 0) {
        g.put(14, 0, "THE HOST HAS NO CLOCK (hostMicros = 0): EACH TEST RAN ONCE, UNTIMED.", .plain);
    }
    g.print(15, 0, "A TEST REPEATS FOR {d} MS OF THE HOST'S CLOCK. R: RUN THEM AGAIN.", .{bench.BUDGET_US / 1000});
    g.print(16, 0, "UP/DOWN OR C: REFERENCE {d}/{d}, {s} ({s})", .{ i + 1, refs.COUNT, ref.name, ref.cpu });
    pages.heading(g, 17, 0, "THE ST'S LOOPS (68000 CYCLES AT 8 MHZ):");
    g.print(18, 0, "INTEGER  add.l d1,d0 / eor.l d0,d1 / dbra        {d} CYCLES A LOOP", .{st.ST_INT_CYCLES});
    g.print(19, 0, "CLEAR    move.l d0,(a0)+ / dbra                  {d} CYCLES A LONG", .{st.ST_CLEAR_CYCLES});
    g.print(20, 0, "COPY     move.l (a0)+,(a1)+ / dbra               {d} CYCLES A LONG", .{st.ST_COPY_CYCLES});
    g.print(21, 0, "SCATTER  add.w / and.w / move.b d0,0(a0,d2) / dbra {d} CYCLES A BYTE", .{st.ST_SCATTER_CYCLES});
    g.put(22, 0, "THE BLITTER ROWS' REFERENCE IS THE CPU LOOP (A STOCK ST HAS NO BLITTER).", .plain);
    if (ref.coremark100 != refs.ST_COREMARK100) g.put(23, 0, "NOT THE ST: ITS TIMES ARE THE ST'S SCALED BY COREMARK, ESTIMATED.", .plain);
}
