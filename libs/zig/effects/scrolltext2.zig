// --------------------------------------------------------------------------
// Scrolltext2 — reusable, stride-agnostic horizontal scrolltext effect.
//
// Unlike `scrolltext.zig` (320-wide/u16-only, no control codes), this effect
// knows nothing about LogicalFB/ZigOS: it owns only the scroll/text state and
// draws glyphs into a caller-supplied byte buffer at an arbitrary `stride`, so
// any scene can point it at a plane's framebuffer OR an off-screen strip.
//
// Faithful to Codef `codef_fx_optim.js` scrolltext_horizontal: `speed` px/frame
// (0 == paused), text control codes consumed only at the moment a slot recycles
// (mirrors the original's per-frame, per-slot recycle check):
//   ^P<digit> - pause the WHOLE scroller for 60*digit frames (all slots freeze).
//   ^S<digit> - set scroll speed (px/frame) from digit onward.
// A slot recycles when its x <= -glyph_w; its new x preserves the sub-glyph
// overshoot (`num_slots*glyph_w + (x + glyph_w)`) for a seamless scroll.
//
// Compositing per glyph: the interior (font_in_bits bit==1) is filled with the
// `raster` pattern sampled at the glyph's *destination* (screen) position, not
// glyph-local, so the pattern is fixed in screen space; the `font_out` outline
// (indexed, 0 == transparent) is drawn on top. Characters with ascii >= 92 or
// '/' are blank (no glyph in the outline sheet), matching the original assets.
// --------------------------------------------------------------------------
const std = @import("std");
const rows = @import("blit_rows.zig");

pub const Config = struct {
    glyph_w: u16 = 32,
    glyph_h: u16 = 32,
    cols: u16 = 10,
    ascii_base: u8 = 32,
    font_out_sheet_w: u16, // pixel width of both font_out and font_in_bits sheets
    font_out: []const u8, // indexed pixels, sheet_w x (rows*glyph_h), 0 = transparent
    font_in_bits: []const u8, // 1bpp MSB-first mask, same geometry as font_out
    raster: []const u8, // fill pattern sampled at (dst_x % raster_w, local_y % raster_h)
    raster_w: u16,
    raster_h: u16,
};

fn isBlank(c: u8) bool {
    return c >= 92 or c == '/';
}

