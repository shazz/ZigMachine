// --------------------------------------------------------------------------
// NOTEPAD's view: the window's work area as rows of character cells over the
// document, scrolled by `top` (lines) and `left` (columns). It redraws only the
// rows the document touched since the last frame (a bit per row), so typing a
// letter repaints one row of text and an idle frame paints nothing. The window
// manager's sliders follow top / left (aes.Window.scroll) only when they change.
// --------------------------------------------------------------------------
const rom = @import("rom_sdk");
const aes = rom.aes;
const Doc = @import("doc.zig").Doc;
const Rect = rom.Rect;

pub const MAX_ROWS = 64; // 480 / 8 = 60 in the desk with the 8x8 font

pub const View = struct {
    g: rom.Gui,
    win: aes.Window,
    work: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    cw: i16 = 8,
    ch: i16 = 8,
    rows: u32 = 0,
    cols: u32 = 0,
    top: u32 = 0,
    left: u32 = 0,
    dirty: u64 = 0,
    widest: u32 = 0,
    shown_scroll: [6]i32 = .{ -1, -1, -1, -1, -1, -1 },

    /// The window moved or changed size: lay out again, every row to draw.
    pub fn layout(self: *View) void {
        self.work = self.win.work();
        const c = aes.cell(self.g);
        self.cw = c[0];
        self.ch = c[1];
        self.rows = @intCast(@min(MAX_ROWS, @max(1, @divTrunc(self.work.h, self.ch))));
        self.cols = @intCast(@max(1, @divTrunc(self.work.w + self.cw - 1, self.cw)));
        self.dirty = ~@as(u64, 0);
    }

    pub fn all(self: *View) void {
        self.dirty = ~@as(u64, 0);
    }

    // The rows showing lines [lo, hi] (or lo to the bottom).
    fn markLines(self: *View, lo: u32, hi: u32, to_end: bool) void {
        var r: u32 = 0;
        while (r < self.rows) : (r += 1) {
            const l = self.top + r;
            if (l >= lo and (to_end or l <= hi)) self.dirty |= @as(u64, 1) << @intCast(r);
        }
    }

    /// The document's edits since the last frame become dirty rows; the cursor is kept in view.
    pub fn absorb(self: *View, d: *Doc) void {
        if (d.touched.any()) {
            const t = d.touched;
            self.markLines(if (t.lo <= t.hi) t.lo else t.hi, t.hi, t.to_end);
            if (t.lo <= t.hi) self.widen(d, t.lo, t.hi, t.to_end);
            d.touched = .{};
        }
        self.follow(d);
    }

    // The widest line (the horizontal slider's bound): a rescan only when lines came or went.
    fn widen(self: *View, d: *const Doc, lo: u32, hi: u32, to_end: bool) void {
        if (to_end) {
            self.widest = d.text.widest();
            return;
        }
        var l = lo;
        while (l <= hi and l < d.text.lines) : (l += 1)
            self.widest = @max(self.widest, d.text.lineEnd(l) - d.text.lineStart(l));
    }

    // Scroll so the cursor's cell is in the work area.
    pub fn follow(self: *View, d: *const Doc) void {
        const l = d.line();
        const c = d.col();
        const t0 = self.top;
        const l0 = self.left;
        if (l < self.top) self.top = l;
        if (l >= self.top + self.rows) self.top = l + 1 - self.rows;
        const full = self.cols -| 1; // the last column may be cut by the scrollbar
        if (c < self.left) self.left = c;
        if (c >= self.left + @max(1, full)) self.left = c + 1 - @max(1, full);
        if (self.top != t0 or self.left != l0) self.all();
    }

    /// The scroll the window manager moved (an arrow, a slider, a track page).
    pub fn scrolledTo(self: *View, v: i32, h: i32) void {
        self.top = @intCast(@max(0, v));
        self.left = @intCast(@max(0, h));
        self.all();
    }

    /// The sliders, told only when they change.
    pub fn sliders(self: *View, d: *const Doc) void {
        const lines = d.text.lines;
        const vmax: i32 = @intCast(lines -| self.rows);
        const vsize: i32 = @intCast(if (lines <= self.rows) 1000 else self.rows * 1000 / lines);
        const w = @max(self.widest + 1, 1);
        const hmax: i32 = @intCast(w -| (self.cols -| 1));
        const hsize: i32 = @intCast(if (w <= self.cols - 1) 1000 else (self.cols - 1) * 1000 / w);
        const want = [6]i32{ vsize, @intCast(self.top), vmax, hsize, @intCast(self.left), hmax };
        if (std.mem.eql(i32, &want, &self.shown_scroll)) return;
        self.shown_scroll = want;
        self.win.scroll(true, vsize, want[1], vmax, @intCast(self.rows));
        self.win.scroll(false, hsize, want[4], hmax, @intCast(self.cols -| 1));
        self.win.drawBars();
    }

    /// The cell under (px, py) as a byte offset, clamped to the text.
    pub fn hit(self: *const View, d: *const Doc, px: i32, py: i32) u32 {
        const r: i32 = @divFloor(py - self.work.y, self.ch);
        const c: i32 = @divFloor(px - self.work.x + @divTrunc(self.cw, 2), self.cw);
        const l: u32 = @intCast(@max(0, @min(@as(i32, @intCast(d.text.lines - 1)), @as(i32, @intCast(self.top)) + r)));
        const col: u32 = @intCast(@max(0, @as(i32, @intCast(self.left)) + c));
        const len = d.text.lineEnd(l) - d.text.lineStart(l);
        return d.text.lineStart(l) + @min(col, len);
    }

    /// Paint the dirty rows (only those).
    pub fn draw(self: *View, d: *const Doc) void {
        if (self.dirty == 0) return;
        var r: u32 = 0;
        while (r < self.rows) : (r += 1) {
            if (self.dirty & (@as(u64, 1) << @intCast(r)) != 0) self.row(d, r);
        }
        // Below the last whole row: the work area's leftover pixels, cleared with the rows.
        const used: i16 = @intCast(self.rows * @as(u32, @intCast(self.ch)));
        if (self.dirty & 1 != 0 and used < self.work.h)
            self.g.rect(.{ .x = self.work.x, .y = self.work.y + used, .w = self.work.w, .h = self.work.h - used }, rom.WHITE);
        self.dirty = 0;
    }

    fn row(self: *View, d: *const Doc, r: u32) void {
        const y: i16 = self.work.y + @as(i16, @intCast(r)) * self.ch;
        const clip = Rect{ .x = self.work.x, .y = y, .w = self.work.w, .h = self.ch };
        self.g.rect(clip, rom.WHITE);
        const l = self.top + r;
        if (l >= d.text.lines) return;
        const s = d.text.lineStart(l);
        const e = d.text.lineEnd(l);
        const from = @min(e, s + self.left);
        const to = @min(e, from + self.cols);
        // The line's visible bytes in up to three runs: before, inside, after the selection.
        const lo = @max(from, @min(to, d.selLo()));
        const hi = @max(lo, @min(to, d.selHi()));
        self.run(d, from, lo, s, y, clip, false);
        self.run(d, lo, hi, s, y, clip, true);
        self.run(d, hi, to, s, y, clip, false);
        // A selection that runs on past the line's end shows its line break as one inverse cell.
        if (d.hasSel() and d.selLo() <= e and d.selHi() > e and e >= s + self.left and e < s + self.left + self.cols)
            self.g.rect(.{ .x = self.cx(e - s), .y = y, .w = self.cw, .h = self.ch }, rom.BLACK);
        if (l == d.line() and !d.hasSel()) {
            const c = d.col();
            if (c >= self.left and c < self.left + self.cols)
                self.g.rect(.{ .x = self.cx(c), .y = y, .w = 2, .h = self.ch }, rom.BLACK);
        }
    }

    fn cx(self: *const View, col: u32) i16 {
        return self.work.x + @as(i16, @intCast(col - self.left)) * self.cw;
    }

    fn run(self: *View, d: *const Doc, a: u32, b: u32, s: u32, y: i16, clip: Rect, inverse: bool) void {
        if (b <= a) return;
        var buf: [MAX_COLS]u8 = undefined;
        const n = @min(b - a, MAX_COLS);
        for (d.text.buf[a .. a + n], 0..) |c, i| buf[i] = if (c == '\t') ' ' else c;
        const ink: u8 = if (inverse) rom.WHITE else rom.BLACK;
        const paper: u8 = if (inverse) rom.BLACK else rom.WHITE;
        aes.textClip(self.g, buf[0..n], self.cx(a - s), y, ink, paper, clip);
    }
};

const MAX_COLS = 96; // 640 / 8 + the cut column
const std = @import("std");
