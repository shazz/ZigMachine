// --------------------------------------------------------------------------
// A window layer: the chrome as objects at the places gui/window.zig hit-tests
// (same title bar, gadgets, tracks and sliders: types.zig vTrack / hTrack /
// sliderBox), then the work area, a CLIPKIDS box holding the directory
// (b_dir.zig). Flat look: TOS 1's, the gadget bitmaps of gem_glyphs.zig and the
// grey mover. 3D look: TOS 4's, grey 3D gadgets drawn as the font's gadget
// characters (0x01..0x07), a grey title bar on the active window, no shadow.
// --------------------------------------------------------------------------
const eng = @import("../../engine/obj.zig");
const L = @import("../../engine/look.zig");
const gui = @import("../../gui.zig");
const glyphs = @import("../../gem_glyphs.zig");
const types = @import("../../gui/types.zig");
const deskwin = @import("../deskwin.zig");
const deskdrive = @import("../deskdrive.zig");
const b_dir = @import("b_dir.zig");
const ctx_mod = @import("ctx.zig");
const Ctx = ctx_mod.Ctx;
const Tree = ctx_mod.Tree;
const Rect = gui.Rect;
const GW: i16 = glyphs.GW;
const GH: i16 = glyphs.GH;

pub const KEY0: u16 = 16; // window id k is layer 16 + k

const Gadget = enum(u3) { close, full, up, down, left, right, size };
const CHARS = [7]u8{ 5, 7, 1, 2, 4, 3, 6 }; // the font's gadget glyphs
const BITMAPS = [7][glyphs.GH]u16{ glyphs.CLOSE, glyphs.FULL, glyphs.UP, glyphs.DOWN, glyphs.LEFT, glyphs.RIGHT, glyphs.SIZE };
const GADGET_BITS = blk: { // gem_glyphs' 12-bit rows as MSB-first byte pairs
    var out: [7][glyphs.GH * 2]u8 = undefined;
    for (BITMAPS, 0..) |rows, g| for (rows, 0..) |r, i| {
        out[g][2 * i] = @intCast((r << 4) >> 8);
        out[g][2 * i + 1] = @intCast((r << 4) & 0xFF);
    };
    break :blk out;
};
const GADGET_BLK = blk: {
    var out: [7]eng.BitBlk = undefined;
    for (&out, 0..) |*b, g| b.* = .{ .data = &GADGET_BITS[g], .w = GW, .h = GH, .bpr = 2 };
    break :blk out;
};

pub fn build(c: *Ctx) void {
    const d = c.d;
    const focus = d.drv.cur;
    defer deskdrive.use(d, focus); // the drag ghosts and the dialogs read the focused drive
    for (d.wm.order[0..d.wm.n]) |id| {
        const w = &d.wm.wins[id];
        if (!w.open) continue;
        if (deskwin.isFloppyWin(d, id)) deskdrive.use(d, d.drv.win[id]);
        var t = Tree.begin(c.pool, .{ .ty = eng.G_BOX, .spec = ctx_mod.box(1, 1, L.WHITE, 7), .x = w.r.x, .y = w.r.y, .w = w.r.w, .h = w.r.h, .state = if (c.three_d) 0 else eng.SHADOWED });
        chrome(c, &t, w, id == d.wm.topOpen());
        if (deskwin.isFloppyWin(d, id)) b_dir.build(c, &t, id);
        var cover = [4]Rect{ w.r, .{ .x = 0, .y = 0, .w = 0, .h = 0 }, .{ .x = 0, .y = 0, .w = 0, .h = 0 }, .{ .x = 0, .y = 0, .w = 0, .h = 0 } };
        if (!c.three_d) { // the 2-pixel shadow hides what is under it too
            cover[1] = .{ .x = w.r.x + w.r.w, .y = w.r.y + 2, .w = 2, .h = w.r.h };
            cover[2] = .{ .x = w.r.x + 2, .y = w.r.y + w.r.h, .w = w.r.w, .h = 2 };
        }
        c.layer(.{ .key = KEY0 + id, .tree = t.objects(), .cover = conv(cover), .n_cover = 3 });
    }
}

fn conv(r: [4]Rect) [4]@import("../../engine/rect.zig").Rect {
    var out: [4]@import("../../engine/rect.zig").Rect = undefined;
    for (r, 0..) |x, i| out[i] = .{ .x = x.x, .y = x.y, .w = x.w, .h = x.h };
    return out;
}

