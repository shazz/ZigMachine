// --------------------------------------------------------------------------
// SysInfo — what the machine IS, asked once at start (the slow questions: a
// coprocessor round trip, a job, the network card, a blitter list). Every
// answer comes from a call the cart is given; where none answers, the page
// says n/a. The pages read this struct and never ask again.
//
//   host       the board writes an ASTROLABE descriptor's W_CYCLES (ZIGGY's cycles
//              of the call, 0 everywhere else: machine/sdk/astro.zig), so cycles != 0
//              is the KESTREL board; else a host clock (hostMicros) is the browser's
//              page; neither: the native host or a harness (no clock, no cycles)
//   frequency  board only: a batch of ASTRO calls bracketed by hostMicros, the
//              cycles they report divided by the microseconds they took
//   astro      the descriptor's SERVED_ARM bit: the ARM's VFPv3, or the machine's code
//   jobs       zg.bard.job: a CRC-32 job posted to a coprocessor (BARD on the board,
//              the page's loader in the browser) or served by the cart itself
//   kos        rom_sdk.kos.vars(): KOS's system variables (version, RAM, boot device)
//   net        zg.net.info(): ZIGNIC's card, when the host has one
//   queue      the blitter's QUEUE (CHISEL v2, HW 1.11.0): a one-op list that FILLs
//              8 pixels of a hidden plane, read back
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const hw = @import("hardware");
const rom = @import("rom_sdk");
const bench = @import("bench.zig");

pub const Host = enum(u8) { board, browser, unclocked };
pub const Jobs = enum(u8) { coprocessor, ziggy, failed };

pub const Ident = struct {
    host: Host = .unclocked,
    astro_ok: bool = false, // the machine ran the descriptor (ST_OK)
    astro_arm: bool = false, // ... on the ARM
    mhz10: u32 = 0, // measured cart CPU clock x10, 0 = not measurable here
    jobs: Jobs = .failed,
    job_cycles: u32 = 0, // what the CRC job cost its server (BARD's counter; 0 elsewhere)
    kos: ?rom.kos.SysVars = null,
    net: ?zg.net.abi.Info = null,
    queue_ok: bool = false,
    desk_ok: bool = false,
};

const astro_abi = hw.astro;
const BATCH: usize = 96;
const FREQ_BUDGET_US: u32 = 2000;

/// Ask everything once. `spare` is a hidden plane for the QUEUE's read-back.
pub fn probe(spare: *zg.LogicalFB) Ident {
    var id: Ident = .{};
    astro(&id);
    if (id.host == .board) id.mhz10 = frequency();
    jobs(&id);
    id.kos = if (rom.kos.vars()) |v| v.* else null;
    id.net = zg.net.info();
    id.queue_ok = queueTest(spare);
    id.desk_ok = hw.hwDeskAvailable() != 0;
    return id;
}

fn astro(id: *Ident) void {
    var d = [_]zg.astro.Desc{.{ .op = astro_abi.OP_SQRT, .s0 = 2.0 }}; // init only: no float per frame
    _ = zg.astro.run(&d);
    id.astro_ok = d[0].status & 0xFF == astro_abi.ST_OK;
    id.astro_arm = zg.astro.servedByArm(d[0]);
    id.host = if (d[0].cycles != 0) .board else if (bench.micros() != 0) .browser else .unclocked;
}

/// ZIGGY's cycles a microsecond, x10: each ASTRO call bracketed by the host clock, its own
/// cycle count (W_CYCLES) over its own microseconds, so the loop's gaps count in neither. A call
/// is BATCH descriptors long, so the clock's 1 us grain is well under 1 % of it.
fn frequency() u32 {
    var d: [BATCH]zg.astro.Desc = undefined;
    const start = bench.micros();
    if (start == 0) return 0; // no clock to divide by
    var cycles: u64 = 0;
    var us: u64 = 0;
    while (bench.micros() -% start < FREQ_BUDGET_US) {
        for (&d) |*x| x.* = .{ .op = astro_abi.OP_SQRT, .s0 = 2.0 };
        const t0 = bench.micros();
        _ = zg.astro.run(&d);
        us += bench.micros() -% t0;
        if (d[0].cycles == 0) return 0;
        cycles += d[0].cycles;
    }
    return if (us == 0) 0 else @intCast(cycles * 10 / us);
}

var job_buf: [1024]u8 align(4) = undefined;
var job_out: [1]u32 = undefined; // one chunk: the whole buffer
const CHUNK_LOG2: u32 = 10; // the server takes the chunk as its log2 (bard_jobs/server.zig): 1 KB

fn jobs(id: *Ident) void {
    for (&job_buf, 0..) |*b, i| b.* = @truncate(i *% 7 +% 3);
    const where = zg.bard.job.open(.coprocessor);
    const t = zg.bard.job.post(.crc32, &.{ addr(&job_buf), job_buf.len, CHUNK_LOG2, addr(&job_out) });
    zg.bard.job.wait(t);
    const r = zg.bard.job.result(t);
    // out[0] = the one chunk's CRC-32 (zlib's); the job's result is the CRC of the out words
    const ok = r.err == 0 and job_out[0] == std.hash.Crc32.hash(&job_buf) and
        r.result == std.hash.Crc32.hash(std.mem.sliceAsBytes(&job_out));
    id.job_cycles = r.cycles;
    id.jobs = if (!ok) .failed else if (where == .coprocessor and zg.bard.job.isRemote()) .coprocessor else .ziggy;
    zg.bard.job.close();
}

fn addr(p: anytype) u32 {
    return @intCast(@intFromPtr(p));
}

fn queueTest(fb: *zg.LogicalFB) bool {
    const v: u8 = 0x5A;
    @memset(fb.fb[0..8], 0);
    var q: zg.blit_queue.Queue = undefined;
    q.init(@intCast(hw.hwVideoBase()));
    q.set(&.{
        .{ .k = @intCast((hw.BLIT_D_BASE - hw.OFF_BLIT) / 4), .v = @intCast(@intFromPtr(fb.fb) - @as(usize, @intCast(hw.hwVideoBase()))) },
        .{ .k = @intCast((hw.BLIT_D_STRIDE - hw.OFF_BLIT) / 4), .v = @intCast(fb.stride) },
    });
    q.fill(0, 0, 8, 1, v);
    q.flush();
    var ok = true;
    for (fb.fb[0..8]) |b| ok = ok and b == v;
    @memset(fb.fb[0..8], 0);
    return ok;
}
