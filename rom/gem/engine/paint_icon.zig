// --------------------------------------------------------------------------
// GEM 5 engine: G_ICON and G_CICON. The mono icon: the mask in the mask colour,
// the data over it in the data colour (ICONBLK's colour byte: data high nibble,
// mask low), swapped when SELECTED; the label under it in the small font on a
// box of the mask colour. A colour icon (CIconBlk) paints its chunky image where
// the mono mask is set, its selected image when there is one (else the mono
// icon, inverted, as TOS 4 does for a colour icon with no selected image).
// --------------------------------------------------------------------------
const obj = @import("obj.zig");
const L = @import("look.zig");
const Canvas = @import("canvas.zig").Canvas;
const Rect = @import("rect.zig").Rect;
const Object = obj.Object;
const Look = L.Look;

pub fn icon(cv: *Canvas, look: *const Look, o: *const Object, r: Rect, sel: bool) void {
    switch (o.spec) {
        .icon => |ib| mono(cv, look, ib, r, sel),
        .cicon => |ci| colour(cv, look, ci, r, sel),
        else => {},
    }
}

fn mono(cv: *Canvas, look: *const Look, ib: *const obj.IconBlk, r: Rect, sel: bool) void {
    const fg: u4 = @intCast((ib.color >> 12) & 15);
    const bg: u4 = @intCast((ib.color >> 8) & 15);
    const data_c = look.ink(if (sel) bg else fg);
    const mask_c = look.ink(if (sel) fg else bg);
    const x = r.x + ib.ix;
    const y = r.y + ib.iy;
    cv.bits(ib.mask, ib.rowBytes(), ib.w, ib.h, x, y, mask_c, null);
    cv.bits(ib.data, ib.rowBytes(), ib.w, ib.h, x, y, data_c, null);
    label(cv, look, ib, r, data_c, mask_c);
}

fn colour(cv: *Canvas, look: *const Look, ci: *const obj.CIconBlk, r: Rect, sel: bool) void {
    const ib = &ci.mono;
    if (sel and ci.sel == null) return mono(cv, look, ib, r, true);
    const img = if (sel) ci.sel.? else ci.col;
    cv.chunky(img, ib.mask, ib.rowBytes(), ib.w, ib.h, r.x + ib.ix, r.y + ib.iy);
    const fg: u4 = @intCast((ib.color >> 12) & 15);
    const bg: u4 = @intCast((ib.color >> 8) & 15);
    label(cv, look, ib, r, look.ink(if (sel) bg else fg), look.ink(if (sel) fg else bg));
}

fn label(cv: *Canvas, look: *const Look, ib: *const obj.IconBlk, r: Rect, ink: u8, paper: u8) void {
    if (ib.tw <= 0 or ib.th <= 0) return;
    const box: Rect = .{ .x = r.x + ib.tx, .y = r.y + ib.ty, .w = ib.tw, .h = ib.th };
    cv.fill(box, paper);
    const f = look.small;
    const tw: i32 = @intCast(@min(ib.text.len * f.w, 4000));
    const tx = box.x + @divTrunc(box.w - tw + 1, 2);
    const saved = cv.clip;
    defer cv.clip = saved;
    cv.clip = @import("rect.zig").intersect(saved, box); // a long name is cut at the box
    cv.text(f, ib.text, tx, box.y + @divTrunc(box.h - @as(i32, f.h) + 1, 2), ink, null);
}
