// --------------------------------------------------------------------------
// AURORA BOOT (cart 161): the new KESTREL boot screen, a spike. Concept and numbers: docs/boot/AURORA_BOOT.md.
//
// A night sky (a real photo), a curtain of aurora light fades in, moves and fades away while every star flies
// along a curved path to become a dot on the wireframe of a falcon; its lines fade in, the name lights, hold,
// fade to black. Everything was computed OFFLINE by tools/boot/aurora_bake.py: this cart is a player.
//
//   plane 0  RGB565 true colour, 320x200: the photo with its stars painted out; the aurora is added in place
//            from palette-indexed, delta-coded, ZX0-packed frames (blend.zig); the final fade is TC_FADE.
//            F: a palette per row; G: no palette, 16-bit deltas of the final 565 picture as change masks (masked.zig)
//   plane 1  8-bit, on top (the TC plane has no colour key): stars, flight, wire, name, drawn from the baked
//            records (stars.zig, plot.zig, look.zig); G: baked per 60 Hz frame, only changed bytes written (overlay.zig)
//   sound    "Northern Lights soft" (CC0), signed 8-bit mono, handed whole to zg.samplePlay at frame 0
//   end      at the last record the picture is black: the cart asks to leave (pollCartRequest -1)
//   keys     Space / R replay, Esc leaves; K / P would pick the falcon (KESTREL only is baked: a hook)
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
const colours = @import("aurora_boot/colours.zig");
const Masked = @import("aurora_boot/masked.zig").Masked;
const Overlay = @import("aurora_boot/overlay.zig").Overlay;
const meta = art.meta;
// Variants F / G (docs/boot/AURORA_BOOT.md) declare these; A..E have neither: one shared palette, the name drawn.
const PAL_MODE: u32 = if (@hasDecl(meta, "PAL_MODE")) meta.PAL_MODE else 0; // 0 shared, 1 per row, 2 16-bit masks (G)
const WORDMARK: u32 = if (@hasDecl(meta, "WORDMARK")) meta.WORDMARK else 1; // 1 bitmap capitals (A..E), 2 the baked script image
const BAKED = @hasDecl(meta, "OVERLAY"); // G: the star plane baked per 60 Hz frame (no records, no drawing)
const ZigOS = zg.ZigOS;

const K_ESC: u32 = 0xE012;
const PLANE: usize = 320 * 200;

