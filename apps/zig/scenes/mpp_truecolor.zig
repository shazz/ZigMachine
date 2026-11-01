// --------------------------------------------------------------------------
// MPP TRUECOLOR: more than 256 colours per plane, the STE "Multi Palette
// Picture" way (https://codeberg.org/zerkman/mpp): reload the palette between
// scanlines. A plane's HBL handler runs once before each line is composited, so
// every line can take a whole new palette. A gallery of truecolor pictures, three modes:
//
//   key 1  GLOBAL    one 256-colour palette for the whole picture, 1 plane
//   key 2  PER-LINE  1 plane, a best 256-colour palette for EACH of the lines
//   key 3  4 PLANES  each pixel opaque in exactly one plane; every plane has its
//                    own per-line palette (255 + transparent) = 1020 per line
//   Space            the next picture (wraps)
//
// The pictures, chosen for smooth gradients that band at 256 colours:
//   SPHERES  procedural (tools/mpp_picture.py)
//   PARROT   "Parrot.red.macaw.1.arp.750pix.jpg", Adrian Pingstone, public domain
//   SUNSET   "Sunset over ocean (27717086074).jpg", Lisa Ann Yount, CC0
//   HALO     procedural, a dusk sky and a low sun (tools/mpp_gradients.py)
//   HILLS    procedural, ridges fading into fog
// (both photos from Wikimedia Commons; tools/mpp_convert.py has crops and URLs).
//
// The modes cycle every CYCLE_FRAMES, then the next picture starts at mode 1. The
// caption band names the mode, the picture and the colours the converter counted.
//
// Each picture and mode is a ZX0-packed blob (build.zig: packed_assets.mpp_truecolor).
// Unpacked they overflow the 2 MB cart window, so the one on screen is depacked into
// one working buffer per switch (mpp_truecolor/blob.zig). On a 1.9.0 machine the per-line palettes
// are copper lists the machine applies (mpp_truecolor/cop.zig): no CPU store a frame; else the HBL
// handler loads them, storing only the records that change. The next switch is built a slice a
// frame while the current picture shows (mpp_truecolor/stage.zig) and lands on the frame it
// always did: that frame only flips the plane buffers (flip.zig) and rewrites the lists.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blob = @import("mpp_truecolor/blob.zig");
const cop = @import("mpp_truecolor/cop.zig");
const flip = @import("mpp_truecolor/flip.zig");
const gallery = @import("mpp_truecolor/gallery.zig");
const stage = @import("mpp_truecolor/stage.zig");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;

const W = blob.W;
const H = blob.H;
const PLANES = blob.PLANES;
const CYCLE_FRAMES: u32 = 8 * 60;
const IMAGE_H: i16 = stage.IMAGE_H;
const INK = stage.INK;
const FIRE: u8 = 5; // demo_main Direction.Fire: the host sends it for Space (and Enter)

const MODES = gallery.MODES;
const NAMES = gallery.NAMES;

// HBL handlers take no user pointer: the depacked view lives at module scope (empty: nothing loaded).
var view: blob.View = .{ .map = &.{}, .idx = &.{}, .pal = &.{} };

// The record last loaded into each plane's palette: the same record again (GLOBAL mode: all
// 180 lines) needs no copy at all. A switch forgets them, as it rewrites entries itself.
const NONE = blob.Rec{ .off = std.math.maxInt(u32), .span = 0 };
var loaded: [PLANES]blob.Rec = .{NONE} ** PLANES;
// The machine applies the palettes from copper lists (cop.install succeeded): no handler.
var lists = false;

// Load this line's palette run for this plane: a straight word copy. A new record changes
// ~all of its entries (PER-LINE and 4 PLANES: 0 of 52,660 stores a frame rewrote a colour),
// so comparing first would only add a load per entry; the repeated record is skipped whole.
fn hbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    if (line >= H or view.map.len == 0) return;
    const p: usize = fb.id;
    const r = view.map[p * H + line];
    const n: usize = r.span >> 16;
    if (n == 0) return;
    if (loaded[p].off == r.off and loaded[p].span == r.span) return;
    loaded[p] = r;
    const first: usize = r.span & 0xffff;
    @memcpy(fb.palette[first..][0..n], view.pal[r.off / 4 ..][0..n]);
}

