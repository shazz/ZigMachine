// --------------------------------------------------------------------------
// COPRO page 5: an f64 Mandelbrot zoom into Seahorse Valley, ~1e-13 deep, on
// ASTROLABE (or ZIGGY's soft f64 for the A/B). 64 x 35 cells of 5 x 5 pixels.
// hwAstro has no per-element compare or select, so the iteration is batched
// for EVERY cell: z = z^2 + c as 7 vector ops (3 VMUL, an AXPY, 3 VADD), ITERS
// iterations a frame in one call. Between calls ZIGGY scans the cells with
// INTEGER ops on the f64 bits: |re| or |im| >= 2 (biased exponent >= 1024)
// means escaped: the cell takes its colour (the iteration count, smoothed by
// the exponent's log2, also from the bits) and is frozen (z = c = 0 stays 0).
// Cells alive after the level's iterations are inside: black. Then the next
// level zooms in x0.8. The per-level corner and step are a few f64 ops on
// ZIGGY (soft) on both sides, so both sides start from the same bits.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const C = @import("common.zig");
const A = @import("astro_page.zig");
const Desc = zg.astro.Desc;

pub const NAME = "F64 ZOOM (BATCH+BIT ESCAPE)";
const GW: u32 = 64;
const GH: u32 = 35;
const P: u32 = GW * GH;
const CELL: u32 = 5;
const ITERS: u32 = 2; // a frame (7 descriptors each): the same on both sides
const CX: f64 = -0.743643887037151; // Seahorse Valley
const CY: f64 = 0.131825904205330;
const DX0: f64 = 3.0 / 64.0;

pub const Zoom = struct {
    zr: []f64 = &.{},
    zi: []f64 = &.{},
    cr: []f64 = &.{},
    ci: []f64 = &.{},
    t: [3][]f64 = .{ &.{}, &.{}, &.{} },
    ix: []f64 = &.{},
    iy: []f64 = &.{},
    ones: []f64 = &.{},
    alive: []u8 = &.{},
    it_desc: []Desc = &.{},
    dx: f64 = DX0,
    level: u32 = 0,
    it: u32 = 0,
    maxit: u32 = 0,

    pub fn enter(self: *Zoom, ctx: *C.Ctx) void {
        if (self.zr.len == 0) self.build();
        C.shades(ctx.fb, .{ 20, 0, 60 }, .{ 255, 220, 120 });
        ctx.fb.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 255 });
        self.dx = DX0;
        self.level = 0;
        self.startLevel(ctx);
    }

    /// The arrays and the iteration's descriptors (init: the index arrays' floats are made once).
    fn build(self: *Zoom) void {
        for ([_]*[]f64{ &self.zr, &self.zi, &self.cr, &self.ci, &self.t[0], &self.t[1], &self.t[2], &self.ix, &self.iy, &self.ones }) |a| a.* = A.f64s(P);
        self.alive = zg.mem.mustAlloc(u8, P);
        for (0..P) |i| {
            self.ix[i] = @floatFromInt(i % GW);
            self.iy[i] = @floatFromInt(i / GW);
            self.ones[i] = 1.0;
        }
        self.it_desc = zg.mem.mustAlloc(Desc, 7 * ITERS);
        const z = self;
        for (0..ITERS) |k| {
            const d = self.it_desc[7 * k ..][0..7];
            d[0] = A.vmul(P, z.zr.ptr, z.zr.ptr, z.t[0].ptr); // re^2
            d[1] = A.vmul(P, z.zi.ptr, z.zi.ptr, z.t[1].ptr); // im^2
            d[2] = A.vmul(P, z.zr.ptr, z.zi.ptr, z.t[2].ptr); // re im
            d[3] = zg.astro.daxpy(P, -1.0, z.t[1].ptr, z.t[0].ptr); // re^2 - im^2
            d[4] = A.vadd(P, z.t[0].ptr, z.cr.ptr, z.zr.ptr); // + cr
            d[5] = A.vadd(P, z.t[2].ptr, z.t[2].ptr, z.zi.ptr); // 2 re im
            d[6] = A.vadd(P, z.zi.ptr, z.ci.ptr, z.zi.ptr); // + ci
        }
    }

    fn startLevel(self: *Zoom, ctx: *C.Ctx) void {
        if (self.dx < 1e-15) self.dx = DX0; // as deep as f64 goes here: again from the top
        const x0 = CX - self.dx * 32.0; // soft f64 on ZIGGY, a few ops a level, both sides
        const y0 = CY - self.dx * 17.0;
        var d = [_]Desc{
            A.scal(P, x0, self.ones.ptr, self.cr.ptr), zg.astro.daxpy(P, self.dx, self.ix.ptr, self.cr.ptr),
            A.scal(P, y0, self.ones.ptr, self.ci.ptr), zg.astro.daxpy(P, self.dx, self.iy.ptr, self.ci.ptr),
        };
        A.run(ctx, &d);
        @memset(self.zr, 0);
        @memset(self.zi, 0);
        @memset(self.alive, 1);
        self.it = 0;
        self.maxit = @min(32 + 6 * self.level, 400);
        C.clearRows(ctx.fb, 0);
    }

    pub fn frame(self: *Zoom, ctx: *C.Ctx) void {
        A.run(ctx, self.it_desc);
        self.it += ITERS;
        self.scan(ctx.pixels());
        if (self.it < self.maxit) return;
        self.level += 1;
        self.dx *= 0.8;
        self.startLevel(ctx);
    }

    /// Escaped cells: coloured and frozen. Integer ops on the f64 bits only.
    fn scan(self: *Zoom, px: [*]u8) void {
        for (0..P) |i| {
            if (self.alive[i] == 0) continue;
            const e = @max((A.hi(&self.zr[i]) >> 20) & 0x7FF, (A.hi(&self.zi[i]) >> 20) & 0x7FF);
            if (e < 1024) continue;
            const lg: u32 = 31 - @clz(@as(u32, e - 1022)); // log2 of the exponent: how far past 2
            const col: u8 = @intCast((self.it * 2 -% lg) & 15);
            cell(px, @intCast(i), C.SHADE + col);
            self.alive[i] = 0;
            self.zr[i] = 0;
            self.zi[i] = 0;
            self.cr[i] = 0;
            self.ci[i] = 0;
        }
    }

    fn cell(px: [*]u8, i: u32, v: u8) void {
        const x0 = (i % GW) * CELL;
        const y0 = (i / GW) * CELL;
        for (0..CELL) |y| @memset(px[(y0 + y) * C.W + x0 ..][0..CELL], v);
    }

    pub fn leave(self: *Zoom, ctx: *C.Ctx) void {
        _ = self;
        _ = ctx;
    }
};
