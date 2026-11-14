// --------------------------------------------------------------------------
// COPRO page 3: a fountain of N sparks, one particles job a frame: gravity,
// a damped bounce on the floor (a multiply and a shift, no divide), a
// respawn at the emitter when one settles or leaves the plane, its velocity
// from a hash of (spark, frame), so every host makes the same sparks.
// State in -> state out (ping-pong: a job never runs twice on its own
// output), and the screen offsets double-buffered as the dots page's are.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const job = zg.bard.job;
const C = @import("common.zig");
const ptr = @import("slides.zig").ptr;

pub const NAME = "PARTICLES 4096";
pub const N: u32 = 4096;
const FLOOR: i32 = 168;

pub const Sparks = struct {
    st: [2][]job.Particle = .{ &.{}, &.{} },
    out: [2][]u32 = .{ &.{}, &.{} },
    ph: *job.Physics = undefined,
    pending: ?u32 = null,
    f: u32 = 0,

    pub fn enter(self: *Sparks, ctx: *C.Ctx) void {
        if (self.st[0].len == 0) self.build();
        for (&self.out) |o| @memset(o, job.OFF);
        self.seed();
        C.clearRows(ctx.fb, 0);
        ctx.fb.setPaletteEntry(0, .{ .r = 8, .g = 0, .b = 0, .a = 255 });
        C.shades(ctx.fb, .{ 120, 16, 0 }, .{ 255, 255, 200 });
        // The floor: one row of the effect's own colour.
        @memset(ctx.pixels()[@as(u32, FLOOR + 1) * C.W ..][0..C.W], C.SHADE + 4);
        self.f = 0;
        self.pending = self.kick(ctx, 0);
    }

    fn build(self: *Sparks) void {
        self.st = .{ @ptrCast(C.words(4 * N)), @ptrCast(C.words(4 * N)) };
        self.out = .{ C.words(N), C.words(N) };
        self.ph = @ptrCast(C.words(@sizeOf(job.Physics) / 4).ptr);
        self.ph.* = .{ .gravity = 5_000, .floor = FLOOR << 16, .bounce = 150, .rest = 1 << 15, .w = C.W, .h = C.ROWS,
            .stride = C.W, .ex = 160 << 16, .ey = 160 << 16, .spread = 1 << 16, .lift = -(4 << 16) };
    }

    /// The first frame's sparks already in flight, all over the arc (not one burst).
    fn seed(self: *Sparks) void {
        for (self.st[0], 0..) |*q, i| {
            const h = job.hash(@intCast(i), 0xC0DE);
            q.* = .{ .x = (64 + @as(i32, @intCast(h & 0xFF))) << 16, .y = (20 + @as(i32, @intCast((h >> 8) % 140))) << 16,
                .vx = @as(i32, @intCast((h >> 16) & 0x1FFFF)) - (1 << 16), .vy = @as(i32, @intCast((h >> 4) & 0x3FFFF)) - (2 << 16) };
        }
    }

    /// Frame f's step: st[f & 1] -> st[(f + 1) & 1], the dots into out[f & 1].
    fn kick(self: *Sparks, ctx: *C.Ctx, f: u32) u32 {
        return ctx.post(.particles, &.{ N, ptr(self.st[f & 1].ptr), ptr(self.st[(f + 1) & 1].ptr), ptr(self.ph), ptr(self.out[f & 1].ptr), f });
    }

    pub fn frame(self: *Sparks, ctx: *C.Ctx) void {
        _ = ctx.wait(self.pending);
        const px = ctx.pixels();
        for (self.out[(self.f + 1) & 1]) |o| {
            if (o != job.OFF) px[o] = 0;
        }
        self.pending = self.kick(ctx, self.f + 1);
        for (self.out[self.f & 1], 0..) |o, i| {
            if (o != job.OFF) px[o] = C.SHADE + 6 + @as(u8, @intCast(i & 7)) + @as(u8, @intCast((i >> 3) & 1));
        }
        self.f += 1;
    }

    pub fn leave(self: *Sparks, ctx: *C.Ctx) void {
        _ = ctx.wait(self.pending);
        self.pending = null;
    }
};
