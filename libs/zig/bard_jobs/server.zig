// --------------------------------------------------------------------------
// The BARD job server: takes the cart's posted jobs (layout.zig) in order,
// checks each against the cart's memory, runs it (kernels.zig, zx0.zig) in
// slices, answers. ONE source for every server:
//   BARD          fpga/cycles/sound/sjobs.c through libs/zig/bard_job_rv32.zig:
//                 a budget of cycles a turn of its loop, between audio renders
//   the page      docs/sealed-loader.js calls the cart's bardJobServe export
//                 after the cart's frame (and when the cart waits)
//   no server     the cart serves its own jobs at once (zg.bard.job, ZIGGY alone)
// Clock.now() is the server's cycle counter (BARD's SND_CYCLES; 0 elsewhere).
// zx0 is libs/zig/depackers/zx0.zig, passed in: inside a cart it belongs to
// the `depackers` module, and a file may sit in only one module.
// --------------------------------------------------------------------------
const L = @import("layout.zig");
const K = @import("kernels.zig");

/// The cart's memory as this server sees it: offset o is at base + o.
pub const Mem = struct {
    base: usize,
    size: u32,

    /// The address of [off, off + len), or the error: out of the cart, at 0, or misaligned.
    pub fn at(self: Mem, off: u32, len: u32, comptime al: u32) error{ range, alignment }!usize {
        if (off == 0 or len > self.size or off > self.size - len) return error.range;
        if (off & (al - 1) != 0) return error.alignment;
        return self.base + off;
    }
};

const SLICE_POINTS = 256; // xform / particles a slice
const SLICE_BYTES = 4096; // zx0 output a slice

/// What step() left: nothing, a job half done (its next slice), a slot not whole yet (re-read it).
pub const Progress = enum(u32) { idle = 0, busy = 1, waiting = 2 };