pub fn Scroller(comptime num_slots: usize) type {
    return struct {
        const Self = @This();

        cfg: Config = undefined,
        text: []const u8 = undefined,
        text_pos: usize = 0,
        speed: i32 = 3,
        old_speed: i32 = 3,
        pause_timer: u32 = 0,
        pause_frames: u32 = 0,
        slot_x: [num_slots]i32 = [_]i32{0} ** num_slots,
        slot_ch: [num_slots]u8 = [_]u8{' '} ** num_slots,

        pub fn init(self: *Self, cfg: Config, text: []const u8, speed: i32) void {
            self.cfg = cfg;
            self.text = text;
            self.text_pos = 0;
            self.speed = speed;
            self.old_speed = speed;
            self.pause_timer = 0;
            self.pause_frames = 0;
            const gw: i32 = @intCast(cfg.glyph_w);
            var i: usize = 0;
            while (i < num_slots) : (i += 1) {
                self.slot_x[i] = @as(i32, @intCast(i)) * gw;
                self.slot_ch[i] = self.feed();
            }
        }

        fn feed(self: *Self) u8 {
            const c = self.text[self.text_pos];
            self.text_pos += 1;
            if (self.text_pos >= self.text.len) self.text_pos = 0;
            return c;
        }

        pub fn update(self: *Self) void {
            if (self.speed == 0) {
                self.pause_timer += 1;
                if (self.pause_timer >= self.pause_frames) self.speed = self.old_speed;
            }
            const cur_speed = self.speed;
            const gw: i32 = @intCast(self.cfg.glyph_w);
            for (&self.slot_x, &self.slot_ch) |*x, *ch| {
                x.* -= cur_speed;
                if (x.* <= -gw) self.recycle(x, ch, gw);
            }
        }

        // Recycle a slot: control codes do NOT occupy a slot, so consume ALL
        // codes at the feed point first, then always feed a letter + reposition
        // (consuming a code without repositioning would leave a one-glyph gap).
        fn recycle(self: *Self, x: *i32, ch: *u8, gw: i32) void {
            while (self.text[self.text_pos] == '^' and self.text_pos + 2 < self.text.len) {
                const code = self.text[self.text_pos + 1];
                const digit: u32 = self.text[self.text_pos + 2] - '0';
                if (code == 'P') {
                    self.pause_frames = 60 * digit;
                    self.pause_timer = 0;
                    self.old_speed = self.speed;
                    self.speed = 0;
                } else if (code == 'S') {
                    self.speed = @intCast(digit);
                }
                self.text_pos += 3;
                if (self.text_pos >= self.text.len) self.text_pos = 0;
            }
            // Reposition one glyph-pitch to the right of the current rightmost
            // slot: the other slots span x+gw .. x+(num_slots-1)*gw, so the new
            // x is x + num_slots*gw (preserving the sub-glyph overshoot). Adding
            // an extra gw here left a one-glyph hole on every recycle.
            x.* = x.* + @as(i32, @intCast(num_slots)) * gw;
            ch.* = self.feed();
        }

        // Draws every visible slot into `dst` (row-major, `stride` units/row),
        // rows [0, cfg.glyph_h). `dst_w` clips column writes.
        pub fn draw(self: *const Self, dst: []u8, stride: usize, dst_w: u16) void {
            for (self.slot_x, self.slot_ch) |x, ch| {
                if (isBlank(ch)) continue;
                self.drawGlyph(dst, stride, dst_w, x, ch);
            }
        }

        // The old loop clipped every pixel and stored up to two bytes a pixel
        // (the raster ink, then the outline over it), each a blocking bus write
        // on the board. Now the clip is one column range a glyph and each row's
        // final pixels go out a word at a time (blit_rows) -- the same bytes:
        // the outline where it is non-zero, else the raster where the mask bit
        // is set, else untouched (scrolltext2_test.zig).
        pub fn drawGlyph(self: *const Self, dst: []u8, stride: usize, dst_w: u16, x: i32, ch: u8) void {
            const cfg = self.cfg;
            const idx: u16 = @as(u16, ch - cfg.ascii_base);
            const gcol: u16 = idx % cfg.cols;
            const grow: u16 = idx / cfg.cols;
            const sheet_w: usize = cfg.font_out_sheet_w;
            const gx0: usize = @intCast(@max(0, -x));
            const gx1: usize = @intCast(@max(0, @min(@as(i32, cfg.glyph_w), @as(i32, dst_w) - x)));
            if (gx1 <= gx0) return;
            const dpx0: usize = @intCast(x + @as(i32, @intCast(gx0)));
            const n = gx1 - gx0;
            const rx0 = dpx0 % cfg.raster_w;
            var gy: u16 = 0;
            while (gy < cfg.glyph_h) : (gy += 1) {
                const bit_row = @as(usize, grow) * cfg.glyph_h + gy;
                const sheet0 = bit_row * sheet_w + @as(usize, gcol) * cfg.glyph_w + gx0;
                var px = GlyphRow{
                    .bits = cfg.font_in_bits.ptr,
                    .so = sheet0,
                    .raster = cfg.raster[(@as(usize, gy) % cfg.raster_h) * @as(usize, cfg.raster_w) ..].ptr,
                    .rx = rx0,
                    .rw = cfg.raster_w,
                };
                rows.row(dst[@as(usize, gy) * stride + dpx0 ..][0..n], cfg.font_out[sheet0..][0..n], &px, GlyphRow.pick, false);
            }
        }

        // One glyph row's pixels for rows.row, which calls pick once per pixel
        // in order: `so` (the sheet offset) and `rx` (the raster column) step
        // along with it. The outline where it is non-zero, else the raster where
        // the mask bit is set, else nothing.
        const GlyphRow = struct {
            bits: [*]const u8,
            so: usize,
            raster: [*]const u8,
            rx: usize,
            rw: usize,

            inline fn pick(g: *GlyphRow, outline: u8, _: u8, _: usize) rows.Px {
                const bit = (g.bits[g.so >> 3] >> @intCast(7 - (g.so & 7))) & 1;
                const r = g.raster[g.rx];
                g.so += 1;
                g.rx += 1;
                if (g.rx == g.rw) g.rx = 0;
                if (outline != 0) return rows.put(outline);
                return if (bit == 1) rows.put(r) else rows.skip;
            }
        };

    };
}
