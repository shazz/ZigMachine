// --------------------------------------------------------------------------
// AURORA BOOT (cart 161): the KESTREL boot screen glass plays at power-on (fpga/glass/src/app_splash.zig).
// Concept and numbers: docs/boot/AURORA_BOOT.md.
//
// A night sky (a real photo), a curtain of aurora light fades in, moves and fades away while every star flies
// along a curved path to become a dot on the wireframe of a falcon; its lines fade in, the name lights, hold,
// fade to black. Everything was computed OFFLINE by tools/boot/aurora_bake.py: this cart is a player.
//
//   plane 0  RGB565 true colour, 320x200: the photo with its stars painted out; the aurora is the final 565
//            picture's 16-bit deltas, added in place from change masks + nibble codes (masked.zig); the final
//            fade is TC_FADE
//   plane 1  8-bit, on top (the TC plane has no colour key): stars, flight, wire, name, baked per 60 Hz frame,
//            only the changed bytes written (overlay.zig); the wire and name fade in by palette alpha (colours.zig)
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
const colours = @import("aurora_boot/colours.zig");
const Masked = @import("aurora_boot/masked.zig").Masked;
const Overlay = @import("aurora_boot/overlay.zig").Overlay;
const meta = art.meta;
const ZigOS = zg.ZigOS;

const K_ESC: u32 = 0xE012;
const PLANE: usize = 320 * 200;
const W: u32 = 320;

pub const Demo = struct {
    f: u32 = 0,
    os: *ZigOS = undefined,
    ok: bool = false, // init found the RAM it needs and the sky depacked
    wants_quit: bool = false, // demo_main's pollCartRequest: the picture is black, glass takes over
    masked: Masked = undefined,
    overlay: Overlay = undefined,
    colours: colours.Colours = .{}, // plane 1's palette, rewritten only when a level or the fade changes

    pub fn init(self: *Demo, os: *ZigOS) void {
        self.* = .{ .os = os };
        const back = &os.lfbs[0];
        back.is_enabled = true;
        const tc = back.setTruecolorPlane(.window);
        os.lfbs[1].is_enabled = true;
        self.ok = self.load(tc);
    }

    /// No run-time buffers: the masks are read in place, the sky unpacked straight into the plane (again on a replay).
    fn load(self: *Demo, tc: zg.tc.Fb) bool {
        if (tc.stride != W or !skyToPlane(tc.pixels)) return false;
        @memset(self.os.lfbs[1].fb[0..PLANE], 0); // the baked lists start from an empty plane
        self.masked = .{ .plane = tc.pixels, .y0 = meta.BAND_Y0, .rows = meta.BAND_ROWS, .deltas = &meta.DELTAS };
        self.overlay = .{ .data = art.overlay };
        return true;
    }

    fn skyToPlane(px: [*]u16) bool {
        return zx0.depack(art.sky, std.mem.sliceAsBytes(px[0..PLANE])) != null;
    }

    /// Replay from the first frame: the sky back, the star plane emptied, the sound restarted.
    fn restart(self: *Demo, os: *ZigOS) void {
        if (!self.ok) return;
        if (!skyToPlane(self.masked.plane)) return self.fail();
        self.overlay.restart();
        @memset(os.lfbs[1].fb[0..PLANE], 0);
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
        if (!self.overlay.play(os.lfbs[1].fb, self.f)) self.fail();
        const lv = meta.SCALARS[rec]; // wire level, name level, fade
        self.colours.apply(&os.lfbs[1], lv[0], lv[1], @intCast(lv[2]));
        os.lfbs[0].setTruecolorFade(@intCast(lv[2]), .black);
        if (self.f >= tl.lastFrame(meta.STAR_FRAMES)) self.wants_quit = true else self.f += 1;
    }

    /// The aurora's frame for this record, over its two 60 Hz frames: the even one adds the frame's first container
    /// (2j), the odd one the second (2j + 1); the baker splits each frame where both carry about as many changed pixels.
    fn aurora(self: *Demo, rec: u32) void {
        const j = tl.auroraFrame(rec, meta.AURORA_AT, meta.AURORA_FRAMES) orelse return;
        const k = 2 * j + @intFromBool(self.f & 1 == 1);
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
