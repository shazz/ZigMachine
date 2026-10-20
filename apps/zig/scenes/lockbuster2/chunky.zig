// --------------------------------------------------------------------------
// The six scroll engines and the title slides on CHUNKY surfaces, as blits.
//
// engine.zig is the reference: the Go clock transcribed onto the ST's planar
// bytes and pinned by the original machine's RAM checkpoints. This is the same
// clock (every counter, flag and phase rule in the same order), but each tick
// is a short list of rectangle ops instead of ~4,000 byte moves and a 32000-byte
// planar-to-chunky expansion a frame (64,000 pixel stores, more than the board's
// whole frame of DDR writes). chunky_test.zig runs both engines side by side and
// demands expand(planar screen) == this engine's front surface on every tick.
//
// THE SURFACES. The ring's two 128 KB buffers become two 320x200 surfaces
// (RING_A/RING_B): the rows a map pass or a trail READS are all on screen
// (chunky_tables asserts it), so the off-screen part of the ring is write-only
// and clipping it away changes nothing visible. A third surface, DISPLAY, is
// the shown plane: present() copies the front ring onto it, and a trail pass
// first copies its source rows there, so that EVERY copy reads one surface and
// writes another (on the board a CHISEL copy inside one plane runs ordered,
// one read per finished write).
//
// The backend `Gpu` is duck-typed: CHISEL in the cart (chisel_gpu.zig), plain
// arrays in the native test. Every rectangle it is handed is already clipped.
// NO FLOAT: integers only, like the 68000.
// --------------------------------------------------------------------------
const std = @import("std");
const ref = @import("engine.zig");
const tab = @import("chunky_tables.zig");
const trl = tab.trails;

pub const DISPLAY: u8 = 0;
pub const RING_A: u8 = 1;
pub const RING_B: u8 = 2;
const H: i32 = @intCast(tab.H);
const W: u16 = @intCast(tab.W);

