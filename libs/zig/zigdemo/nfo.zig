//! NFO / ASCII-art viewer core, in the look of an Amiga ASCII viewer (docs: libs/zig/zigdemo/README.md).
//! CP437 text goes into ONE tall 640-wide buffer of palette indices, painted once; the scroll is
//! only a pan of the plane's read base (`y`), so a frame costs nothing. An optional prompt bar
//! stays fixed at the bottom of the 640x480 window while the text moves under it: the bar's rows
//! are rewritten into the buffer when `y` moves (one text row restored, 18 bar rows copied),
//! because the desk mode has one plane only. Hardware-free: nfo_plane.zig binds it to a plane.
const std = @import("std");
const glyph = @import("nfo_glyph.zig");
const render = @import("nfo_render.zig");

pub const Error = render.Error || error{BadConfig};
pub const screen_h: u32 = 480;
pub const bar_h = render.bar_h;
pub const row_px = render.row_px;

pub const End = enum { stop, loop };

pub const Config = struct {
    /// Frames per 1-pixel step (60 fps): 1 = 60 px/s, 3 = 20 px/s.
    frames_per_px: u16 = 3,
    /// Frames the first screen stays still before the scroll starts.
    start_delay: u16 = 180,
    /// At the last row: stay (`stop`) or, after `end_hold` frames, jump back to the top (`loop`).
    end: End = .stop,
    end_hold: u16 = 240,
    /// The fixed bottom line (ASCII, at most 80 columns); empty = no bar.
    prompt: []const u8 = "",
    /// The keys that choose (ASCII, matched without case); `key()` returns the one pressed.
    keys: []const u8 = "",
};

pub const Nfo = struct {
    pub const palette = glyph.palette;

    text: render.Text,
    cfg: Config,
    y: u32 = 0,
    y_max: u32,
    buf: []u8 = &.{},
    bar: [bar_h * row_px]u8 = undefined,
    timer: u32 = 0,
    hold: u32 = 0,
    chosen: ?u8 = null,

    /// `bytes` is CP437 (keep it alive: the viewer reads it on every restored row).
    pub fn init(bytes: []const u8, cfg: Config) Error!Nfo {
        if (cfg.frames_per_px == 0) return error.BadConfig;
        const text = try render.Text.parse(bytes);
        var self = Nfo{ .text = text, .cfg = cfg, .y_max = 0 };
        const shown = screen_h - self.barRows();
        self.y_max = if (text.height() > shown) text.height() - shown else 0;
        if (cfg.prompt.len > 0) try render.buildBar(cfg.prompt, &self.bar);
        return self;
    }

    /// Rows the buffer needs: the window can sit at any y up to `y_max`.
    pub fn bufferRows(self: *const Nfo) u32 {
        return self.y_max + screen_h;
    }

    pub fn bufferBytes(self: *const Nfo) usize {
        return @as(usize, self.bufferRows()) * row_px;
    }

    /// Paint the whole buffer once (`buf` holds bufferBytes()); keep it: update() edits it.
    pub fn paint(self: *Nfo, buf: []u8) void {
        std.debug.assert(buf.len >= self.bufferBytes());
        self.buf = buf;
        for (0..self.bufferRows()) |r| self.paintRow(@intCast(r));
        self.drawBar();
    }

    /// One frame: advance the timers and the scroll. Returns y, the row at the top of the window.
    pub fn update(self: *Nfo) u32 {
        if (self.timer < self.cfg.start_delay) {
            self.timer += 1;
            return self.y;
        }
        if (self.y >= self.y_max) return self.atEnd();
        self.timer += 1;
        if ((self.timer - self.cfg.start_delay) % self.cfg.frames_per_px == 0) self.scrollTo(self.y + 1);
        return self.y;
    }

    fn atEnd(self: *Nfo) u32 {
        if (self.cfg.end != .loop) return self.y;
        self.hold += 1;
        if (self.hold >= self.cfg.end_hold) {
            self.hold = 0;
            self.timer = 0;
            self.scrollTo(0);
        }
        return self.y;
    }

    pub fn scrollBy(self: *Nfo, dy: i32) void {
        const to = std.math.clamp(@as(i64, self.y) + dy, 0, @as(i64, self.y_max));
        self.scrollTo(@intCast(to));
    }

    /// Move the window to row `y` (clamped): repaint the text rows the bar leaves, draw it anew.
    pub fn scrollTo(self: *Nfo, to: u32) void {
        const new = @min(to, self.y_max);
        if (new == self.y) return;
        const old_lo = self.barTop();
        self.y = new;
        const new_lo = self.barTop();
        if (self.buf.len == 0 or self.cfg.prompt.len == 0) return;
        for (old_lo..old_lo + bar_h) |r| {
            if (r < new_lo or r >= new_lo + bar_h) self.paintRow(@intCast(r));
        }
        self.drawBar();
    }

    /// The key a press chose, if any: `cp` is the host's code point; the choice is also kept in `chosen`.
    pub fn key(self: *Nfo, cp: u32) ?u8 {
        if (cp > 0x7E) return null;
        const up = std.ascii.toUpper(@intCast(cp));
        for (self.cfg.keys) |k| if (std.ascii.toUpper(k) == up) {
            self.chosen = k;
            return k;
        };
        return null;
    }

    /// First buffer row of the bar for the current y.
    pub fn barTop(self: *const Nfo) u32 {
        return self.y + screen_h - self.barRows();
    }

    fn barRows(self: *const Nfo) u32 {
        return if (self.cfg.prompt.len > 0) bar_h else 0;
    }

    fn paintRow(self: *Nfo, r: u32) void {
        render.renderRow(&self.text, r, self.buf[@as(usize, r) * row_px ..][0..row_px]);
    }

    fn drawBar(self: *Nfo) void {
        if (self.cfg.prompt.len == 0) return;
        const top: usize = self.barTop();
        @memcpy(self.buf[top * row_px ..][0 .. bar_h * row_px], &self.bar);
    }
};

pub const plane = @import("nfo_plane.zig");
pub const cp437 = @import("nfo_cp437.zig");
