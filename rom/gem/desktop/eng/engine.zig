// --------------------------------------------------------------------------
// GEM 5 step 1: the desk painted by the engine (docs/GEM5_ENGINE.md).
//
// A frame runs ZigGEM's own step (input, menus, windows, dialogs: unchanged)
// with the Gui MUTED, so the logic is exactly the old path's; then it builds the
// screen as layers of object trees (b_*.zig), compares them with what the buffer
// about to be drawn holds (damage.zig: per buffer, the desk is double-buffered)
// and paints only the damage (compose.zig). The dialogs are not on the engine
// yet: the step paints them itself, clipped to the box they had last frame, and
// the compositor keeps out of that box. A frame with no damage paints nothing
// and does not flip (`drew` false).
// --------------------------------------------------------------------------
const gui = @import("../../gui.zig");
const eng = @import("../../engine/obj.zig");
const rect = @import("../../engine/rect.zig");
const scene_mod = @import("../../engine/scene.zig");
const damage = @import("../../engine/damage.zig");
const compose = @import("../../engine/compose.zig");
const canvas = @import("../../engine/canvas.zig");
const assets = @import("assets.zig");
const looks = @import("looks.zig");
const ctx_mod = @import("ctx.zig");
const b_desk = @import("b_desk.zig");
const b_win = @import("b_win.zig");
const b_menu = @import("b_menu.zig");
const b_over = @import("b_over.zig");
const deskdirty = @import("../deskdirty.zig");
const dt = @import("../desktop.zig");
const Desktop = dt.Desktop;

pub const Mode = enum(u8) { old = 0, flat = 1, three_d = 2 };

// --break mutants (deskSetEngine's high bits), each one a bug the harness must catch.
pub const BREAK_WHOLE: u32 = 1 << 8; // repaint the whole screen every drawn frame
pub const BREAK_NOCLIP: u32 = 1 << 9; // paint every layer unclipped
pub const BREAK_ONESNAP: u32 = 1 << 10; // one snapshot for both buffers (forgets the frame before last)
pub const BREAK_DROP: u32 = 1 << 11; // lose the damage's last rectangle

/// What the harness reads (deskEngineStats): u32s, in this order.
pub const Stats = extern struct { frames: u32 = 0, drawn: u32 = 0, rects: u32 = 0, area: u32 = 0, written: u32 = 0, last_area: u32 = 0, last_rects: u32 = 0, overflow: u32 = 0 };

