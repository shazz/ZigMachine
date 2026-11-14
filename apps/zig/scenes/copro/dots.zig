// --------------------------------------------------------------------------
// COPRO page 2: a dot sphere morphing into a torus and back, N points a frame
// through one xform job: the morph, a Q14 rotation, and the projection
// through a reciprocal table the cart builds once (BARD has no divide).
// Double-buffered: frame f draws job f's dots while job f+1 runs; the dots of
// frame f-1 are erased (only what moved is touched) before job f+1 reuses
// their buffer.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const job = zg.bard.job;
const ft = zg.fixtrig;
const C = @import("common.zig");
const ptr = @import("slides.zig").ptr;

pub const NAME = "3D MORPH 4096 DOTS";
pub const N: u32 = 4096;
const SIDE: u32 = 64; // N = SIDE x SIDE
const FOCAL: u32 = 200;
const ZOFF: i32 = 36_000;
const ZSHIFT: u32 = 8;
const ZTAB: u32 = 256;

pub const Dots = struct {
    a: []job.Point = &.{},
    b: []job.Point = &.{},
    ztab: []u32 = &.{},
    tint: [256]u8 = undefined, // depth bucket (the job's shade byte) -> colour: near is bright
    out: [2][]u32 = .{ &.{}, &.{} },
    xf: *job.Xform = undefined,
    pending: ?u32 = null,
    f: u32 = 0,

    pub fn enter(self: *Dots, ctx: *C.Ctx) void {
        if (self.a.len == 0) self.build();
        for (&self.out) |o| @memset(o, job.OFF);
        C.clearRows(ctx.fb, 0);
        ctx.fb.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 16, .a = 255 });
        C.shades(ctx.fb, .{ 16, 24, 64 }, .{ 255, 240, 160 });
        self.f = 0;
        self.pending = self.kick(ctx, 0);
    }

    /// The shapes and the reciprocal table: init only (the divides are here, not in the job).
    fn build(self: *Dots) void {
        self.a = @ptrCast(C.words(2 * N));
        self.b = @ptrCast(C.words(2 * N));
        self.ztab = C.words(ZTAB);
        self.out = .{ C.words(N), C.words(N) };
        self.xf = @ptrCast(C.words(@sizeOf(job.Xform) / 4).ptr);
        for (0..N) |i| {
            const r = i / SIDE;
            const c = i % SIDE;
            const th: u32 = @intCast((2 * r + 1) << 24); // 0..pi
            const ph: u32 = @intCast(c << 26); // 0..2 pi
            self.a[i] = point(12_000, ft.mul(ft.sin(th), ft.cos(ph)), ft.cos(th), ft.mul(ft.sin(th), ft.sin(ph)));
            const ring: i32 = 8_000 + (3_500 * ft.cos(@intCast(r << 26)) >> 16); // the torus' tube
            self.b[i] = .{ .x = @intCast(ring * ft.cos(ph) >> 16), .y = @intCast(3_500 * ft.sin(@intCast(r << 26)) >> 16),
                .z = @intCast(ring * ft.sin(ph) >> 16) };
        }
        for (self.ztab, 0..) |*z, d| z.* = if (d == 0) 0 else @intCast(FOCAL * 65536 / (d << ZSHIFT));
        // The shapes span depths ZOFF +- 12000: buckets 94..188 (ZSHIFT 8), spread over the 16 shades.
        const near: u32 = (ZOFF - 12_000) >> ZSHIFT;
        for (&self.tint, 0..) |*t, d| {
            const k: u32 = if (d <= near) 0 else @min(15, (@as(u32, @intCast(d)) - near) * 16 / (24_000 >> ZSHIFT));
            t.* = C.SHADE + 15 - @as(u8, @intCast(k));
        }
    }

    fn point(r: i32, x: i32, y: i32, z: i32) job.Point {
        return .{ .x = @intCast(r * x >> 16), .y = @intCast(r * y >> 16), .z = @intCast(r * z >> 16) };
    }

    /// Post frame f's transform into out[f & 1].
    fn kick(self: *Dots, ctx: *C.Ctx, f: u32) u32 {
        const ax: u32 = f *% 9_000_000;
        const ay: u32 = f *% 14_000_000;
        const cx = ft.cos(ax) >> 2; // Q14
        const sx = ft.sin(ax) >> 2;
        const cy = ft.cos(ay) >> 2;
        const sy = ft.sin(ay) >> 2;
        self.xf.* = .{ .m = .{ cy, sy * sx >> 14, sy * cx >> 14, 0, cx, -sx, -sy, cy * sx >> 14, cy * cx >> 14 },
            .zoff = ZOFF, .cx = 160, .cy = @intCast(C.ROWS / 2), .w = C.W, .h = C.ROWS, .stride = C.W,
            .ztab = ptr(self.ztab.ptr), .ztab_n = ZTAB, .zshift = ZSHIFT, .shade_shift = 0 };
        return ctx.post(.xform, &.{ N, ptr(self.a.ptr), ptr(self.b.ptr), morph(f), ptr(self.xf), ptr(self.out[f & 1].ptr) });
    }

    /// Hold the sphere, morph to the torus, hold it, morph back: 360 frames.
    fn morph(f: u32) u32 {
        const p = f % 360;
        if (p < 90) return 0;
        if (p < 180) return @min(256, (p - 90) * 3);
        if (p < 270) return 256;
        return 256 - @min(256, (p - 270) * 3);
    }

    pub fn frame(self: *Dots, ctx: *C.Ctx) void {
        _ = ctx.wait(self.pending);
        const px = ctx.pixels();
        const old = self.out[(self.f + 1) & 1];
        for (old) |o| {
            if (o != job.OFF) px[o & 0xFF_FFFF] = 0;
        }
        self.pending = self.kick(ctx, self.f + 1); // into the buffer just erased
        for (self.out[self.f & 1]) |o| {
            if (o != job.OFF) px[o & 0xFF_FFFF] = self.tint[o >> 24];
        }
        self.f += 1;
    }

    pub fn leave(self: *Dots, ctx: *C.Ctx) void {
        _ = ctx.wait(self.pending);
        self.pending = null;
    }
};
