// --------------------------------------------------------------------------
// COPRO page 6: a 16 x 16 cloth, pinned at its edges and poked by a point
// that circles over it, solved implicitly every frame on ASTROLABE (or ZIGGY's
// soft f64 for the A/B). One call of 39 descriptors a frame, LINPACK inside:
//   r  = h + v + poke                          SCAL, AXPY, AXPY
//   rows:    (I + aL) X = r, 16 times          GESL with the factors GEFA made once
//   columns: H' = X (I + aL)^-1, 16 columns    GEMV with the inverse (16 GESLs, once)
//   v  = k H' - k h,  h = H',  the heights x20 SCAL, AXPY, SCAL, SCAL
// (L: the 16-point second difference, the edges held at 0: alternating
// directions, the classic ADI split.) The mesh is drawn from the heights' bits
// (integer ops), in an oblique view, every line redrawn a frame.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const C = @import("common.zig");
const A = @import("astro_page.zig");
const Desc = zg.astro.Desc;

pub const NAME = "F64 CLOTH 16X16 LINPACK";
const N: u32 = 16;
const P: u32 = N * N;
const STIFF: f64 = 4.0; // a: the implicit spring's stiffness
const DAMP: f64 = 0.97; // k: v = k (h' - h)
const POKES: u32 = 64; // the poke's strength table (a sine, made at init)

pub const Cloth = struct {
    h: []f64 = &.{},
    v: []f64 = &.{},
    r: []f64 = &.{},
    hn: []f64 = &.{},
    hs: []f64 = &.{},
    poke: []f64 = &.{},
    lu: []f64 = &.{},
    inv: []f64 = &.{},
    ipvt: []u32 = &.{},
    amp: [POKES]f64 = undefined,
    d: []Desc = &.{},
    f: u32 = 0,
    at: u32 = 0, // the poked node

    pub fn enter(self: *Cloth, ctx: *C.Ctx) void {
        if (self.h.len == 0) self.build();
        C.shades(ctx.fb, .{ 0, 40, 60 }, .{ 200, 255, 255 });
        ctx.fb.setPaletteEntry(0, .{ .r = 4, .g = 8, .b = 16, .a = 255 });
        for ([_][]f64{ self.h, self.v, self.poke }) |a| @memset(a, 0);
        self.factor(ctx);
        self.f = 0;
    }

    fn build(self: *Cloth) void {
        for ([_]*[]f64{ &self.h, &self.v, &self.r, &self.hn, &self.hs, &self.poke, &self.lu, &self.inv }) |a| a.* = A.f64s(P);
        self.ipvt = zg.mem.mustAlloc(u32, N);
        for (&self.amp, 0..) |*a, i| a.* = 24.0 * @sin(@as(f64, @floatFromInt(i)) * (6.2831853 / @as(f64, POKES))); // init only
        self.d = zg.mem.mustAlloc(Desc, 39);
        const d = self.d;
        d[0] = A.scal(P, 1.0, self.h.ptr, self.r.ptr);
        d[1] = zg.astro.daxpy(P, 1.0, self.v.ptr, self.r.ptr);
        d[2] = zg.astro.daxpy(P, 1.0, self.poke.ptr, self.r.ptr);
        for (0..N) |i| d[3 + i] = zg.astro.dgesl(N, self.lu.ptr, N, @ptrCast(self.ipvt.ptr), self.r.ptr + N * i);
        for (0..N) |k| d[3 + N + k] = zg.astro.dgemv(N, N, self.r.ptr, N, self.inv.ptr + N * k, self.hn.ptr + N * k);
        d[35] = A.scal(P, DAMP, self.hn.ptr, self.v.ptr);
        d[36] = zg.astro.daxpy(P, -DAMP, self.h.ptr, self.v.ptr);
        d[37] = A.scal(P, 1.0, self.hn.ptr, self.h.ptr);
        d[38] = A.scal(P, 20.0, self.h.ptr, self.hs.ptr);
    }

    /// I + aL (16 x 16, column-major) factored by GEFA; its inverse by 16 GESLs on the identity.
    fn factor(self: *Cloth, ctx: *C.Ctx) void {
        @memset(self.lu, 0);
        @memset(self.inv, 0);
        for (0..N) |i| {
            self.lu[N * i + i] = 1.0 + 2.0 * STIFF; // comptime constants: no f64 op on ZIGGY
            if (i > 0) self.lu[N * i + i - 1] = -STIFF;
            if (i + 1 < N) self.lu[N * i + i + 1] = -STIFF;
            self.inv[N * i + i] = 1.0;
        }
        var d: [1 + N]Desc = undefined;
        d[0] = zg.astro.dgefa(N, self.lu.ptr, N, @ptrCast(self.ipvt.ptr));
        for (0..N) |j| d[1 + j] = zg.astro.dgesl(N, self.lu.ptr, N, @ptrCast(self.ipvt.ptr), self.inv.ptr + N * j);
        A.run(ctx, &d);
    }

    pub fn frame(self: *Cloth, ctx: *C.Ctx) void {
        self.poke[self.at] = 0;
        // The poke circles the cloth: node (8 + 5 cos, 8 + 5 sin) from a 16-step table, integers.
        const ring = [16][2]u8{ .{ 13, 8 }, .{ 13, 10 }, .{ 12, 11 }, .{ 10, 13 }, .{ 8, 13 }, .{ 6, 13 }, .{ 4, 11 }, .{ 3, 10 }, .{ 3, 8 }, .{ 3, 6 }, .{ 4, 4 }, .{ 6, 3 }, .{ 8, 3 }, .{ 10, 3 }, .{ 12, 4 }, .{ 13, 6 } };
        const p = ring[(self.f / 8) % 16];
        self.at = @as(u32, p[1]) * N + p[0];
        self.poke[self.at] = self.amp[self.f % POKES]; // a copy of the table's bits
        A.run(ctx, self.d);
        self.draw(ctx.pixels());
        self.f += 1;
    }

    fn draw(self: *Cloth, px: [*]u8) void {
        C.clearRowsPx(px, 0);
        var sx: [P]i32 = undefined;
        var sy: [P]i32 = undefined;
        for (0..P) |i| {
            const gx: i32 = @intCast(i % N);
            const gy: i32 = @intCast(i / N);
            sx[i] = 30 + gx * 12 + gy * 5;
            sy[i] = 40 + gy * 7 - A.toInt(&self.hs[i]);
        }
        for (0..P) |i| {
            const col: u8 = C.SHADE + @as(u8, @intCast(@min(15, @max(0, 8 + @divTrunc(A.toInt(&self.hs[i]), 4)))));
            if (i % N + 1 < N) C.line(px, sx[i], sy[i], sx[i + 1], sy[i + 1], col);
            if (i + N < P) C.line(px, sx[i], sy[i], sx[i + N], sy[i + N], col);
        }
    }

    pub fn leave(self: *Cloth, ctx: *C.Ctx) void {
        _ = self;
        _ = ctx;
    }
};
