// --------------------------------------------------------------------------
// zg.bard.job: jobs for a coprocessor (system table 1.24, docs/ZIGOS_API.md
// "BARD jobs", decisions.md 2026-11-13). The cart posts a job (an op and its
// arrays, all in its own memory) and goes on with its frame; a server outside
// the cart's frame runs it and answers in the job's slot:
//   board   BARD, the sound CPU, between its audio renders (it reads and writes
//           the cart's DDR; fpga/cycles/sound/sjobs.c)
//   page    the loader, after the cart's frame (docs/sealed-loader.js)
//   none    (the native host, the harnesses, ZIGGY with no BARD): the cart
//           serves its own jobs at once, inside its frame.
// The same kernels everywhere (bard_jobs/kernels.zig), so the bytes a job
// writes never depend on who ran it. The rules a cart keeps:
//   - everything a job reads is written BEFORE post(); nothing it writes is read
//     before wait() says it is done (the board's D-cache is dropped then);
//   - double-buffer: post frame N+1's job, draw frame N's answer;
//   - at most SLOTS jobs in flight (post waits for the oldest past that);
//   - no divide and no float in a job: BARD has neither (reciprocal tables).
// --------------------------------------------------------------------------
const L = @import("bard_jobs/layout.zig");
const S = @import("bard_jobs/server.zig");
const zx0 = @import("depackers").zx0; // zigos imports the depackers module (build.zig, sdk/build_cart.zig)

extern fn hostBardJob(op: u32, arg: u32) u32;

pub const Op = L.Op;
pub const Err = L.Err;
pub const Job = L.Job;
pub const Point = L.Point;
pub const Xform = L.Xform;
pub const Particle = L.Particle;
pub const Physics = L.Physics;
pub const OFF = L.OFF;
pub const SLOTS = L.SLOTS;
const kernels = @import("bard_jobs/kernels.zig");
pub const crcTable = kernels.crc_table;
/// The particles' respawn hash, for a cart that seeds its first frame the same way.
pub const hash = kernels.hash;

/// hostBardJob's ops (the import's first argument).
pub const HOST_OPEN: u32 = 0; // arg: the block (0 closes). 1: a server outside the cart takes it
pub const HOST_KICK: u32 = 1; // arg: head. The server may start now
pub const HOST_POLL: u32 = 2; // arg: a ticket. 1: done (the board dropped ZIGGY's D-cache)
pub const HOST_WAIT: u32 = 3; // arg: a ticket. 1: done; 0: the server never answered

/// Who serves: ZIGGY (the cart, inside its frame) or the coprocessor.
pub const Where = enum { ziggy, coprocessor };

const NoClock = struct {
    pub fn now() u32 {
        return 0;
    }
};

var block: [L.BLOCK_BYTES / 4]u32 align(64) = [_]u32{0} ** (L.BLOCK_BYTES / 4);
var srv: S.Server(NoClock, zx0) = .{};
var head: u32 = 0;
var remote: bool = false; // a server outside the cart's frame has the block
var opened: bool = false;

fn hw(i: u32) *volatile u32 {
    return @ptrCast(&block[i]);
}

fn slot(t: u32) *volatile L.Job {
    return @ptrCast(@alignCast(&block[L.HEAD_WORDS + L.JOB_WORDS * (t & (L.SLOTS - 1))]));
}

fn mem() S.Mem {
    return .{ .base = 0, .size = @intCast(@wasmMemorySize(0) * 65536) };
}

/// Serve the jobs `where` says. Waits for every job in flight first. Answers where they will
/// really run: .ziggy when no coprocessor answers here.
pub fn open(where: Where) Where {
    if (opened) close();
    if (hw(L.H.magic).* != L.MAGIC) { // the first open: no slot holds a job (a zeroed slot 0 would pass for job 0)
        for (0..L.SLOTS) |i| {
            slot(@intCast(i)).seq = L.NONE;
            slot(@intCast(i)).done = L.NONE;
        }
    }
    hw(L.H.slots).* = L.SLOTS;
    hw(L.H.head).* = head;
    hw(L.H.magic).* = L.MAGIC;
    const at: u32 = @intCast(@intFromPtr(&block));
    remote = where == .coprocessor and hostBardJob(HOST_OPEN, at) != 0;
    _ = srv.open(mem(), at, head);
    opened = true;
    return if (remote) .coprocessor else .ziggy;
}

pub fn close() void {
    if (!opened) return;
    drain();
    if (remote) _ = hostBardJob(HOST_OPEN, 0);
    remote = false;
    opened = false;
}

fn drain() void {
    var t = head -% L.SLOTS;
    while (t != head) : (t +%= 1) {
        if (slot(t).seq == t) wait(t);
    }
}

/// Post a job: `op` and its arguments (layout.zig's Op says which). Returns its ticket.
pub fn post(op: Op, args: []const u32) u32 {
    if (!opened) _ = open(.ziggy);
    const t = head;
    if (slot(t).seq == t -% L.SLOTS) wait(t -% L.SLOTS); // the slot's last job must be over
    const j = slot(t);
    j.op = @intFromEnum(op);
    for (0..L.ARGS) |i| j.a[i] = if (i < args.len) args[i] else 0;
    j.done = L.NONE;
    j.seq = t; // last: the slot is whole
    head = t +% 1;
    hw(L.H.head).* = head;
    if (remote) {
        _ = hostBardJob(HOST_KICK, head);
    } else {
        _ = srv.step(head, 0xFFFF_FFFF);
    }
    return t;
}

/// The job's answer is in (non-blocking).
pub fn done(t: u32) bool {
    if (slot(t).done == t) return true;
    return remote and hostBardJob(HOST_POLL, t) != 0 and slot(t).done == t;
}

/// Block until job `t` is answered. A coprocessor that never answers: the cart serves the rest itself.
pub fn wait(t: u32) void {
    if (done(t)) return;
    if (remote and hostBardJob(HOST_WAIT, t) != 0 and slot(t).done == t) return;
    remote = false; // the server is gone: ZIGGY serves from the first job not answered
    _ = hostBardJob(HOST_OPEN, 0);
    var first = t; // jobs are served in order: the ones before t may be unanswered too
    while (head -% (first -% 1) <= L.SLOTS) {
        const p = first -% 1;
        if (slot(p).seq != p or slot(p).done == p) break;
        first = p;
    }
    _ = srv.open(mem(), @intCast(@intFromPtr(&block)), first);
    _ = srv.step(head, 0xFFFF_FFFF);
}

/// The answer of job `t` (after wait).
pub fn result(t: u32) *volatile L.Job {
    return slot(t);
}

pub fn isRemote() bool {
    return remote;
}

/// The page's server (docs/sealed-loader.js): the loader calls it after the cart's frame and
/// when the cart waits. A scene that posts jobs exports it: `comptime { zg.bard.job.exportServer(); }`.
fn serve() callconv(.c) void {
    if (remote) _ = srv.step(hw(L.H.head).*, 0xFFFF_FFFF);
}
pub fn exportServer() void {
    @export(&serve, .{ .name = "bardJobServe" });
}
