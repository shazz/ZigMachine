// --------------------------------------------------------------------------
// ZigMachine — SEALED blitter: BLIT, the 3-source block transfer / cookie-cut
// bob (§4.1), with the CHISEL v2 (1.11.0) extras every other op shares in
// blitter_px.zig: MIRROR_X/Y (the sources read flipped) and the area fill
// (CON.IFE/EFE). See docs/BLITTER_HW_SPEC.md.
// --------------------------------------------------------------------------
const memmap = @import("sdk/memmap.zig");
const regs = @import("blitter_regs.zig");
const check = @import("blitter_check.zig");
const px = @import("blitter_px.zig");
const Clip = regs.Clip;
const r8 = regs.r8;
const r16 = regs.r16;
const ri16 = regs.ri16;
const r32 = regs.r32;

pub fn doBlit(d: [*]u8, ds: u16, c: Clip, con: u8, cost: *u32) void {
    const s = BlitSetup.load(con) orelse return; // all registers read ONCE, not per pixel
    var out = px.Writer.init(con);
    var jj: u16 = 0;
    while (jj < s.h) : (jj += 1) {
        const j: u16 = if (s.desc) s.h - 1 - jj else jj;
        const py = @as(i32, s.y0) + j;
        if (py < c.y0 or py >= c.y1) continue;
        out.row();
        const drow = @as(usize, @intCast(py)) * ds;
        const sj: usize = if (s.flip_y) s.h - 1 - j else j; // the sources' row
        const arow = sj * s.a_stride;
        const brow = sj * s.b_stride;
        var ii: u16 = 0;
        while (ii < s.w) : (ii += 1) {
            const i: u16 = if (s.desc) s.w - 1 - ii else ii;
            const pxx = @as(i32, s.x0) + i;
            if (pxx < c.x0 or pxx >= c.x1) continue;
            const si: usize = if (s.flip_x) s.w - 1 - i else i;
            const b = if (s.use_b) s.b_src[brow + si] else 0;
            if (s.key_en and b == s.key) continue; // cookie-cut transparent pixel
            const di = drow + @as(usize, @intCast(pxx));
            const v = if (s.plain) b else regs.applyMinterm(
                if (s.use_a) s.a_src[arow + si] else 0,
                b,
                if (s.use_c) d[di] else 0,
                s.mt,
            );
            out.put(d, di, v);
            cost.* += 1;
        }
    }
}

// One-time decode of the BLIT register block, so the inner loop touches only
// locals. `plain` is the D = B copy fast path (skips the per-bit minterm).
// Null when there is nothing to draw or an absolute source was refused.
const BlitSetup = struct {
    w: u16,
    h: u16,
    x0: i16,
    y0: i16,
    mt: u8,
    key: u8,
    key_en: bool,
    desc: bool,
    flip_x: bool,
    flip_y: bool,
    use_a: bool,
    use_b: bool,
    use_c: bool,
    plain: bool,
    a_src: [*]const u8,
    a_stride: usize,
    b_src: [*]const u8,
    b_stride: usize,

    fn load(con: u8) ?BlitSetup {
        const mt = r8(memmap.BLIT_MINTERM);
        const con2 = r8(memmap.BLIT_CON2);
        const use_a = con & memmap.CON_USEA != 0;
        const use_b = con & memmap.CON_USEB != 0;
        const w = r16(memmap.BLIT_W);
        const h = r16(memmap.BLIT_H);
        if (w == 0 or h == 0) return null;
        const abs = con2 & memmap.CON2_SRC_ABS != 0;
        const a_stride = r16(memmap.BLIT_A_STRIDE);
        const b_stride = r16(memmap.BLIT_B_STRIDE);
        // an unused channel is never read: point it at the region, unchecked
        const a_src = if (use_a) check.source(abs, r32(memmap.BLIT_A_BASE), a_stride, w, h) orelse return null else regs.region();
        const b_src = if (use_b) check.source(abs, r32(memmap.BLIT_B_BASE), b_stride, w, h) orelse return null else regs.region();
        return .{
            .w = w,
            .h = h,
            .x0 = ri16(memmap.BLIT_X0),
            .y0 = ri16(memmap.BLIT_Y0),
            .mt = mt,
            .key = r8(memmap.BLIT_COLOR_KEY),
            .key_en = con & memmap.CON_KEY_EN != 0,
            .desc = con & memmap.CON_DESC != 0,
            .flip_x = con2 & memmap.CON2_MIRROR_X != 0,
            .flip_y = con2 & memmap.CON2_MIRROR_Y != 0,
            .use_a = use_a,
            .use_b = use_b,
            .use_c = con & memmap.CON_USEC != 0,
            .plain = mt == memmap.MT_B and use_b and !use_a,
            .a_src = a_src,
            .a_stride = a_stride,
            .b_src = b_src,
            .b_stride = b_stride,
        };
    }
};
