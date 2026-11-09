// --------------------------------------------------------------------------
// GEM 5 engine: painting ONE object at its screen box, by type, then its state
// (OUTLINED, SHADOWED, CHECKED). The flat look is TOS 1's: a SELECTED object is
// drawn inverted (white and black swapped). The 3D look (look.three_d) is TOS 4's,
// for objects with a 3D flag: a grey face, a light top-left and a dark
// bottom-right edge; an activator (FL3DACT) pushes in when selected (the bevel
// flips, the text moves one pixel), an indicator (FL3DIND) changes colour, and
// both are drawn ADJ3D pixels larger than their box.
// --------------------------------------------------------------------------
const rect = @import("rect.zig");
const obj = @import("obj.zig");
const L = @import("look.zig");
const Canvas = @import("canvas.zig").Canvas;
const Rect = rect.Rect;
const Object = obj.Object;
const Look = L.Look;

pub const SHADOW: i16 = 2;

pub fn paint(cv: *Canvas, look: *const Look, o: *const Object, r: Rect) void {
    const sel = o.state & obj.SELECTED != 0;
    switch (o.ty) {
        obj.G_BOX, obj.G_IBOX, obj.G_BOXCHAR => box(cv, look, o, r, sel),
        obj.G_STRING, obj.G_TITLE => string(cv, look, o, r, sel),
        obj.G_BUTTON => button(cv, look, o, r, sel),
        obj.G_TEXT, obj.G_FTEXT, obj.G_BOXTEXT, obj.G_FBOXTEXT => tedText(cv, look, o, r, sel),
        obj.G_ICON, obj.G_CICON => @import("paint_icon.zig").icon(cv, look, o, r, sel),
        obj.G_DOTS => cv.dotted(r, look.ink(switch (o.spec) {
            .box => |b| obj.colors(@truncate(b)).border,
            else => L.BLACK,
        })),
        obj.G_IMAGE => if (o.spec == .image) {
            const b = o.spec.image;
            cv.bits(b.data, rowBytes(b.w, b.bpr), b.w, b.h, r.x, r.y, look.inv(@intCast(b.color & 15), sel), null);
        },
        else => {},
    }
    states(cv, look, o, r);
}

pub fn rowBytes(w: i16, bpr: i16) usize {
    return if (bpr > 0) @intCast(bpr) else (@as(usize, @intCast(w)) + 7) / 8;
}

pub fn kind3d(look: *const Look, o: *const Object) u16 {
    return if (look.three_d) o.flags & obj.FL3DMASK else 0;
}

/// The face of a 3D object: grey, an indicator darker when selected; the light /
/// dark edges inside `r` (swapped for a pushed activator).
fn face3d(cv: *Canvas, look: *const Look, k: u16, r: Rect, sel: bool) void {
    const face = if (k == obj.FL3DIND and sel) look.ink(L.LBLACK) else look.ink(look.face);
    cv.fill(r, face);
    if (k == obj.FL3DBAK) return;
    const pushed = sel and k == obj.FL3DACT;
    const hi = look.ink(if (pushed) L.LBLACK else L.WHITE);
    const lo = look.ink(if (pushed) L.WHITE else L.LBLACK);
    cv.fill(.{ .x = r.x, .y = r.y, .w = r.w - 1, .h = 1 }, hi);
    cv.fill(.{ .x = r.x, .y = r.y, .w = 1, .h = r.h - 1 }, hi);
    cv.fill(.{ .x = r.x + 1, .y = r.y + r.h - 1, .w = r.w - 1, .h = 1 }, lo);
    cv.fill(.{ .x = r.x + r.w - 1, .y = r.y + 1, .w = 1, .h = r.h - 1 }, lo);
}

fn interior(cv: *Canvas, look: *const Look, c: obj.Colors, r: Rect, sel: bool) void {
    if (c.pattern == 7) return cv.fill(r, look.inv(c.interior, sel));
    if (c.pattern == 0) return if (c.replace) cv.fill(r, look.inv(L.WHITE, sel));
    cv.pattern(r, &look.patterns[c.pattern], look.inv(c.interior, sel), if (c.replace) look.inv(L.WHITE, sel) else null);
}

fn box(cv: *Canvas, look: *const Look, o: *const Object, r: Rect, sel: bool) void {
    const spec = switch (o.spec) {
        .box => |s| s,
        else => obj.boxSpec(0, 1, 0x1100),
    };
    const c = obj.colors(@truncate(spec));
    const t = obj.boxThickness(spec);
    const k = kind3d(look, o);
    const outer = if (k == obj.FL3DIND or k == obj.FL3DACT) r.grow(L.ADJ3D) else r;
    if (k != 0 and o.ty != obj.G_IBOX) {
        face3d(cv, look, k, if (t > 0) inset(outer, t) else outer, sel);
    } else if (o.ty != obj.G_IBOX) interior(cv, look, c, r, sel and k == 0);
    if (t != 0) cv.frame(outer, t, look.inv(c.border, sel and k == 0));
    if (o.ty == obj.G_BOXCHAR) {
        const ch = [1]u8{obj.boxChar(spec)};
        const push: i16 = if (sel and k == obj.FL3DACT) 1 else 0;
        centred(cv, look.font, &ch, r, push, look.inv(c.text, sel and k == 0), null);
    }
}

