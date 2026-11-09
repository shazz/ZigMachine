// --------------------------------------------------------------------------
// A clip and a recorder for the immediate-mode primitives (GEM 5 step 1).
//
// The GEM 5 engine (rom/gem/desktop/eng/) runs ZigGEM's desktop logic exactly as
// before — the immediate-mode code decides AND draws in one pass — but paints
// the desk itself from object trees. So it runs that pass with the Gui's clip
// set to MUTED (nothing drawn), and the dialogs (not on the engine yet) with the
// clip set to their own box; `rec` collects the box of everything the dialogs
// tried to draw, which is where the engine finds them.
// With `clip` and `rec` both null (the low and medium modes, the old desk path)
// the primitives take their old path: not one pixel moves.
// --------------------------------------------------------------------------
const types = @import("types.zig");
const zsrc = @import("zigos");
const bandfill = @import("bandfill.zig");
const Gui = @import("core.zig").Gui;
const Rect = types.Rect;

pub const MUTED: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };

pub fn muted(g: *const Gui) bool {
    const c = g.clip orelse return false;
    return c.w <= 0 or c.h <= 0;
}

fn meet(a: Rect, b: Rect) Rect {
    const x0 = @max(a.x, b.x);
    const y0 = @max(a.y, b.y);
    const x1 = @min(@as(i32, a.x) + a.w, @as(i32, b.x) + b.w);
    const y1 = @min(@as(i32, a.y) + a.h, @as(i32, b.y) + b.h);
    if (x1 <= x0 or y1 <= y0) return MUTED;
    return .{ .x = x0, .y = y0, .w = @intCast(x1 - x0), .h = @intCast(y1 - y0) };
}

fn record(g: *Gui, r: Rect) void {
    const was = g.rec orelse return;
    if (r.w <= 0 or r.h <= 0) return;
    if (was.w <= 0) {
        g.rec = r;
        return;
    }
    const x0 = @min(was.x, r.x);
    const y0 = @min(was.y, r.y);
    const x1 = @max(@as(i32, was.x) + was.w, @as(i32, r.x) + r.w);
    const y1 = @max(@as(i32, was.y) + was.h, @as(i32, r.y) + r.h);
    g.rec = .{ .x = x0, .y = y0, .w = @intCast(x1 - x0), .h = @intCast(y1 - y0) };
}

pub fn fill(g: *Gui, x: i16, y: i16, w: u16, h: u16, color: u8) void {
    const r: Rect = .{ .x = x, .y = y, .w = @intCast(@min(w, 32767)), .h = @intCast(@min(h, 32767)) };
    record(g, r);
    const c = if (g.clip) |k| meet(r, k) else r;
    if (c.w <= 0 or c.h <= 0) return;
    bandfill.fill(g.blit, g.fb, c.x, c.y, @intCast(c.w), @intCast(c.h), color);
}

/// Text of `fw` x `fh` cells (8x8 or the 6x6 font), clipped to `within` and the Gui's clip.
pub fn text(g: *Gui, s: []const u8, x: i16, y: i16, ink: u8, paper: u8, small: bool, within: ?Rect) void {
    const fw: i16 = if (small) 6 else 8;
    const box: Rect = .{ .x = x, .y = y, .w = @intCast(@min(@as(usize, 4000), s.len * @as(usize, @intCast(fw)))), .h = if (small) 6 else 8 };
    record(g, if (within) |w| meet(box, w) else box);
    var c = if (g.clip) |k| k else Rect{ .x = 0, .y = 0, .w = 32767, .h = 32767 };
    if (within) |w| c = meet(c, w);
    if (c.w <= 0 or c.h <= 0) return;
    const k: zsrc.Clip = .{ .x0 = c.x, .y0 = c.y, .x1 = c.x + c.w, .y1 = c.y + c.h };
    if (small) g.os.printTextSmallClipped(g.fb, s, x, y, ink, paper, k) else g.os.printTextClipped(g.fb, s, x, y, ink, paper, k);
}

pub fn plot(g: *Gui, x: i16, y: i16) bool {
    record(g, .{ .x = x, .y = y, .w = 1, .h = 1 });
    const k = g.clip orelse return true;
    return x >= k.x and y >= k.y and x < @as(i32, k.x) + k.w and y < @as(i32, k.y) + k.h;
}