pub const Demo = struct {
    os: *ZigOS,
    picture: u8,
    mode: u8,
    frames: u32,
    work: []align(4) u8,
    // The next switch in the making, a slice a frame (null: none, or it runs on its frame).
    job: ?stage.Job,
    spread: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.* = .{ .os = zigos, .picture = 0, .mode = 0, .frames = 0, .work = &.{}, .job = null, .spread = false };
        zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        for (&zigos.lfbs) |*fb| fb.setFrameBufferHBLHandler(0, hbl);
        // On zg.mem, taken once at the largest blob's size: every switch reuses it.
        // u32 words, so the map and palette views blob.load takes are aligned.
        const len = gallery.workLen() orelse return self.fail("a packed picture is unreadable");
        const words = zg.mem.alloc(u32, (len + 3) / 4) orelse return self.fail("no free RAM to depack into");
        self.work = std.mem.sliceAsBytes(words);
        lists = cop.install(zigos, gallery.mostColours() orelse return self.fail("a packed picture is unreadable"));
        // Spreading needs lists (the HBL handler would read the buffer being depacked into),
        // a spare table and spare pixel buffers; else each switch runs whole on its frame.
        self.spread = lists and cop.spread() and flip.install();
        self.switchTo(0, 0);
    }

    pub fn setShadeMode(self: *Demo, m: u32) void {
        if (m >= MODES.len) return;
        self.switchTo(self.picture, @intCast(m));
    }

    // Space arrives as Fire. Taking input() rather than key() keeps Escape and
    // Back returning to the menu (demo_main.zig).
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == FIRE) self.switchTo(nextPicture(self.picture), self.mode);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.frames += 1;
        if (self.frames < CYCLE_FRAMES) {
            if (self.job) |*j| _ = j.step(self.os, 1, lists);
            return;
        }
        // After the last mode, the next picture from mode 1.
        if (self.mode + 1 < MODES.len) return self.switchTo(self.picture, self.mode + 1);
        self.switchTo(nextPicture(self.picture), 0);
    }

    // Everything is drawn once per switch; the lists (or HBLs) do the per-frame work.
    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
    }

    fn nextPicture(p: u8) u8 {
        return @intCast((p + 1) % NAMES.len);
    }

    // Show `picture` in `mode` this frame: the job built ahead when it is that one (finished
    // here if it is not done yet), else a job run whole (a key). Then start the next one.
    fn switchTo(self: *Demo, picture: u8, mode: u8) void {
        if (self.work.len == 0) return; // init failed and said why
        self.frames = 0;
        var job = self.job orelse stage.Job.init(picture, mode, self.work);
        self.job = null;
        if (job) |j| if (j.picture != picture or j.mode != mode) {
            job = stage.Job.init(picture, mode, self.work);
        };
        const j = &(job orelse return self.fail("depack failed"));
        if (j.finish(self.os, lists) != .done) return self.fail("depack failed");
        self.show(j);
        if (!self.spread) return;
        const next_mode: u8 = if (mode + 1 < MODES.len) mode + 1 else 0;
        self.job = stage.Job.init(if (next_mode == 0) nextPicture(picture) else picture, next_mode, self.work);
    }

    // The switch frame: planes, bases, lists. The pixels and the table are already in place.
    fn show(self: *Demo, job: *const stage.Job) void {
        self.picture = job.picture;
        self.mode = job.mode;
        view = job.view();
        loaded = .{NONE} ** PLANES;
        const lfbs = &self.os.lfbs;
        for (lfbs, 0..) |*fb, p| {
            fb.is_enabled = p < job.planes();
            fb.setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
        }
        lfbs[0].setPaletteEntry(INK, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
        flip.show(self.os);
        if (lists) cop.commit(self.os, view, job.planes());
    }

    // Say so on screen and in the console, with nothing half-loaded behind it.
    fn fail(self: *Demo, why: []const u8) void {
        zg.Console.log("mpp_truecolor: {s}", .{why});
        self.job = null;
        view = .{ .map = &.{}, .idx = &.{}, .pal = &.{} };
        if (lists) cop.load(self.os, view, 0); // empty lists: no stale palette over the message
        const lfbs = &self.os.lfbs;
        for (lfbs, 0..) |*fb, p| fb.is_enabled = p == 0;
        @memset(lfbs[0].fb[0 .. W * H], 0);
        lfbs[0].setPaletteEntry(0, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
        lfbs[0].setPaletteEntry(INK, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
        self.os.printText(&lfbs[0], "MPP TRUECOLOR: DEPACK FAILED", 4, IMAGE_H + 2, INK, 0);
    }
};
