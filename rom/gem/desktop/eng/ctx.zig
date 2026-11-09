// --------------------------------------------------------------------------
// What every layer builder (b_*.zig) works with in one frame: the desktop's
// state, the object pool, the asset set, the look, and the scene the layers go
// into. Plus the few builder helpers they share (a G_BOX spec, a string copied
// into the pool, a colour icon block).
// --------------------------------------------------------------------------
const eng = @import("../../engine/obj.zig");
const scene = @import("../../engine/scene.zig");
const pool_mod = @import("pool.zig");
const assets = @import("assets.zig");
const Desktop = @import("../desktop.zig").Desktop;

pub const Tree = pool_mod.Tree;
pub const Pool = pool_mod.Pool;

pub const Ctx = struct {
    d: *Desktop,
    pool: *Pool,
    set: *const assets.Set,
    three_d: bool,
    s: *scene.Scene,
    cicons: [24]eng.CIconBlk = undefined,
    n_cicon: usize = 0,

    pub fn layer(self: *Ctx, l: scene.Layer) void {
        self.s.add(l);
    }

    /// A string copied into the pool (the tree outlives the caller's buffer).
    pub fn str(self: *Ctx, s: []const u8) []const u8 {
        const out = self.pool.bytes(s.len);
        if (out.len == s.len) @memcpy(out, s);
        return out;
    }

    pub fn cicon(self: *Ctx, ib: *const eng.IconBlk, col: []const u8) *const eng.CIconBlk {
        if (self.n_cicon == self.cicons.len) {
            self.pool.full = true;
            self.n_cicon = 0;
        }
        self.cicons[self.n_cicon] = .{ .mono = ib.*, .col = col };
        self.n_cicon += 1;
        return &self.cicons[self.n_cicon - 1];
    }
};

/// A box: border colour/thickness, interior colour and pattern (7 solid, 0 hollow).
pub fn box(thick: i8, border: u4, interior: u4, pattern: u3) eng.Spec {
    return .{ .box = eng.boxSpec(0, thick, eng.colorWord(border, 1, true, pattern, interior)) };
}

/// A G_BOXCHAR spec: one character in black on `interior`.
pub fn boxChar(ch: u8, thick: i8, interior: u4) eng.Spec {
    return .{ .box = eng.boxSpec(ch, thick, eng.colorWord(1, 1, true, 7, interior)) };
}
