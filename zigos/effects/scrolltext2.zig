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

        // One control code (or one letter) per recycling slot per frame -
        // exactly mirrors the original's single `if/else` at the recycle site.
        fn recycle(self: *Self, x: *i32, ch: *u8, gw: i32) void {
            if (self.text[self.text_pos] == '^' and self.text_pos + 2 < self.text.len) {
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
                return;
            }
            x.* = @as(i32, @intCast(num_slots)) * gw + (x.* + gw);
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

        fn drawGlyph(self: *const Self, dst: []u8, stride: usize, dst_w: u16, x: i32, ch: u8) void {
            const cfg = self.cfg;
            const idx: u16 = @as(u16, ch - cfg.ascii_base);
            const gcol: u16 = idx % cfg.cols;
            const grow: u16 = idx / cfg.cols;
            const sheet_w: usize = cfg.font_out_sheet_w;
            var gy: u16 = 0;
            while (gy < cfg.glyph_h) : (gy += 1) {
                const bit_row = @as(usize, grow) * cfg.glyph_h + gy;
                var gx: u16 = 0;
                while (gx < cfg.glyph_w) : (gx += 1) {
                    const px = x + @as(i32, gx);
                    if (px < 0 or px >= dst_w) continue;
                    const bit_col = @as(usize, gcol) * cfg.glyph_w + gx;
                    const sheet_off = bit_row * sheet_w + bit_col;
                    const dpx: usize = @intCast(px);
                    const doff = @as(usize, gy) * stride + dpx;

                    const byte = cfg.font_in_bits[sheet_off / 8];
                    const bit = (byte >> @intCast(7 - (sheet_off % 8))) & 1;
                    if (bit == 1) {
                        const rx = dpx % cfg.raster_w;
                        const ry = @as(usize, gy) % cfg.raster_h;
                        dst[doff] = cfg.raster[ry * @as(usize, cfg.raster_w) + rx];
                    }
                    const outline = cfg.font_out[sheet_off];
                    if (outline != 0) dst[doff] = outline;
                }
            }
        }
    };
}