pub fn Engine(comptime Gpu: type) type {
    return struct {
        const Self = @This();
        gpu: *Gpu,
        front: u1 = 0,
        tick: usize = 0,
        phase: i32 = -1,
        frame: usize = 0,
        byte_phase: usize = 0,
        offset: usize = 0,
        remaining: usize = 0,
        header_tick: usize = 0,
        text: []const u8 = &.{},
        gold: bool = false, // gold (F1) or metallic (F2) screen palette
        color_text: bool = false, // per-line colour-1 raster (F3) or black text (F4)
        new_raster: bool = false, // raster-new.bin (F5) or raster-old.bin (F6)

        /// The surfaces start zeroed, as Go's make() rings did.
        pub fn init(self: *Self, gpu: *Gpu) void {
            self.* = .{ .gpu = gpu };
            for ([_]u8{ DISPLAY, RING_A, RING_B }) |s| gpu.fill(s, 0, 0, W, @intCast(H), 0);
        }

        fn ring(i: u1) u8 {
            return if (i == 0) RING_A else RING_B;
        }

        pub fn frontSurface(self: *const Self) u8 {
            return ring(self.front);
        }

        /// The shown plane takes the front ring (once per rendered frame).
        pub fn present(self: *Self) void {
            self.gpu.copy(DISPLAY, 0, 0, ring(self.front), 0, 0, W, @intCast(H));
        }

        /// engine.zig step(), op for op.
        pub fn step(self: *Self) void {
            self.tick += 1;
            if (self.header_tick < ref.TITLE_TICKS) return self.slide();
            if (self.remaining == 0) self.nextPhase();
            const mode: usize = ref.mode_of_phase[@intCast(self.phase)];
            if (self.frame == 4) {
                self.frame = 0;
                self.offset += 384;
            }
            const base = tab.baseRow(mode);
            const to = ring(1 - self.front);
            self.mapPass(mode, base, ring(self.front), to);
            self.front = 1 - self.front;
            self.byte_phase ^= 1;
            if (self.byte_phase == 0) self.offset += 6;
            self.offset += 1;
            self.frame += 1;
            self.remaining -= 1;
            self.trails(mode, base, to);
            if (mode == 4) self.wedge(to);
        }

        /// The title slides: bank 0 slides down over 305 VBLs, bank 1 (gold on) up.
        fn slide(self: *Self) void {
            const bank = self.header_tick / 305;
            const frame: i32 = @intCast(self.header_tick % 305 + 1);
            var start: i32 = -99 + frame;
            if (bank == 1) {
                self.gold = true;
                start = 202 - frame;
            }
            const rows: i32 = @intCast(tab.HEADER_ROWS[bank]);
            const lo = @max(start, 0);
            const hi = @min(start + rows, H);
            const target = ring(1 - self.front);
            if (lo < hi) self.gpu.image(target, 0, @intCast(lo), &tab.headers[bank], W, 0, @intCast(lo - start), W, @intCast(hi - lo));
            self.front = 1 - self.front;
            self.header_tick += 1;
        }

        fn nextPhase(self: *Self) void {
            self.phase = @mod(self.phase + 1, ref.MAX_PHASES);
            self.frame = 0;
            self.byte_phase = 0;
            self.offset = 0;
            self.text = ref.messages[2 + @as(usize, @intCast(self.phase))];
            self.remaining = self.text.len * 4;
            switch (self.phase) {
                0, 2 => self.color_text = false,
                1, 5 => {
                    self.gold = true;
                    self.color_text = true;
                },
                3 => self.gold = true,
                4 => {
                    self.color_text = false;
                    self.new_raster = false;
                },
                else => {}, // phases 6 and 7 replay phase 5's look, flags untouched
            }
        }

        /// The band of `mode`'s copy map: each span one blit `from` -> `to`, and
        /// the text column straight from the comptime font strip.
        fn mapPass(self: *Self, mode: usize, base: i32, from: u8, to: u8) void {
            const h = tab.bandHeight(mode);
            const m = tab.maps[mode];
            for (m.spans) |s| {
                const c = clip(base + s.dr, h) orelse continue;
                const sy = base + s.sr + c.skip;
                self.gpu.copy(to, s.dx, @intCast(c.y), from, s.sx, @intCast(sy), s.w, @intCast(c.h));
            }
            // The compiled text: glyph i = offset / 400; offset % 400 is 0, 1, 8 or 9,
            // the glyph's 8-px column (chunk offset/8, half offset%2).
            const c = clip(base + m.text_dr, h) orelse return;
            const i = self.offset / ref.GLYPH_BYTES;
            const rem = self.offset % ref.GLYPH_BYTES;
            std.debug.assert(rem % 8 < 2 and rem < 16);
            const g: usize = @intCast(std.math.clamp(@as(i32, self.text[i]) - 32, 0, 58));
            const sx = g * 32 + (rem / 8) * 16 + (rem % 2) * 8;
            self.gpu.image(to, m.text_dx, @intCast(c.y), &tab.font, tab.FONT_W, @intCast(sx), @intCast(c.skip), 8, @intCast(c.h));
        }

        /// pass(): the trail rows read the ring's own band, so they are copied
        /// from DISPLAY, where the band was put first.
        fn trails(self: *Self, mode: usize, base: i32, buf: u8) void {
            const p = trl.passes[mode];
            const lo = base + p.src_lo;
            self.gpu.copy(DISPLAY, 0, @intCast(lo), buf, 0, @intCast(lo), W, @intCast(p.src_hi - p.src_lo + 1));
            for (p.rows) |t| {
                const sy = base + t.src;
                const c = clip(base + t.dst, if (t.double) 2 else t.h) orelse continue;
                if (t.double and c.h == 2) {
                    self.gpu.copyDouble(buf, 0, @intCast(c.y), DISPLAY, 0, @intCast(sy), W);
                } else {
                    const y = if (t.double) sy else sy + c.skip;
                    self.gpu.copy(buf, 0, @intCast(c.y), DISPLAY, 0, @intCast(y), W, @intCast(c.h));
                }
            }
        }

        /// Engine 4's wedge, after its trails (the two touch the same rows).
        fn wedge(self: *Self, buf: u8) void {
            for (trl.wedge.fills) |f| self.gpu.fill(buf, f.x, f.y, f.w, f.h, 0);
            for (trl.wedge.masks) |m| self.gpu.andMask(buf, m.x, m.y, m.w, m.keep);
        }
    };
}

/// The on-screen part of rows y0 .. y0+h-1: first row, height, rows cut on top.
const Clip = struct { y: i32, h: i32, skip: i32 };
fn clip(y0: i32, h: i32) ?Clip {
    const lo = @max(y0, 0);
    const hi = @min(y0 + h, H);
    if (lo >= hi) return null;
    return .{ .y = lo, .h = hi - lo, .skip = lo - y0 };
}
