// --------------------------------------------------------------------------
// Gui — pointer state (from the host, sealed-loader.js) + immediate-mode drawing
// primitives over the blitter (fast fills) + ZigOS text, held for one frame.
// --------------------------------------------------------------------------
const zsrc = @import("zigos");
const ZigOS = zsrc.ZigOS;
const LogicalFB = zsrc.LogicalFB;
const Blitter = zsrc.Blitter;
const glyphs = @import("../gem_glyphs.zig");
const types = @import("types.zig");
const Rect = types.Rect;
const Screen = @import("screen.zig").Screen;
const bandfill = @import("bandfill.zig");
const clip = @import("clip.zig");
const inRect = types.inRect;
const BLACK = types.BLACK;
const WHITE = types.WHITE;
const DGRAY = types.DGRAY;

pub const Gui = struct {
    os: *ZigOS,
    fb: *LogicalFB,
    blit: *Blitter,
    screen: Screen = .{}, // the mode, size and font every layout reads (screen.zig)
    px: i32 = -1,
    py: i32 = -1,
    down: bool = false,
    prev: bool = false,
    edge: bool = false, // press started this frame
    clip: ?Rect = null, // GEM 5: draw only inside (MUTED: nothing); null = the old path (clip.zig)
    rec: ?Rect = null, // GEM 5: non-null = collect the box of everything drawn (clip.zig)

    pub fn setPointer(self: *Gui, x: i32, y: i32, buttons: u32) void {
        self.px = x;
        self.py = y;
        self.down = buttons != 0;
    }
    pub fn beginFrame(self: *Gui) void {
        self.edge = self.down and !self.prev;
    }
    pub fn endFrame(self: *Gui) void {
        self.prev = self.down;
    }

    /// A blitter fill on this screen, whatever its height (bandfill.zig: the desk is 480 rows).
    pub fn fill(self: *Gui, x: i16, y: i16, w: u16, h: u16, color: u8) void {
        if (self.clip != null or self.rec != null) return clip.fill(self, x, y, w, h, color);
        bandfill.fill(self.blit, self.fb, x, y, w, h, color);
    }
    pub fn rect(self: *Gui, r: Rect, color: u8) void {
        self.fill(r.x, r.y, @intCast(r.w), @intCast(r.h), color);
    }
    pub fn frame(self: *Gui, r: Rect, color: u8) void {
        self.fill(r.x, r.y, @intCast(r.w), 1, color);
        self.fill(r.x, r.y + r.h - 1, @intCast(r.w), 1, color);
        self.fill(r.x, r.y, 1, @intCast(r.h), color);
        self.fill(r.x + r.w - 1, r.y, 1, @intCast(r.h), color);
    }
    pub fn bevel(self: *Gui, r: Rect, face: u8, raised: bool) void { // TOS 4 look; not the TOS 1 chrome's
        const hi: u8 = if (raised) WHITE else DGRAY;
        const lo: u8 = if (raised) DGRAY else WHITE;
        self.rect(r, face);
        self.fill(r.x, r.y, @intCast(r.w), 1, hi);
        self.fill(r.x, r.y, 1, @intCast(r.h), hi);
        self.fill(r.x, r.y + r.h - 1, @intCast(r.w), 1, lo);
        self.fill(r.x + r.w - 1, r.y, 1, @intCast(r.h), lo);
    }
    pub fn text(self: *Gui, s: []const u8, x: i16, y: i16, ink: u8, paper: u8) void {
        if (self.clip != null or self.rec != null) return clip.text(self, s, x, y, ink, paper, false, null);
        self.os.printText(self.fb, s, x, y, ink, paper);
    }
    // 6x6 system font (icon labels).
    pub fn textSmall(self: *Gui, s: []const u8, x: i16, y: i16, ink: u8, paper: u8) void {
        if (self.clip != null or self.rec != null) return clip.text(self, s, x, y, ink, paper, true, null);
        self.os.printTextSmall(self.fb, s, x, y, ink, paper);
    }

    // Text confined to `r` — clipped per PIXEL, so a glyph cell may overlap its
    // neighbours without painting over them.
    pub fn textClipped(self: *Gui, s: []const u8, x: i16, y: i16, ink: u8, paper: u8, r: Rect) void {
        if (self.clip != null or self.rec != null) return clip.text(self, s, x, y, ink, paper, false, r);
        self.os.printTextClipped(self.fb, s, x, y, ink, paper, .{
            .x0 = r.x,
            .y0 = r.y,
            .x1 = r.x + r.w,
            .y1 = r.y + r.h,
        });
    }

    // Text clipped to the span [lo, hi) a CHARACTER at a time: a name slides out of a
    // window letter by letter instead of vanishing whole, and stays on the cell grid.
    pub fn textIn(self: *Gui, s: []const u8, x: i16, y: i16, ink: u8, paper: u8, lo: i16, hi: i16) void {
        const c = hClip(s, x, 8, lo, hi);
        if (c.s.len > 0) self.text(c.s, c.x, y, ink, paper);
    }
    // The same, in the 6x6 system font (icon labels).
    pub fn textSmallIn(self: *Gui, s: []const u8, x: i16, y: i16, ink: u8, paper: u8, lo: i16, hi: i16) void {
        const c = hClip(s, x, 6, lo, hi);
        if (c.s.len > 0) self.textSmall(c.s, c.x, y, ink, paper);
    }
    fn hClip(s: []const u8, x: i16, fw: i16, lo: i16, hi: i16) struct { s: []const u8, x: i16 } {
        var str = s;
        var px = x;
        while (str.len > 0 and px < lo) { // characters off the left edge
            str = str[1..];
            px += fw;
        }
        while (str.len > 0 and px + @as(i16, @intCast(str.len)) * fw > hi) // off the right
            str = str[0 .. str.len - 1];
        return .{ .s = str, .x = px };
    }

    // A single pixel, clipped to the framebuffer (gadgets, hatch, icons, overlays plot here):
    // an unclipped write past an edge would wrap onto the neighbouring scanline.
    pub fn plot(self: *Gui, x: i16, y: i16, c: u8) void {
        if ((self.clip != null or self.rec != null) and !clip.plot(self, x, y)) return;
        if (x < 0 or x >= @as(i16, @intCast(self.fb.fb_w))) return;
        if (y < 0 or y >= @as(i16, @intCast(self.fb.fb_h))) return;
        self.fb.setPixelValue(@intCast(x), @intCast(y), c);
    }

    // GEM's dotted outline (every other pixel): every pending gesture (move, drag, zoom, band).
    pub fn dotted(self: *Gui, r: Rect, c: u8) void {
        if (clip.muted(self)) return; // GEM 5's logic pass: no pixel, skip the loop
        var x: i16 = r.x;
        while (x < r.x + r.w) : (x += 2) {
            self.plot(x, r.y, c);
            self.plot(x, r.y + r.h - 1, c);
        }
        var y: i16 = r.y;
        while (y < r.y + r.h) : (y += 2) {
            self.plot(r.x, y, c);
            self.plot(r.x + r.w - 1, y, c);
        }
    }

    // A GEM control gadget (a GWxGH box from the ST reference), opaque: 1 = ink, 0 = paper.
    pub fn gadget(self: *Gui, x: i16, y: i16, box: [glyphs.GH]u16, ink: u8, paper: u8) void {
        if (clip.muted(self)) return; // GEM 5's logic pass: no pixel, skip the per-pixel loop
        for (box, 0..) |bits, row| {
            var col: u4 = 0;
            while (col < glyphs.GW) : (col += 1) {
                const on = (bits >> @intCast(glyphs.GW - 1 - col)) & 1 != 0;
                self.plot(x + col, y + @as(i16, @intCast(row)), if (on) ink else paper);
            }
        }
    }

    // GEM "grey" fill (title-bar mover, scroll track), from the ST reference: one ink dot on
    // every even row at every odd column (25%), aligned to SCREEN coordinates like a VDI fill.
    pub fn hatch(self: *Gui, r: Rect, ink: u8, paper: u8) void {
        if (clip.muted(self)) return;
        self.rect(r, paper);
        var yy: i16 = r.y;
        while (yy < r.y + r.h) : (yy += 1) {
            if (yy & 1 != 0) continue;
            var xx: i16 = r.x | 1;
            while (xx < r.x + r.w) : (xx += 2)
                self.plot(xx, yy, ink);
        }
    }

    pub fn hit(self: *Gui, r: Rect) bool {
        return inRect(r, self.px, self.py);
    }
    // A flat GEM (TOS 1.x) button: white box, 1px black border, inverse video
    // while pressed or `active` (SELECTED). Returns true on the press frame.
    pub fn button(self: *Gui, r: Rect, label: []const u8, active: bool) bool {
        return self.buttonEx(r, label, active, false);
    }
    // `default` = the GEM default exit button: a solid 2px border (the outer
    // frame plus a second frame 1px inside it).
    pub fn buttonEx(self: *Gui, r: Rect, label: []const u8, active: bool, default: bool) bool {
        const held = active or (self.down and self.hit(r));
        const ink: u8 = if (held) WHITE else BLACK;
        const paper: u8 = if (held) BLACK else WHITE;
        self.rect(r, paper);
        self.frame(r, BLACK);
        if (default) self.frame(.{ .x = r.x + 1, .y = r.y + 1, .w = r.w - 2, .h = r.h - 2 }, BLACK);
        const tx = r.x + @divTrunc(r.w - @as(i16, @intCast(label.len)) * 8, 2);
        self.text(label, tx, r.y + @divTrunc(r.h - 8, 2), ink, paper);
        return self.edge and self.hit(r);
    }
    // A flat GEM button with an explicit border thickness (nested frames). GEM
    // dialogs use 1px for multi-choice buttons, 2px for a normal exit button,
    // 3px for the default (OK). Inverse-video while pressed or `active`.
    pub fn buttonThick(self: *Gui, r: Rect, label: []const u8, active: bool, border: i16) bool {
        const held = active or (self.down and self.hit(r));
        const ink: u8 = if (held) WHITE else BLACK;
        const paper: u8 = if (held) BLACK else WHITE;
        self.rect(r, paper);
        var i: i16 = 0;
        while (i < border) : (i += 1)
            self.frame(.{ .x = r.x + i, .y = r.y + i, .w = r.w - 2 * i, .h = r.h - 2 * i }, BLACK);
        const tx = r.x + @divTrunc(r.w - @as(i16, @intCast(label.len)) * 8, 2);
        self.text(label, tx, r.y + @divTrunc(r.h - 8, 2), ink, paper);
        return self.edge and self.hit(r);
    }
};
