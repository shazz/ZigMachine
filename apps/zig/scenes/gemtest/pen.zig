// --------------------------------------------------------------------------
// GEMTEST's pen: lays a window's content out in rows over its work area, scrolled
// by the window's sliders (rows down, columns across). The same layout runs twice:
// to DRAW (only what lies wholly inside the work area: the ROM's buttons and boxes
// do not clip, text does, aes.textClip) and to HIT-TEST a press (which control is
// under it). So a control is where it is drawn by construction, and the content's
// extent (the sliders' bounds) comes out of the same pass.
// --------------------------------------------------------------------------
const rom = @import("rom_sdk");
const aes = rom.aes;
const Rect = rom.Rect;

pub const NONE: u8 = 0xFF;

pub const Pen = struct {
    g: rom.Gui,
    work: Rect,
    cw: i32 = 8,
    ch: i32 = 8,
    ox: i32 = 0, // the content's origin on screen
    oy: i32 = 0,
    x: i32 = 0, // the cursor, in content pixels
    y: i32 = 0,
    row_h: i32 = 0,
    drawing: bool = true,
    hx: i32 = 0, // the press being hit-tested (drawing = false)
    hy: i32 = 0,
    hit: u8 = NONE,
    max_x: i32 = 0, // the content's extent so far
    max_y: i32 = 0,

    pub fn init(g: rom.Gui, work: Rect, top: i32, left: i32) Pen {
        const c = aes.cell(g);
        var p = Pen{ .g = g, .work = work, .cw = c[0], .ch = c[1] };
        p.ox = work.x - left * p.cw;
        p.oy = work.y - top * p.ch;
        p.x = p.cw;
        p.y = @divTrunc(p.ch, 2);
        return p;
    }

    /// The content's size in cells (rows, columns), rounded up, for the sliders.
    pub fn extent(self: *const Pen) [2]i32 {
        return .{ @divTrunc(self.max_y + self.ch - 1, self.ch), @divTrunc(self.max_x + self.cw - 1, self.cw) };
    }

    fn grow(self: *Pen, x1: i32, y1: i32) void {
        self.max_x = @max(self.max_x, x1 + self.cw);
        self.max_y = @max(self.max_y, y1 + @divTrunc(self.ch, 2));
    }

    fn screen(self: *const Pen, x: i32, y: i32, w: i32, h: i32) Rect {
        return .{ .x = @intCast(clamp(self.ox + x)), .y = @intCast(clamp(self.oy + y)), .w = @intCast(clamp(w)), .h = @intCast(clamp(h)) };
    }

    /// A rect wholly in the work area (drawn), and the press test.
    fn place(self: *Pen, id: u8, r: Rect) bool {
        if (!self.drawing) {
            if (id != NONE and self.hx >= r.x and self.hx < r.x + r.w and self.hy >= r.y and self.hy < r.y + r.h) self.hit = id;
            return false;
        }
        const wk = self.work;
        return r.x >= wk.x and r.y >= wk.y and r.x + r.w <= wk.x + wk.w and r.y + r.h <= wk.y + wk.h;
    }

    /// A line of text on its own row, cut at the work area's edges.
    pub fn line(self: *Pen, s: []const u8) void {
        self.textAt(s, self.cw, self.y, rom.BLACK);
        self.y += self.ch;
    }
    /// A line in the ROM's disabled grey: what the API does not have yet.
    pub fn missing(self: *Pen, what: []const u8) void {
        self.textAt("not in the API yet:", self.cw, self.y, rom.DGRAY);
        self.textAt(what, self.cw * 21, self.y, rom.DGRAY);
        self.y += self.ch;
    }
    pub fn gap(self: *Pen) void {
        self.y += @divTrunc(self.ch, 2);
    }

    fn textAt(self: *Pen, s: []const u8, x: i32, y: i32, ink: u8) void {
        self.grow(x + @as(i32, @intCast(s.len)) * self.cw, y + self.ch);
        if (!self.drawing) return;
        const sy = self.oy + y;
        if (sy + self.ch <= self.work.y or sy >= self.work.y + self.work.h) return;
        aes.textClip(self.g, s, @intCast(clamp(self.ox + x)), @intCast(clamp(sy)), ink, rom.WHITE, self.work);
    }

    /// A row of controls `h` pixels high; each control goes right of the last.
    pub fn row(self: *Pen, h: i32) void {
        self.x = self.cw;
        self.row_h = h;
    }
    pub fn endRow(self: *Pen) void {
        self.y += self.row_h + 4;
        self.row_h = 0;
    }

    /// Text inside a row (a control's caption), vertically centred.
    pub fn label(self: *Pen, s: []const u8) void {
        self.textAt(s, self.x, self.y + @divTrunc(self.row_h - self.ch, 2), rom.BLACK);
        self.x += (@as(i32, @intCast(s.len)) + 1) * self.cw;
    }

    /// A ROM button (guiButton): border 1 plain, 2 exit, 3 default; `active` shows it selected.
    pub fn button(self: *Pen, id: u8, s: []const u8, active: bool, border: u32) void {
        const w = (@as(i32, @intCast(s.len)) + 2) * self.cw;
        const r = self.screen(self.x, self.y, w, self.row_h);
        self.grow(self.x + w, self.y + self.row_h);
        if (self.place(id, r)) _ = self.g.button(r, s, active, border);
        self.x += w + self.cw;
    }

    /// A box of the ROM's (guiBox: white, `inset` black frames), `w` x the row, with a caption.
    pub fn box(self: *Pen, w: i32, inset: u32, s: []const u8) void {
        const r = self.screen(self.x, self.y, w, self.row_h);
        self.grow(self.x + w, self.y + self.row_h);
        if (self.place(NONE, r)) {
            self.g.box(r, inset);
            self.g.text(s, r.x + 4 + @as(i16, @intCast(inset)), r.y + @divTrunc(r.h - 8, 2), rom.BLACK, rom.WHITE);
        }
        self.x += w + self.cw;
    }

    /// A control the program draws itself out of the ROM's frame and fill: a box `w` x the row,
    /// and its rect on screen (null: not drawn this pass, or out of the work area).
    pub fn own(self: *Pen, id: u8, w: i32) ?Rect {
        const r = self.screen(self.x, self.y, w, self.row_h);
        self.grow(self.x + w, self.y + self.row_h);
        self.x += w + self.cw;
        return if (self.place(id, r)) r else null;
    }
};

fn clamp(v: i32) i32 {
    return @max(-16000, @min(16000, v));
}
