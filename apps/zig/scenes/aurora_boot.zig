// --------------------------------------------------------------------------
// AURORA BOOT (cart 161): the new KESTREL boot screen, a spike. Concept and numbers: docs/boot/AURORA_BOOT.md.
//
// A night sky (a real photo), a curtain of aurora light fades in, moves and fades away while every star flies
// along a curved path to become a dot on the wireframe of a falcon; its lines fade in, the name lights, hold,
// fade to black. Everything was computed OFFLINE by tools/boot/aurora_bake.py: this cart is a player.
//
//   plane 0  RGB565 true colour, 320x200: the photo with its stars painted out; the aurora is added in place
//            from palette-indexed, delta-coded, ZX0-packed frames (blend.zig); the final fade is TC_FADE
//   plane 1  8-bit, on top (the TC plane has no colour key): the stars, their flight, the falcon's wire and
//            the wordmark, replayed from the baked records (stars.zig, plot.zig, look.zig)
//   sound    "Northern Lights soft" (CC0), signed 8-bit mono, handed whole to zg.samplePlay at frame 0
//   end      at the last record the picture is black: the cart asks to leave (pollCartRequest -1)
//   keys     Space / R replay, Esc leaves; K / P would pick the falcon (KESTREL only is baked: a hook)
//
// Integer-only per frame; frames are counted, dt is ignored (timeline.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const zx0 = @import("depackers").zx0;
const art = @import("aurora_art");
const tl = @import("aurora_boot/timeline.zig");
const blend = @import("aurora_boot/blend.zig");
const look = @import("aurora_boot/look.zig");
const stars = @import("aurora_boot/stars.zig");
const meta = art.meta;
const ZigOS = zg.ZigOS;

const K_ESC: u32 = 0xE012;
const PLANE: usize = 320 * 200;