pub fn Server(comptime Clock: type, comptime zx0: type) type {
    return struct {
        const Self = @This();
        const Cur = union(enum) {
            zx0: zx0.Stream,
            xform: struct { a: [*]const L.Point, b: [*]const L.Point, t: i32, x: L.Xform, ztab: [*]const u32, out: [*]u32, n: u32 },
            particles: struct { in: [*]const L.Particle, st: [*]L.Particle, p: L.Physics, out: [*]u32, n: u32, frame: u32 },
            crc: struct { src: [*]const u32, words: u32, out: [*]u32, n: u32 },
        };

        mem: Mem = .{ .base = 0, .size = 0 },
        block: u32 = 0, // the block's cart offset; 0 = closed
        tail: u32 = 0, // the next job to serve
        cur: ?Cur = null, // the job in progress
        pos: u32 = 0, // its index reached
        acc: u32 = 0, // its result so far
        spent: u32 = 0, // its cycles so far

        /// Serve the block at cart offset `block` (0: close), from post number `head` on.
        pub fn open(self: *Self, mem: Mem, block: u32, head: u32) bool {
            self.* = .{ .mem = mem };
            const addr = mem.at(block, L.BLOCK_BYTES, 16) catch return false;
            const h: [*]volatile u32 = @ptrFromInt(addr);
            if (h[L.H.magic] != L.MAGIC or h[L.H.slots] != L.SLOTS) return false;
            self.block = block;
            self.tail = head;
            return true;
        }

        fn slot(self: *Self, n: u32) *volatile L.Job {
            const addr = self.mem.base + self.block + 4 * L.HEAD_WORDS + @sizeOf(L.Job) * (n & (L.SLOTS - 1));
            return @ptrFromInt(addr);
        }

        /// Serve up to post number `head` for at most `budget` cycles (maxInt: to the end).
        pub fn step(self: *Self, head: u32, budget: u32) Progress {
            if (self.block == 0 or head -% self.tail > L.SLOTS) return .idle;
            const t0 = Clock.now();
            while (self.tail != head) {
                const job = self.slot(self.tail);
                if (self.cur == null) {
                    if (job.seq != self.tail) return .waiting; // not whole yet (a store on its way)
                    self.start(job) catch |e| {
                        self.finish(job, if (e == error.alignment) .alignment else if (e == error.range) .range else if (e == error.bad_op) .bad_op else .data);
                        continue;
                    };
                }
                if (self.run(t0, budget)) return .busy;
                self.finish(job, if (self.acc == L.NONE) .data else .ok);
            }
            return .idle;
        }

        fn start(self: *Self, job: *volatile L.Job) !void {
            const a = job.a;
            self.pos = 0;
            self.acc = 0;
            self.spent = 0;
            const m = self.mem;
            switch (@as(L.Op, @enumFromInt(job.op))) {
                .zx0 => {
                    const src: [*]const u8 = @ptrFromInt(try m.at(a[0], a[1], 1));
                    const dst: [*]u8 = @ptrFromInt(try m.at(a[2], a[3], 1));
                    self.cur = .{ .zx0 = zx0.Stream.init(src[0..a[1]], dst[0..a[3]]) orelse return error.data };
                },
                .xform => {
                    if (a[0] > 1 << 20 or a[3] > 256) return error.data;
                    const x: *const L.Xform = @ptrFromInt(try m.at(a[4], @sizeOf(L.Xform), 4));
                    const xf = x.*;
                    if (xf.ztab_n > 1 << 16) return error.data;
                    self.cur = .{ .xform = .{ .a = @ptrFromInt(try m.at(a[1], a[0] * 8, 4)), .b = @ptrFromInt(try m.at(a[2], a[0] * 8, 4)),
                        .t = @intCast(a[3]), .x = xf, .ztab = @ptrFromInt(try m.at(xf.ztab, xf.ztab_n * 4, 4)),
                        .out = @ptrFromInt(try m.at(a[5], a[0] * 4, 4)), .n = a[0] } };
                },
                .particles => {
                    if (a[0] > 1 << 20) return error.data;
                    const p: *const L.Physics = @ptrFromInt(try m.at(a[3], @sizeOf(L.Physics), 4));
                    const ph = p.*;
                    if (ph.spread == 0 or ph.spread & (ph.spread - 1) != 0) return error.data;
                    if (a[1] < a[2] +% a[0] * 16 and a[2] < a[1] +% a[0] * 16) return error.data; // in and out overlap
                    self.cur = .{ .particles = .{ .in = @ptrFromInt(try m.at(a[1], a[0] * 16, 4)), .st = @ptrFromInt(try m.at(a[2], a[0] * 16, 4)),
                        .p = ph, .out = @ptrFromInt(try m.at(a[4], a[0] * 4, 4)), .n = a[0], .frame = a[5] } };
                },
                .crc32 => {
                    if (a[2] < 2 or a[2] > 16) return error.data;
                    const n = a[1] >> @intCast(a[2]);
                    self.cur = .{ .crc = .{ .src = @ptrFromInt(try m.at(a[0], n << @intCast(a[2]), 4)), .words = @as(u32, 1) << @intCast(a[2] - 2),
                        .out = @ptrFromInt(try m.at(a[3], n * 4, 4)), .n = n } };
                },
                _ => return error.bad_op,
            }
        }

        /// The job in progress, a slice at a time while the budget lasts. True: not finished.
        fn run(self: *Self, t0: u32, budget: u32) bool {
            while (true) {
                const c0 = Clock.now();
                const more = self.slice();
                self.spent +%= Clock.now() -% c0;
                if (!more) return false;
                if (Clock.now() -% t0 >= budget) return true;
            }
        }

        fn slice(self: *Self) bool {
            switch (self.cur.?) {
                .zx0 => |*s| switch (s.step(SLICE_BYTES)) {
                    .more => return true,
                    .done => self.acc = s.written(),
                    .failed => self.acc = L.NONE,
                },
                .xform => |*j| {
                    const end = @min(j.n, self.pos + SLICE_POINTS);
                    self.acc += K.xform(j.a, j.b, j.t, &j.x, j.ztab, j.out, self.pos, end);
                    self.pos = end;
                    if (end < j.n) return true;
                },
                .particles => |*j| {
                    const end = @min(j.n, self.pos + SLICE_POINTS);
                    self.acc += K.particles(j.in, j.st, &j.p, j.out, j.frame, self.pos, end);
                    self.pos = end;
                    if (end < j.n) return true;
                },
                .crc => |*j| {
                    if (self.pos < j.n) {
                        K.crcChunks(j.src, j.words, j.out, self.pos, self.pos + 1);
                        self.pos += 1;
                        return true;
                    }
                    self.acc = ~K.crcWords(0xFFFF_FFFF, j.out, j.n);
                },
            }
            return false;
        }

        /// The answer, `done` last: the cart reads the rest once it sees its seq there.
        fn finish(self: *Self, job: *volatile L.Job, err: L.Err) void {
            job.err = @intFromEnum(err);
            job.cycles = self.spent;
            job.result = if (err == .ok) self.acc else 0;
            job.done = self.tail;
            self.tail +%= 1;
            self.cur = null;
        }
    };
}
