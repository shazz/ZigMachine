// --------------------------------------------------------------------------
// STNICCC 2000 — the flat-shaded flight from Oxygene's Atari ST demo (2000),
// since ported to the GBA, Archimedes, BBC Micro, PICO-8 and many more.
//
// It is not a 3D engine: the demo streams 1800 pre-projected frames of 2D
// polygons, 16 colours out of the ST's 512, onto a 256x200 window. A frame may
// skip the clear and paint over the last one, which is why the plane is never
// wiped by the scene except when a frame asks. The stream decoder and the
// polygon filler are pure and natively tested (stniccc/stream.zig, polyfill.zig).
//
// Data: scene1.bin, the demo's own stream, as shipped by the HTML5 port
// (dabadab/st-niccc-2000-html5) and the Archimedes port (kieranhj/stniccc-archie,
// MIT); both copies are byte-identical (sha256 bebba91a...). Music: "STNICCC 2000++"
// by Dolby (SNDH, 50 Hz timer). Credit for the scene belongs to Oxygene.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const stream_mod = @import("stniccc/stream.zig");
const polyfill = @import("stniccc/polyfill.zig");

const ZigOS = zg.ZigOS;
const Color = zg.Color;

const PLANE: usize = 0;
const W: usize = zg.WIDTH;
const H: usize = zg.HEIGHT;
const SCENE_W: usize = 256;
const OX: usize = (W - SCENE_W) / 2; // centred on the 320-wide screen
const BORDER: u8 = 16; // outside the scene's 16 colours: stays black
const FAILED: u8 = 17; // turns the border red if the stream ever fails to decode
// The stream has no timing of its own; the original ran as fast as the ST could
// draw. One stream frame every 2 VBLs (30 fps) plays the flight in 60 seconds.
const VBL_PER_FRAME: u8 = 2;
const MUSIC = "stniccc_2000.sndh";

const scene_data = @embedFile("../assets/screens/stniccc/scene1.bin");
const ST_LEVEL = [8]u8{ 0, 36, 73, 109, 146, 182, 219, 255 }; // ST 3-bit gun -> 8 bit

comptime {
    // drawFrame copies a decoded polygon into a polyfill point list; the filler
    // silently skips anything longer than it can hold.
    if (stream_mod.MAX_POLY_VERTS > polyfill.MAX_VERTS) @compileError("polyfill.MAX_VERTS too small");
}

pub const Demo = struct {
    stream: stream_mod.Stream,
    pal: [16]u16,
    vbl: u8,
    failed: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // The Demo arrives as stale bytes on a re-entry from the menu: assign all.
        self.stream = .{ .data = scene_data };
        self.pal = [_]u16{0} ** 16;
        self.vbl = VBL_PER_FRAME - 1; // draw the first frame straight away
        self.failed = false;
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        for (0..256) |i| fb.setPaletteEntry(@intCast(i), Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        fb.setPaletteEntry(FAILED, Color{ .r = 255, .g = 0, .b = 0, .a = 255 });
        fb.clearFrameBuffer(BORDER);
        zg.requestSong(MUSIC);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = self;
        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        _ = elapsed_time;
        if (self.failed) return;
        self.vbl += 1;
        if (self.vbl < VBL_PER_FRAME) return;
        self.vbl = 0;
        const fb = &zigos.lfbs[PLANE];
        self.drawFrame(fb) catch {
            // Fail loud: a corrupt stream stops the flight and paints the border red.
            self.failed = true;
            fb.clearFrameBuffer(FAILED);
        };
    }

    fn drawFrame(self: *Demo, fb: *zg.LogicalFB) stream_mod.Error!void {
        if (self.stream.done) self.stream.rewind(); // the flight loops
        const flags = try self.stream.beginFrame(&self.pal);
        if (flags.palette) self.applyPalette(fb);
        const px = fb.fb[0 .. W * H];
        if (flags.clear) {
            for (0..H) |y| @memset(px[y * W + OX ..][0..SCENE_W], 0);
        }
        const t = polyfill.Target{ .px = px, .stride = W, .w = SCENE_W, .h = H, .ox = OX };
        var poly: stream_mod.Poly = undefined;
        var pts: [stream_mod.MAX_POLY_VERTS]polyfill.Point = undefined;
        while (try self.stream.nextPoly(&poly)) {
            for (poly.pts[0..poly.n], 0..) |p, i| pts[i] = .{ .x = p.x, .y = p.y };
            polyfill.fill(t, pts[0..poly.n], poly.color);
        }
    }

    fn applyPalette(self: *Demo, fb: *zg.LogicalFB) void {
        for (self.pal, 0..) |w, i| fb.setPaletteEntry(@intCast(i), Color{
            .r = ST_LEVEL[(w >> 8) & 7],
            .g = ST_LEVEL[(w >> 4) & 7],
            .b = ST_LEVEL[w & 7],
            .a = 255,
        });
    }
};