pub const Engine = struct {
    mode: Mode = .old,
    breaks: u32 = 0,
    set: assets.Set = undefined,
    snaps: [2]damage.Snap = undefined,
    scene: scene_mod.Scene = undefined,
    pool: ctx_mod.Pool = undefined,
    arrow_mask: [32]u8 = undefined,
    arrow_data: [32]u8 = undefined,
    arrow: eng.IconBlk = undefined,
    dlg_rect: gui.Rect = gui.clip.MUTED, // the dialog's box as last painted
    slot: u1 = 0, // the buffer this frame draws into (rom_main.deskFrame)
    drew: bool = false,
    stats: Stats = .{},
    ready: bool = false, // init ran once: a re-init (a cart returned) keeps the mode deskSetEngine chose

    pub fn init(self: *Engine, sys8: []const u8, small6: []const u8) void {
        const default_on = @import("gem_opts").engine_default; // build.zig -Dgem_engine
        self.set = assets.load(sys8, small6);
        self.snaps[0].valid = false;
        self.snaps[1].valid = false;
        self.pool.reset();
        for (0..16) |r| {
            self.arrow_mask[2 * r] = @intCast(self.set.arrow.mask[r] >> 8);
            self.arrow_mask[2 * r + 1] = @intCast(self.set.arrow.mask[r] & 0xFF);
            self.arrow_data[2 * r] = @intCast(self.set.arrow.data[r] >> 8);
            self.arrow_data[2 * r + 1] = @intCast(self.set.arrow.data[r] & 0xFF);
        }
        self.arrow = .{ .mask = &self.arrow_mask, .data = &self.arrow_data, .w = 16, .h = 16, .bpr = 2, .color = 0x1000 };
        if (!self.ready) self.mode = if (default_on) (if (self.set.present) .three_d else .flat) else .old;
        self.ready = true;
    }

    pub fn active(self: *const Engine, d: *const Desktop) bool {
        return self.mode != .old and d.g.screen.mode == .desk;
    }

    /// deskSetEngine: 0 old path, 1 flat (TOS 1), 2 3D (TOS 4); bits 8.. the mutants.
    pub fn setMode(self: *Engine, d: *Desktop, v: u32) void {
        self.mode = switch (v & 0xFF) {
            1 => .flat,
            2 => .three_d,
            else => .old,
        };
        self.breaks = v & ~@as(u32, 0xFF);
        self.invalidate();
        if (self.mode != .old) installPens(self, d);
        deskdirty.touch(d);
    }

    /// The buffers hold something the snapshots do not describe (a mode change, an old-path frame).
    pub fn invalidate(self: *Engine) void {
        self.snaps[0].valid = false;
        self.snaps[1].valid = false;
    }

    pub fn frame(self: *Engine, d: *Desktop) dt.Action {
        const painted = self.logic(d);
        const action = painted.action;
        self.stats.frames += 1;
        self.paint(d, painted.dialog);
        return action;
    }

    // ZigGEM's step, muted, the dialogs clipped to last frame's box; what the dialogs painted.
    fn logic(self: *Engine, d: *Desktop) struct { action: dt.Action, dialog: gui.Rect } {
        const modal0 = d.isModal();
        const clip = if (modal0) self.dlg_rect else gui.clip.MUTED;
        d.g.clip = gui.clip.MUTED;
        d.eng_dlg = clip;
        const action = d.step();
        d.g.clip = null;
        d.eng_dlg = null;
        const rec = d.eng_rec orelse gui.clip.MUTED;
        d.eng_rec = null;
        if (!d.isModal()) {
            self.dlg_rect = gui.clip.MUTED;
            return .{ .action = action, .dialog = gui.clip.MUTED };
        }
        if (!same(rec, self.dlg_rect)) deskdirty.touch(d); // its box moved: paint it whole next frame
        self.dlg_rect = rec;
        return .{ .action = action, .dialog = if (modal0) meet(rec, clip) else gui.clip.MUTED };
    }

    fn paint(self: *Engine, d: *Desktop, dialog: gui.Rect) void {
        self.drew = false;
        const look = looks.look(&self.set, self.mode == .three_d);
        self.buildScene(d, dialog);
        self.scene.measure(&look);
        const s = d.g.screen;
        const screen: rect.Rect = .{ .w = s.w, .h = s.h };
        const snap = &self.snaps[if (self.breaks & BREAK_ONESNAP != 0) 0 else self.slot];
        var dmg: rect.RectList = .{};
        damage.diff(&self.scene, snap, screen, &dmg);
        if (self.breaks & BREAK_WHOLE != 0 and dmg.n > 0) dmg = whole(screen);
        if (self.breaks & BREAK_DROP != 0 and dmg.n > 1) dmg.n -= 1;
        if (dmg.n == 0) return; // a clean frame: nothing painted, no flip
        var cv = canvas.Canvas.init(d.g.fb.fb, d.g.fb.stride, s.w, @min(s.h, @as(i16, @intCast(d.g.fb.fb_h))));
        cv.fill_fn = fillPlane;
        cv.fill_ctx = @ptrCast(d.g.fb);
        var st: compose.Stats = .{};
        const all = whole(screen);
        compose.compose(&cv, &look, &self.scene, if (self.breaks & BREAK_NOCLIP != 0) &all else &dmg, &st);
        if (self.breaks & BREAK_NOCLIP != 0) st.area = dmg.area(); // the bug paints past the damage it reports
        if (self.breaks & BREAK_NOCLIP != 0) st.area = dmg.area(); // the bug paints past the damage it reports
        snap.record(&self.scene);
        self.drew = true;
        self.count(st, cv.written);
    }

    fn buildScene(self: *Engine, d: *Desktop, dialog: gui.Rect) void {
        self.pool.reset();
        self.scene.n = 0;
        self.scene.n_obj = 0;
        self.scene.overflow = false;
        var c: ctx_mod.Ctx = .{ .d = d, .pool = &self.pool, .set = &self.set, .three_d = self.mode == .three_d, .s = &self.scene };
        b_desk.build(&c);
        b_win.build(&c);
        b_over.gestures(&c);
        b_menu.build(&c);
        b_over.dialog(&c, dialog);
        b_over.pointer(&c, &self.arrow);
        if (self.pool.full) self.scene.overflow = true;
    }

    fn count(self: *Engine, st: compose.Stats, written: u32) void {
        self.stats.drawn += 1;
        self.stats.rects += st.rects;
        self.stats.area += st.area;
        self.stats.written += written;
        self.stats.last_area = st.area;
        self.stats.last_rects = st.rects;
        if (self.scene.overflow) self.stats.overflow += 1;
    }
};

fn whole(screen: rect.Rect) rect.RectList {
    var l: rect.RectList = .{};
    l.add(screen);
    return l;
}

fn same(a: gui.Rect, b: gui.Rect) bool {
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h;
}

fn meet(a: gui.Rect, b: gui.Rect) gui.Rect {
    const r = rect.intersect(.{ .x = a.x, .y = a.y, .w = a.w, .h = a.h }, .{ .x = b.x, .y = b.y, .w = b.w, .h = b.h });
    return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
}

fn installPens(self: *Engine, d: *Desktop) void {
    for (0..16) |i| {
        const p = looks.penEntry(&self.set, i);
        d.g.fb.setPaletteEntry(p.idx, .{ .r = p.rgb[0], .g = p.rgb[1], .b = p.rgb[2], .a = 255 });
    }
}

// The canvas's big fills: the plane's own fill (blit.Dst: CHISEL above its threshold).
fn fillPlane(ctx: *anyopaque, at: [*]u8, stride: u32, w: u32, h: u32, v: u8) void {
    const fb: *@import("zigos").LogicalFB = @ptrCast(@alignCast(ctx));
    const off = @intFromPtr(at) - @intFromPtr(fb.fb);
    fb.fillRect(@intCast(off % stride), @intCast(off / stride), w, h, v);
}