fn inset(r: Rect, t: i8) Rect {
    return r.grow(-@as(i16, t));
}

fn string(cv: *Canvas, look: *const Look, o: *const Object, r: Rect, sel: bool) void {
    const s = switch (o.spec) {
        .str => |s| s,
        else => return,
    };
    if (sel) cv.fill(r, look.ink(L.BLACK));
    const ink = if (o.state & obj.DISABLED != 0) look.grey else look.inv(L.BLACK, sel);
    const y = r.y + @divTrunc(r.h - look.font.h + 1, 2);
    cv.text(look.font, s, r.x, y, ink, null);
}

fn button(cv: *Canvas, look: *const Look, o: *const Object, r: Rect, sel: bool) void {
    const s = switch (o.spec) {
        .str => |s| s,
        else => "",
    };
    var t: i8 = -1;
    if (o.flags & obj.EXIT != 0) t -= 1;
    if (o.flags & obj.DEFAULT != 0) t -= 1;
    const k = kind3d(look, o);
    var push: i16 = 0;
    if (k != 0) {
        const outer = if (k == obj.FL3DBAK) r else r.grow(L.ADJ3D);
        face3d(cv, look, k, outer, sel);
        cv.frame(outer, if (o.flags & obj.DEFAULT != 0) -2 else -1, look.ink(L.BLACK));
        push = if (sel and k == obj.FL3DACT) 1 else 0;
    } else {
        cv.fill(r, look.inv(L.WHITE, sel));
        cv.frame(r, t, look.ink(L.BLACK));
    }
    const ink = if (o.state & obj.DISABLED != 0) look.grey else look.inv(L.BLACK, sel and k == 0);
    centred(cv, look.font, s, r, push, ink, null);
}

fn tedText(cv: *Canvas, look: *const Look, o: *const Object, r: Rect, sel: bool) void {
    const t = switch (o.spec) {
        .ted => |t| t,
        else => return,
    };
    const c = obj.colors(t.color);
    const boxed = o.ty == obj.G_BOXTEXT or o.ty == obj.G_FBOXTEXT;
    const k = kind3d(look, o);
    if (boxed and k != 0) face3d(cv, look, k, r, sel) else if (boxed) interior(cv, look, c, r, sel);
    if (boxed and t.thickness != 0) cv.frame(r, t.thickness, look.inv(c.border, sel and k == 0));
    const f = if (t.font == obj.FONT_SMALL) look.small else look.font;
    const tw: i16 = @intCast(@min(t.text.len * f.w, 4000));
    const x = switch (t.just) {
        obj.JUST_RIGHT => r.x + r.w - tw,
        obj.JUST_CENTRE => r.x + @divTrunc(r.w - tw + 1, 2),
        else => r.x,
    };
    const ink = if (o.state & obj.DISABLED != 0) look.grey else look.inv(c.text, sel and k == 0);
    const paper: ?u8 = if (c.replace and !boxed) look.inv(L.WHITE, sel) else null;
    cv.text(f, t.text, x, r.y + @divTrunc(r.h - f.h + 1, 2), ink, paper);
}

/// Text centred in `r`, the spare space rounded up as the AES's gr_just does.
pub fn centred(cv: *Canvas, f: *const L.Font, s: []const u8, r: Rect, push: i16, ink: u8, paper: ?u8) void {
    const tw: i32 = @intCast(@min(s.len * f.w, 4000));
    const x = r.x + @divTrunc(r.w - tw + 1, 2) + push;
    const y = r.y + @divTrunc(r.h - @as(i32, f.h) + 1, 2) + push;
    cv.text(f, s, x, y, ink, paper);
}

fn states(cv: *Canvas, look: *const Look, o: *const Object, r: Rect) void {
    const k = kind3d(look, o);
    const base = if (k == obj.FL3DIND or k == obj.FL3DACT) r.grow(L.ADJ3D) else r;
    if (o.state & obj.OUTLINED != 0) {
        if (k == obj.FL3DBAK) { // TOS 4: a 3D background's outline is its own light/dark rim
            cv.frame(base.grow(3), 1, look.ink(L.BLACK));
            cv.frame(base.grow(2), 2, look.ink(L.LWHITE));
            cv.fill(.{ .x = base.x - 2, .y = base.y - 2, .w = base.w + 4, .h = 1 }, look.ink(L.WHITE));
        } else {
            cv.frame(base.grow(3), 1, look.ink(L.BLACK));
            cv.frame(base.grow(2), 2, look.ink(L.WHITE));
        }
    }
    if (o.state & obj.SHADOWED != 0) {
        const ink = look.ink(L.BLACK);
        cv.fill(.{ .x = base.x + base.w, .y = base.y + SHADOW, .w = SHADOW, .h = base.h }, ink);
        cv.fill(.{ .x = base.x + SHADOW, .y = base.y + base.h, .w = base.w, .h = SHADOW }, ink);
    }
    if (o.state & obj.CHECKED != 0) cv.text(look.font, &[1]u8{8}, r.x, r.y + @divTrunc(r.h - look.font.h + 1, 2), look.inv(L.BLACK, o.state & obj.SELECTED != 0), null);
}