pub const Demo = struct {
    f: u32 = 0,
    os: *ZigOS = undefined,
    ok: bool = false, // init found the RAM it needs and every depack succeeded
    wants_quit: bool = false, // demo_main's pollCartRequest: the picture is black, glass takes over
    layer: blend.Layer = undefined,
    masked: Masked = undefined, // G
    overlay: Overlay = undefined, // G
    delta: []u32 = &.{}, // one aurora frame's deltas (BAND_ROWS x 320 bytes)
    stream: zx0.Stream = undefined, // the aurora frame being unpacked (resumes on the odd 60 Hz frame)
    next_row: u32 = 0, // the first stored row not yet added
    player: stars.Player = undefined,
    colours: colours.Colours = .{}, // plane 1's palette, rewritten only when a level or the fade changes

    pub fn init(self: *Demo, os: *ZigOS) void {
        self.* = .{ .os = os };
        const back = &os.lfbs[0];
        back.is_enabled = true;
        const tc = back.setTruecolorPlane(.window);
        os.lfbs[1].is_enabled = true;
        self.ok = self.load(tc);
    }

    fn load(self: *Demo, tc: zg.tc.Fb) bool {
        return if (BAKED) self.loadBaked(tc) else self.loadRecords(tc);
    }

    /// G: no records, no delta buffer (the masks are read in place); the sky unpacked into the plane (again on a replay).
    fn loadBaked(self: *Demo, tc: zg.tc.Fb) bool {
        if (tc.stride != blend.W or !skyToPlane(tc.pixels)) return false;
        @memset(self.os.lfbs[1].fb[0..PLANE], 0); // the baked lists start from an empty plane
        self.masked = .{ .plane = tc.pixels, .y0 = meta.BAND_Y0, .rows = meta.BAND_ROWS, .deltas = &meta.DELTAS };
        self.overlay = .{ .data = art.overlay };
        return true;
    }

    fn loadRecords(self: *Demo, tc: zg.tc.Fb) bool {
        const deltas = zg.mem.alloc(i16, meta.STAR_FRAMES * meta.REC) orelse return false;
        if (zx0.depack(art.stars, std.mem.sliceAsBytes(deltas)) == null) return false;
        self.player = .{ .deltas = deltas };
        const sky = zg.mem.alloc(u16, PLANE) orelse return false;
        self.delta = zg.mem.alloc(u32, meta.BAND_ROWS * blend.W / 4) orelse return false;
        if (zx0.depack(art.sky, std.mem.sliceAsBytes(sky)) == null) return false;
        @memcpy(tc.pixels[0..PLANE], sky);
        const state = zg.mem.alloc(u8, meta.BAND_ROWS * blend.W) orelse return false;
        const pal = rowPalette() orelse return false;
        self.layer = .{ .sky = sky.ptr, .plane = tc.pixels, .stride = tc.stride, .pal = pal.ptr, .pal_stride = if (PAL_MODE == 1) 256 else 0, .state = state, .y0 = meta.BAND_Y0, .step = meta.ROW_STEP, .rows = meta.BAND_ROWS };
        return true;
    }

    fn skyToPlane(px: [*]u16) bool {
        return zx0.depack(art.sky, std.mem.sliceAsBytes(px[0..PLANE])) != null;
    }

    /// The palette the layer reads: the shared one, or (F) the per-row tables copied to aligned RAM (an embedded
    /// file is byte-aligned, and a misaligned u16 load traps on the board).
    fn rowPalette() ?[]const u16 {
        if (PAL_MODE != 1) return &meta.PALETTE;
        const t = zg.mem.alloc(u16, meta.BAND_ROWS * 256) orelse return null;
        @memcpy(std.mem.sliceAsBytes(t), art.palette[0 .. meta.BAND_ROWS * 512]);
        return t;
    }

    /// Replay from the first frame: the sky back, the records and the sound restarted.
    fn restart(self: *Demo, os: *ZigOS) void {
        if (!self.ok) return;
        if (BAKED) {
            if (!skyToPlane(self.masked.plane)) return self.fail();
            self.overlay.restart();
            @memset(os.lfbs[1].fb[0..PLANE], 0);
        } else {
            self.layer.reset();
            self.player.restart();
        }
        self.f = 0;
        self.colours = .{};
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
        const rec = @min(s.rec, meta.STAR_FRAMES - 1);
        self.aurora(s.rec);
        if (!self.ok) return;
        const lv = if (BAKED) self.playBaked(os.lfbs[1].fb, rec) else self.drawRecords(os.lfbs[1].fb, rec, s.odd);
        self.colours.apply(&os.lfbs[1], lv[0], lv[1], @intCast(lv[2]), WORDMARK == 2);
        os.lfbs[0].setTruecolorFade(@intCast(lv[2]), .black);
        if (self.f >= tl.lastFrame(meta.STAR_FRAMES)) self.wants_quit = true else self.f += 1;
    }

    /// G: write this frame's baked star-plane bytes; the levels (wire, name, fade) come from the baked table.
    fn playBaked(self: *Demo, plane: [*]u8, rec: u32) [3]u32 {
        if (!self.overlay.play(plane, self.f)) self.fail();
        const v = meta.SCALARS[rec];
        return .{ v[0], v[1], v[2] };
    }

    /// A..F: clear the star plane and draw the record (stars, glints, wire, name); the levels from the record.
    fn drawRecords(self: *Demo, plane: [*]u8, rec: u32, odd: bool) [3]u32 {
        self.player.seek(rec);
        @memset(plane[0..PLANE], 0);
        self.player.draw(plane, odd and rec + 1 < meta.STAR_FRAMES);
        if (self.player.scalar(1) > 0) {
            if (WORDMARK == 2) look.drawImage(plane, art.word) else if (WORDMARK == 1) look.drawWord(plane);
        }
        return .{ self.player.scalar(0), self.player.scalar(1), self.player.scalar(2) };
    }

    /// The aurora's frame for this record, over its two 60 Hz frames: unpack and add the first half of its rows on
    /// the even one, the rest on the odd one (zx0.Stream resumes where it stopped).
    fn aurora(self: *Demo, rec: u32) void {
        const j = tl.auroraFrame(rec, meta.AURORA_AT, meta.AURORA_FRAMES) orelse return;
        const even = self.f & 1 == 0;
        if (BAKED) return self.auroraDirect(j, even);
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

    /// G: the even 60 Hz frame adds the frame's first container (2j), the odd one the second (2j + 1); the baker
    /// splits each frame where both carry about as many changed pixels.
    fn auroraDirect(self: *Demo, j: u32, even: bool) void {
        const k = 2 * j + @intFromBool(!even);
        const o = std.mem.readInt(u32, art.aurora_idx[4 * k ..][0..4], .little);
        const e = std.mem.readInt(u32, art.aurora_idx[4 * k + 4 ..][0..4], .little);
        if (o > e or e > art.aurora.len or !self.masked.apply(art.aurora[o..e])) self.fail();
    }

    fn fail(self: *Demo) void {
        self.ok = false;
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