pub const Demo = struct {
    f: u32 = 0,
    os: *ZigOS = undefined,
    ok: bool = false, // init found the RAM it needs and every depack succeeded
    wants_quit: bool = false, // demo_main's pollCartRequest: the picture is black, glass takes over
    layer: blend.Layer = undefined,
    delta: []u32 = &.{}, // one aurora frame's deltas (BAND_ROWS x 320 bytes)
    stream: zx0.Stream = undefined, // the aurora frame being unpacked (resumes on the odd 60 Hz frame)
    next_row: u32 = 0, // the first stored row not yet added
    player: stars.Player = undefined,
    drawn: [look.WORD + 1]u8 = [_]u8{255} ** (look.WORD + 1), // the last level written per ramp entry
    coef: u8 = 255, // the fade last applied to the palette

    pub fn init(self: *Demo, os: *ZigOS) void {
        self.* = .{ .os = os };
        const back = &os.lfbs[0];
        back.is_enabled = true;
        const tc = back.setTruecolorPlane(.window);
        os.lfbs[1].is_enabled = true;
        self.ok = self.load(tc);
    }

    fn load(self: *Demo, tc: zg.tc.Fb) bool {
        const sky = zg.mem.alloc(u16, PLANE) orelse return false;
        const state = zg.mem.alloc(u8, meta.BAND_ROWS * blend.W) orelse return false;
        const deltas = zg.mem.alloc(i16, meta.STAR_FRAMES * meta.REC) orelse return false;
        self.delta = zg.mem.alloc(u32, meta.BAND_ROWS * blend.W / 4) orelse return false;
        if (zx0.depack(art.sky, std.mem.sliceAsBytes(sky)) == null) return false;
        if (zx0.depack(art.stars, std.mem.sliceAsBytes(deltas)) == null) return false;
        @memcpy(tc.pixels[0..PLANE], sky);
        self.layer = .{ .sky = sky.ptr, .plane = tc.pixels, .stride = tc.stride, .pal = &meta.PALETTE, .state = state, .y0 = meta.BAND_Y0, .step = meta.ROW_STEP, .rows = meta.BAND_ROWS };
        self.player = .{ .deltas = deltas };
        return true;
    }

    /// Replay from the first frame: the sky back, the records and the sound restarted.
    fn restart(self: *Demo, os: *ZigOS) void {
        if (!self.ok) return;
        self.layer.reset();
        self.player.restart();
        self.f = 0;
        self.coef = 255;
        self.drawn = [_]u8{255} ** (look.WORD + 1);
        os.lfbs[0].setTruecolorFade(0, .black);
        _ = zg.sampleStop();
    }

    pub fn update(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        if (self.f == 0) _ = zg.samplePlay(art.pcm, meta.SAMPLE_RATE, false); // the sound starts with the picture
    }

    pub fn render(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = dt;
        if (!self.ok) return;
        const s = tl.step(self.f);
        self.player.seek(@min(s.rec, meta.STAR_FRAMES - 1));
        self.aurora(s.rec);
        const plane = os.lfbs[1].fb;
        @memset(plane[0..PLANE], 0);
        self.player.draw(plane, s.odd and s.rec + 1 < meta.STAR_FRAMES);
        if (self.player.scalar(1) > 0) look.drawWord(plane);
        self.palette(&os.lfbs[1]);
        os.lfbs[0].setTruecolorFade(@intCast(self.player.scalar(2)), .black);
        if (self.f >= tl.lastFrame(meta.STAR_FRAMES)) self.wants_quit = true else self.f += 1;
    }

    /// The aurora's frame for this record, over its two 60 Hz frames: unpack and add the first half of its rows on
    /// the even one, the rest on the odd one (zx0.Stream resumes where it stopped).
    fn aurora(self: *Demo, rec: u32) void {
        const j = tl.auroraFrame(rec, meta.AURORA_AT, meta.AURORA_FRAMES) orelse return;
        const even = self.f & 1 == 0;
        if (even) {
            const o = std.mem.readInt(u32, art.aurora_idx[4 * j ..][0..4], .little);
            const e = std.mem.readInt(u32, art.aurora_idx[4 * j + 4 ..][0..4], .little);
            self.stream = zx0.Stream.init(art.aurora[o..e], std.mem.sliceAsBytes(self.delta)) orelse return self.fail();
            self.next_row = 0;
        }
        const mid = tl.splitRow(meta.BAND_ROWS);
        _ = self.stream.step(if (even) mid * blend.W else std.math.maxInt(u32));
        const ready: u32 = if (even) self.stream.written() / blend.W else meta.BAND_ROWS;
        self.layer.apply(std.mem.sliceAsBytes(self.delta), self.next_row, ready);
        self.next_row = ready;
    }

    fn fail(self: *Demo) void {
        self.ok = false;
    }

    /// Plane 1's colours: the star ramp, the wire and the name by their levels, all through the fade.
    fn palette(self: *Demo, fb: *zg.LogicalFB) void {
        const c: u5 = @intCast(self.player.scalar(2));
        const redo = c != self.coef;
        self.coef = c;
        for (1..look.LEVELS + 1) |lv| self.set(fb, @intCast(lv), look.star(@intCast(lv)), lv, c, redo);
        self.set(fb, look.LINE, look.wire(self.player.scalar(0)), self.player.scalar(0), c, redo);
        self.set(fb, look.WORD, look.ink(self.player.scalar(1)), self.player.scalar(1), c, redo);
    }

    fn set(self: *Demo, fb: *zg.LogicalFB, e: u8, rgb: look.Rgb, level: usize, c: u5, redo: bool) void {
        if (!redo and self.drawn[e] == level) return;
        self.drawn[e] = @intCast(level);
        const col = zg.Color{ .r = look.fadeChannel(rgb.r, c), .g = look.fadeChannel(rgb.g, c), .b = look.fadeChannel(rgb.b, c), .a = 255 };
        fb.palette[e] = col.toRGBA();
    }

    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            K_ESC => self.wants_quit = true,
            ' ', 'r', 'R' => self.restart(self.os),
            else => {}, // K / P: the other falcon is not baked (docs/boot/AURORA_BOOT.md)
        }
    }

    /// Frames since the cart started (the harness and glass's hand-off read it).
    pub fn frameCount(self: *const Demo) u32 {
        return self.f;
    }
};
