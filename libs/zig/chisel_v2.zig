// --------------------------------------------------------------------------
// ZigOS — CHISEL v2 (HW 1.11.0): the texture ops and the small-ops bundle.
//
//   affine(): textured spans from a list CHISEL reads itself (Mode 7 floors,
//             rotozooms, textured polygons a span per row)
//   map():    a box whose every texel comes from a (u, v) map (tunnels, lenses)
//   bobFlip() a keyed bob read mirrored (one sprite sheet, four orientations)
//   areaFill() the Amiga's inclusive / exclusive fill over a box, in place
//   collision: a sticky bit set by any op drawn with `coll = true`
// Each call sets the block for one op and fires hwBlit(), as blitter.zig does.
// The machine is the reference (machine/blitter_tex.zig, blitter_blit.zig,
// blitter_px.zig); docs/BLITTER_HW_SPEC.md §4.5-4.7 has the rules.
// --------------------------------------------------------------------------
const hw = @import("hardware");
const LogicalFB = @import("zigos.zig").LogicalFB;

/// One span of an AFFINE list: pixels [x0, x1) of row y read texel (u >> 16, v >> 16),
/// u = u0 + (x - x0) * du, v likewise (16.16, wrapping). 24 bytes, as the hardware reads it.
pub const Span = extern struct {
    x0: i16,
    x1: i16,
    y: i16,
    _pad: u16 = 0,
    u0: u32,
    v0: u32,
    du: u32,
    dv: u32,
};

comptime {
    if (@sizeOf(Span) != hw.BLIT_SPAN_BYTES) @compileError("chisel_v2: Span must match BLIT_SPAN_BYTES");
}

/// A texture in the cart's RAM (or anywhere CHISEL may read): texel (U, V) is
/// pixels[V * stride + U] with U, V cut by the masks. `wrap` repeats the texture
/// (power-of-two sizes: mask = size - 1); otherwise texels past a mask are not drawn.
pub const Texture = struct {
    pixels: []const u8,
    stride: u16,
    umask: u16,
    vmask: u16,
    wrap: bool = true,
};

/// How a texel is drawn: `key` skips that index, `mt` combines it (B) with the
/// destination (C), `coll` reports a write over a non-zero pixel (collided()).
pub const Draw = struct {
    key: ?u8 = null,
    mt: u8 = hw.MT_B,
    coll: bool = false,
};

inline fn reg(base: usize, comptime T: type, off: usize, v: T) void {
    const p: *volatile T = @ptrFromInt(base + off);
    if (p.* != v) p.* = v;
}

fn setDest(base: usize, dst: *LogicalFB) void {
    reg(base, u32, hw.BLIT_D_BASE, @intCast(@intFromPtr(dst.fb) - base));
    reg(base, u16, hw.BLIT_D_STRIDE, dst.stride);
}

fn setTexture(base: usize, t: Texture, d: Draw) void {
    reg(base, u32, hw.BLIT_A_BASE, @intCast(@intFromPtr(t.pixels.ptr)));
    reg(base, u16, hw.BLIT_A_STRIDE, t.stride);
    reg(base, u16, hw.BLIT_U_MASK, t.umask);
    reg(base, u16, hw.BLIT_V_MASK, t.vmask);
    var con2: u8 = hw.CON2_SRC_ABS;
    if (!t.wrap) con2 |= hw.CON2_TEX_CLIP;
    if (d.coll) con2 |= hw.CON2_COLL_EN;
    reg(base, u8, hw.BLIT_CON2, con2);
    reg(base, u8, hw.BLIT_CON, if (d.key != null) hw.CON_KEY_EN else 0);
    reg(base, u8, hw.BLIT_COLOR_KEY, d.key orelse 0);
    reg(base, u8, hw.BLIT_MINTERM, d.mt);
}

fn fire(base: usize, cmd: u8) void {
    reg(base, u8, hw.BLIT_COMMAND, cmd);
    hw.hwBlit();
}

/// Draw `spans` (in cart RAM: CHISEL reads the list itself) with texture `t` onto `dst`.
pub fn affine(dst: *LogicalFB, t: Texture, spans: []const Span, d: Draw) void {
    if (spans.len == 0) return;
    const base: usize = @intCast(hw.hwVideoBase());
    setDest(base, dst);
    setTexture(base, t, d);
    reg(base, u32, hw.BLIT_SPAN_BASE, @intCast(@intFromPtr(spans.ptr)));
    reg(base, u16, hw.BLIT_SPAN_COUNT, @intCast(@min(spans.len, 0xFFFF)));
    fire(base, hw.BLIT_CMD_AFFINE);
}