fn chrome(c: *Ctx, t: *Tree, w: *const types.Window, active: bool) void {
    const top = types.topBarsH(w);
    titleBar(c, t, w, active);
    if (w.info.len > 0) {
        const max: usize = @intCast(@max(0, @divTrunc(w.r.w - 10, 8)));
        _ = t.add(0, .{ .ty = eng.G_STRING, .spec = .{ .str = w.info[0..@min(w.info.len, max)] }, .x = 8, .y = types.TITLE_H, .w = w.r.w - 10, .h = types.INFO_H });
        _ = t.add(0, .{ .ty = eng.G_BOX, .spec = ctx_mod.box(0, 1, L.BLACK, 7), .y = types.TITLE_H + types.INFO_H - 1, .w = w.r.w, .h = 1 });
    }
    track(c, t, w, types.vTrack(w), w.vslide, w.vscroll, w.vmax, true);
    track(c, t, w, types.hTrack(w), w.hslide, w.hscroll, w.hmax, false);
    gadget(c, t, .up, w.r.w - GW, top - 1);
    gadget(c, t, .down, w.r.w - GW, w.r.h - 2 * GH + 1);
    gadget(c, t, .left, 0, w.r.h - GH);
    gadget(c, t, .right, w.r.w - 2 * GW + 1, w.r.h - GH);
    gadget(c, t, .size, w.r.w - GW, w.r.h - GH);
}

fn titleBar(c: *Ctx, t: *Tree, w: *const types.Window, active: bool) void {
    const bar_w = w.r.w - 2 * GW + 2;
    if (c.three_d) {
        const ted = c.pool.ted(.{ .text = w.title, .just = eng.JUST_CENTRE, .color = eng.colorWord(1, 1, true, 7, L.WHITE), .thickness = 1 });
        _ = t.add(0, .{ .ty = eng.G_BOXTEXT, .flags = if (active) eng.FL3DBAK else 0, .spec = .{ .ted = ted }, .x = GW - 1, .w = bar_w, .h = types.TITLE_H });
    } else {
        _ = t.add(0, .{ .ty = eng.G_BOX, .spec = ctx_mod.box(1, 1, L.BLACK, if (active) 2 else 0), .x = GW, .w = w.r.w - 2 * GW, .h = types.TITLE_H });
        const tw: i16 = @intCast(@min(w.title.len * 8, 4000));
        const tx = @divTrunc(w.r.w - tw, 2);
        _ = t.add(0, .{ .ty = eng.G_BOX, .spec = ctx_mod.box(0, 1, L.WHITE, 7), .x = tx - 8, .y = 1, .w = tw + 16, .h = types.TITLE_H - 2 });
        _ = t.add(0, .{ .ty = eng.G_STRING, .spec = .{ .str = w.title }, .x = tx, .y = 2, .w = tw, .h = 8 });
    }
    gadget(c, t, .close, 0, 0);
    gadget(c, t, .full, w.r.w - GW, 0);
}

fn gadget(c: *Ctx, t: *Tree, g: Gadget, x: i16, y: i16) void {
    const i = @intFromEnum(g);
    if (c.three_d) {
        // A set's font has the gadget glyphs; ZigOS's built-in 8x8 has none there: TOS 1's bitmaps then.
        const ch: u8 = if (c.set.present) CHARS[i] else 0;
        _ = t.add(0, .{ .ty = eng.G_BOXCHAR, .flags = eng.FL3DBAK, .spec = ctx_mod.boxChar(ch, 1, L.LWHITE), .x = x, .y = y, .w = GW, .h = GH });
        if (!c.set.present) _ = t.add(0, .{ .ty = eng.G_IMAGE, .spec = .{ .image = &GADGET_BLK[i] }, .x = x, .y = y, .w = GW, .h = GH });
        return;
    }
    _ = t.add(0, .{ .ty = eng.G_BOX, .spec = ctx_mod.box(0, 1, L.WHITE, 7), .x = x, .y = y, .w = GW, .h = GH });
    _ = t.add(0, .{ .ty = eng.G_IMAGE, .spec = .{ .image = &GADGET_BLK[i] }, .x = x, .y = y, .w = GW, .h = GH });
}

// A scroll track, relative to the window: white when everything fits, else the grey
// (TOS 1's hatch, TOS 4's light grey) with the slider box over it.
fn track(c: *Ctx, t: *Tree, w: *const types.Window, tr: Rect, permille: i16, scroll: i16, max: i16, vertical: bool) void {
    const rel = Rect{ .x = tr.x - w.r.x, .y = tr.y - w.r.y, .w = tr.w, .h = tr.h };
    const full = permille >= 1000;
    const grey: eng.Spec = if (c.three_d) ctx_mod.box(1, 1, L.LBLACK, 2) else ctx_mod.box(1, 1, L.BLACK, 2);
    _ = t.add(0, .{ .ty = eng.G_BOX, .spec = if (full) ctx_mod.box(1, 1, L.WHITE, 7) else grey, .x = rel.x, .y = rel.y, .w = rel.w, .h = rel.h });
    if (full) return;
    const b = types.sliderBox(tr, permille, scroll, max, vertical);
    const flags: u16 = if (c.three_d) eng.FL3DBAK else 0;
    const spec = if (c.three_d) ctx_mod.boxChar(0, 1, L.LWHITE) else ctx_mod.box(1, 1, L.WHITE, 7);
    _ = t.add(0, .{ .ty = if (c.three_d) eng.G_BOXCHAR else eng.G_BOX, .flags = flags, .spec = spec, .x = b.x - w.r.x, .y = b.y - w.r.y, .w = b.w, .h = b.h });
}
