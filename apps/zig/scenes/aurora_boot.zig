// --------------------------------------------------------------------------
// AURORA BOOT (cart 161): the KESTREL boot screen glass plays at power-on (fpga/glass/src/app_splash.zig).
// Concept and numbers: docs/boot/AURORA_BOOT.md. The picture covers the WHOLE 400x280 raster, borders included
// (Matt, 27 Nov: "aurora h is perfect! make it the kestrel boot"; until then 161 was G2, 320x200).
//
// A night sky (a real photo), a curtain of aurora light fades in, moves and fades away while every star flies
// along a curved path to become a dot on the wireframe of a falcon; its lines fade in, the name lights, hold,
// fade to black. Everything was computed OFFLINE by tools/boot/aurora_bake.py: this cart is a player.
//
//   plane 0  RGB565 true colour FULL (FB_MODE 6): 400x280 from x 0, the borders open with nothing to earn; the
//            photo with its stars painted out, the aurora's 16-bit deltas added from change masks (masked.zig)
//            read off the disk a frame at a time (stream.zig: the masks outgrow the cart's RAM at this size)
//   plane 1  8-bit OVERSCAN, 400x280: its borders ARE earned, by a FLICK on every line of a copper list written
//            once (no HBL handler, no per-frame cost); the baked star plane in two 64 K sections (overlay.zig);
//            the wire and name fade in by palette alpha (colours.zig)
//   sound    "Northern Lights soft" (CC0), signed 8-bit mono, handed whole to zg.samplePlay at frame 0
//   end      at the last record the picture is black: the cart asks to leave (pollCartRequest -1)
//   keys     Space / R replay, Esc leaves; K / P would pick the falcon (KESTREL only is baked: a hook)
// Integer-only per frame; frames are counted, dt is ignored (aurora_boot/timeline.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const zx0 = @import("depackers").zx0;
const art = @import("aurora_art");
const tl = @import("aurora_boot/timeline.zig");
const colours = @import("aurora_boot/colours.zig");
const MaskedW = @import("aurora_boot/masked.zig").MaskedW;
const OverlayFor = @import("aurora_boot/overlay.zig").OverlayFor;
const stream = @import("aurora_boot/stream.zig");
const meta = art.meta;
const ZigOS = zg.ZigOS;

const K_ESC: u32 = 0xE012;
const W: u32 = 400;
const H: u32 = 280;
const PLANE: usize = W * H;
const Masked = MaskedW(W);
const Overlay = OverlayFor(PLANE);
const FILE = "AURORA.MSK";

fn readBlock(b: u32, dst: []u8) i32 {
    return zg.readBlock(b, dst);
}

pub const Demo = struct {
    f: u32 = 0,
    os: *ZigOS = undefined,
    ok: bool = false, // init found the disk file, the RAM and VRAM it needs, and the sky depacked
    wants_quit: bool = false, // demo_main's pollCartRequest: the picture is black, glass takes over
    masked: Masked = undefined,
    overlay: Overlay = undefined,
    disk: stream.Stream = undefined,
    colours: colours.Colours = .{},

    pub fn init(self: *Demo, os: *ZigOS) void {
        self.* = .{ .os = os };
        const back = &os.lfbs[0];
        back.is_enabled = true;
        const tc = back.setTruecolorPlane(.full);
        const front = &os.lfbs[1];
        front.is_enabled = true;
        self.ok = openBorders(front) and self.load(tc);
    }

    /// Plane 1 overscan, its borders opened by a FLICK on each of the 280 lines: a copper list written once
    /// (replicants_emlyn/rasters.zig's way). The plane's HBL position stays the magic column openBorders set.
    fn openBorders(fb: *zg.LogicalFB) bool {
        fb.openBorders(.all);
        fb.clearFrameBufferHBLHandler();
        const l = fb.copperList(2 * H + 1) orelse return false;
        for (0..H) |y| {
            l[2 * y] = 0xF000_0000 | @as(u32, @intCast(y)) << 19 | 1; // HEAD: line y, one body word
            l[2 * y + 1] = 0x3000_0000; // FLICK
        }
        l[2 * H] = 0xF000_0000 | 511 << 19; // the end
        return true;
    }

    fn load(self: *Demo, tc: zg.tc.Fb) bool {
        if (tc.stride != W or tc.h != H or !skyToPlane(tc.pixels)) return false;
        const lay = zg.disk.mount() orelse return false;
        const file = zg.disk.find(lay, FILE) orelse return false;
        const big = stream.largest(art.aurora_idx) orelse return false;
        const end = std.mem.readInt(u32, art.aurora_idx[art.aurora_idx.len - 4 ..][0..4], .little);
        if (file.len != end) return false; // the disk's masks are not this cart's
        const buf = zg.mem.alloc(u8, stream.blocksFor(big)) orelse return false;
        self.disk = .{ .start = file.start, .len = file.len, .buf = buf, .read_block = readBlock };
        @memset(self.os.lfbs[1].fb[0..PLANE], 0);
        self.masked = .{ .plane = tc.pixels, .y0 = meta.BAND_Y0, .rows = meta.BAND_ROWS, .deltas = &meta.DELTAS };
        self.overlay = .{ .data = art.overlay };
        return true;
    }

    fn skyToPlane(px: [*]u16) bool {
        return zx0.depack(art.sky, std.mem.sliceAsBytes(px[0..PLANE])) != null;
    }

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
        if (self.f == 0) _ = zg.samplePlay(art.pcm, meta.SAMPLE_RATE, false);
    }

    pub fn render(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = dt;
        if (!self.ok) return;
        const s = tl.step(self.f);
        const rec = @min(s.rec, meta.STAR_FRAMES - 1);
        self.aurora(s.rec);
        if (!self.ok) return;
        if (!self.overlay.play(os.lfbs[1].fb, self.f)) self.fail();
        const lv = meta.SCALARS[rec];
        self.colours.apply(&os.lfbs[1], lv[0], lv[1], @intCast(lv[2]));
        os.lfbs[0].setTruecolorFade(@intCast(lv[2]), .black);
        if (self.f >= tl.lastFrame(meta.STAR_FRAMES)) self.wants_quit = true else self.f += 1;
    }

    /// The aurora's frame for this record, over its two 60 Hz frames: the even one adds the frame's first container
    /// (2j), the odd one the second (2j + 1), each read off the disk first; the baker splits each frame where both
    /// carry about as many changed pixels.
    fn aurora(self: *Demo, rec: u32) void {
        const j = tl.auroraFrame(rec, meta.AURORA_AT, meta.AURORA_FRAMES) orelse return;
        const k = 2 * j + @intFromBool(self.f & 1 == 1);
        const o = std.mem.readInt(u32, art.aurora_idx[4 * k ..][0..4], .little);
        const e = std.mem.readInt(u32, art.aurora_idx[4 * k + 4 ..][0..4], .little);
        const c = self.disk.read(o, e) orelse return self.fail();
        if (!self.masked.apply(c)) self.fail();
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
