// --------------------------------------------------------------------------
// Gui — pointer state + immediate-mode drawing primitives, held for one frame.
// Immediate-mode drawing over the blitter (fast fills) + ZigOS text. Pointer
// state comes from the host via demo.pointer() (see sealed-loader.js).
// --------------------------------------------------------------------------
const zsrc = @import("zigos");
const ZigOS = zsrc.ZigOS;
const LogicalFB = zsrc.LogicalFB;
const Blitter = zsrc.Blitter;
const glyphs = @import("../gem_glyphs.zig");
const types = @import("types.zig");
const Rect = types.Rect;
const inRect = types.inRect;
const BLACK = types.BLACK;
const WHITE = types.WHITE;
const DGRAY = types.DGRAY;

pub const Gui = struct {
    os: *ZigOS,
    fb: *LogicalFB,
    blit: *Blitter,
    screen_w: i16 = 320, // set to 640 for a medium-res app (centres dialogs etc.)
    screen_h: i16 = 200,
    px: i32 = -1,
    py: i32 = -1,
    down: bool = false,
    prev: bool = false,
    edge: bool = false, // press started this frame

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

    // --- primitives ---
    pub fn rect(self: *Gui, r: Rect, color: u8) void {
        self.blit.fill(self.fb, r.x, r.y, @intCast(r.w), @intCast(r.h), color);
    }
    pub fn frame(self: *Gui, r: Rect, color: u8) void {
        self.blit.fill(self.fb, r.x, r.y, @intCast(r.w), 1, color);
        self.blit.fill(self.fb, r.x, r.y + r.h - 1, @intCast(r.w), 1, color);
        self.blit.fill(self.fb, r.x, r.y, 1, @intCast(r.h), color);
        self.blit.fill(self.fb, r.x + r.w - 1, r.y, 1, @intCast(r.h), color);
    }
    // A raised (or sunken) 3D bevel box (TOS 4 / MagiC look — NOT used by the
    // TOS 1.x-style chrome, kept for apps that want it).
    pub fn bevel(self: *Gui, r: Rect, face: u8, raised: bool) void {
        const hi: u8 = if (raised) WHITE else DGRAY;
        const lo: u8 = if (raised) DGRAY else WHITE;
        self.rect(r, face);
        self.blit.fill(self.fb, r.x, r.y, @intCast(r.w), 1, hi);
        self.blit.fill(self.fb, r.x, r.y, 1, @intCast(r.h), hi);
        self.blit.fill(self.fb, r.x, r.y + r.h - 1, @intCast(r.w), 1, lo);
        self.blit.fill(self.fb, r.x + r.w - 1, r.y, 1, @intCast(r.h), lo);
    }
    pub fn text(self: *Gui, s: []const u8, x: i16, y: i16, ink: u8, paper: u8) void {
        self.os.printText(self.fb, s, x, y, ink, paper);
    }
    // 6x6 system font (icon labels).
    pub fn textSmall(self: *Gui, s: []const u8, x: i16, y: i16, ink: u8, paper: u8) void {
        self.os.printTextSmall(self.fb, s, x, y, ink, paper);
    }

    // A single pixel, clipped to the framebuffer. Everything that plots directly
    // (gadgets, hatch, icons, dotted overlays) goes through here: a window can be
    // dragged past an edge, and an unclipped write there wraps onto the
    // neighbouring scanline instead of disappearing.
    pub fn plot(self: *Gui, x: i16, y: i16, c: u8) void {
        if (x < 0 or x >= @as(i16, @intCast(self.fb.fb_w))) return;
        if (y < 0 or y >= @as(i16, @intCast(self.fb.fb_h))) return;
        self.fb.setPixelValue(@intCast(x), @intCast(y), c);
    }

    // A GEM dotted rectangle outline (every other pixel) — the shape every
    // "pending" gesture is drawn with: window move/resize, icon drag, the
    // window-open zoom box, the rubber-band marquee.
    pub fn dotted(self: *Gui, r: Rect, c: u8) void {
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

    // Blit a GEM control gadget (a GWxGH box lifted verbatim from the ST GEM
    // reference: frame + background + symbol) opaquely at (x,y). 1 = ink, 0 = paper.
    pub fn gadget(self: *Gui, x: i16, y: i16, box: [glyphs.GH]u16, ink: u8, paper: u8) void {
        for (box, 0..) |bits, row| {
            var col: u4 = 0;
            while (col < glyphs.GW) : (col += 1) {
                const on = (bits >> @intCast(glyphs.GW - 1 - col)) & 1 != 0;
                self.plot(x + col, y + @as(i16, @intCast(row)), if (on) ink else paper);
            }
        }
    }

    // GEM "grey" pattern fill — the title-bar mover / scrollbar track. Lifted
    // from the ST reference: one ink dot on every even row at every odd column
    // (25%), aligned to SCREEN coordinates like a VDI pattern fill.
    pub fn hatch(self: *Gui, r: Rect, ink: u8, paper: u8) void {
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