/// The w x h box at (x, y) of `dst`, pixel (i, j) taking texel (u + uoff, v + voff) where
/// map[j * map_w + i] = v << 8 | u (a map in cart RAM, `map_w` entries a row).
pub fn map(dst: *LogicalFB, t: Texture, x: i16, y: i16, w: u16, h: u16, m: []const u16, map_w: u16, uoff: u16, voff: u16, d: Draw) void {
    if (w == 0 or h == 0 or @as(usize, map_w) * (h - 1) + w > m.len) return;
    const base: usize = @intCast(hw.hwVideoBase());
    setDest(base, dst);
    setTexture(base, t, d);
    reg(base, u32, hw.BLIT_B_BASE, @intCast(@intFromPtr(m.ptr)));
    reg(base, u16, hw.BLIT_B_STRIDE, map_w * 2);
    reg(base, u16, hw.BLIT_U_OFF, uoff);
    reg(base, u16, hw.BLIT_V_OFF, voff);
    reg(base, u16, hw.BLIT_X0, @bitCast(x));
    reg(base, u16, hw.BLIT_Y0, @bitCast(y));
    reg(base, u16, hw.BLIT_W, w);
    reg(base, u16, hw.BLIT_H, h);
    fire(base, hw.BLIT_CMD_MAP);
}

/// A keyed bob from `src` (a w x h image in cart RAM, `src_w` pixels a row) at (x, y) of
/// `dst`, read mirrored: `fx` left-right, `fy` top-bottom.
pub fn bobFlip(dst: *LogicalFB, x: i16, y: i16, src: []const u8, src_w: u16, w: u16, h: u16, key: ?u8, fx: bool, fy: bool, coll: bool) void {
    if (w == 0 or h == 0 or @as(usize, src_w) * (h - 1) + w > src.len) return;
    const base: usize = @intCast(hw.hwVideoBase());
    setDest(base, dst);
    var con2: u8 = hw.CON2_SRC_ABS;
    if (fx) con2 |= hw.CON2_MIRROR_X;
    if (fy) con2 |= hw.CON2_MIRROR_Y;
    if (coll) con2 |= hw.CON2_COLL_EN;
    reg(base, u8, hw.BLIT_CON2, con2);
    reg(base, u8, hw.BLIT_CON, if (key != null) hw.CON_USEB | hw.CON_KEY_EN else hw.CON_USEB);
    reg(base, u8, hw.BLIT_COLOR_KEY, key orelse 0);
    reg(base, u8, hw.BLIT_MINTERM, hw.MT_B);
    reg(base, u32, hw.BLIT_B_BASE, @intCast(@intFromPtr(src.ptr)));
    reg(base, u16, hw.BLIT_B_STRIDE, src_w);
    reg(base, u16, hw.BLIT_X0, @bitCast(x));
    reg(base, u16, hw.BLIT_Y0, @bitCast(y));
    reg(base, u16, hw.BLIT_W, w);
    reg(base, u16, hw.BLIT_H, h);
    fire(base, hw.BLIT_CMD_BLIT);
}

pub const Fill = enum { inclusive, exclusive };

/// The Amiga's area fill over the w x h box at (x, y) of `dst`, in place: each row, left to
/// right, every bit of the index is filled between the edge pixels LINE drew (with MT_XOR_BC,
/// one a row). `inside` starts each row inside (the Amiga's FCI).
pub fn areaFill(dst: *LogicalFB, x: i16, y: i16, w: u16, h: u16, how: Fill, inside: bool) void {
    const base: usize = @intCast(hw.hwVideoBase());
    setDest(base, dst);
    reg(base, u8, hw.BLIT_CON2, if (inside) hw.CON2_FILL_CARRY else 0);
    reg(base, u8, hw.BLIT_CON, hw.CON_USEC | if (how == .inclusive) hw.CON_IFE else hw.CON_EFE);
    reg(base, u8, hw.BLIT_MINTERM, hw.MT_C);
    reg(base, u16, hw.BLIT_X0, @bitCast(x));
    reg(base, u16, hw.BLIT_Y0, @bitCast(y));
    reg(base, u16, hw.BLIT_W, w);
    reg(base, u16, hw.BLIT_H, h);
    fire(base, hw.BLIT_CMD_BLIT);
}

/// Did an op drawn with `coll` write over a non-zero pixel since the last clearCollision()?
pub fn collided() bool {
    const p: *volatile u8 = @ptrFromInt(@as(usize, @intCast(hw.hwVideoBase())) + hw.BLIT_COLL);
    return p.* & 1 != 0;
}

pub fn clearCollision() void {
    const p: *volatile u8 = @ptrFromInt(@as(usize, @intCast(hw.hwVideoBase())) + hw.BLIT_COLL);
    p.* = 0;
}
