// --------------------------------------------------------------------------
// RACER (R82, Kestrel Racing M1): the renderer spike. An original flat-shaded track (our own
// generator, tools/racer/gen_track.py) drawn by the engine of freds72's PICO-8 racer (MIT; the
// tile/PVS/painter pipeline), in Q16 integers + ZM-X mulsh: a camera flies the racing line
// (the benchmark's lap v0), the PVS and a ray DDA pick the tiles, faces are back-face culled,
// transformed, clipped, bucket-sorted far to near and filled flat. docs/ports/kestrel_racing/.
//
//   3-8 draw distance R (tiles)   f the fill path: CPU word stores / CHISEL AFFINE spans   m mulsh / plain twin
//   g the vertex transform in f32   d decals on / off   t oval / stress city   p pause   o the benchmark OSD
//   u the cart-only rate   c the lap CRC on / off   l back to the lap   A-H a fixed pose
// M2 (oval only): n drive (arrows or joystick, fire = accelerate)   b bench lap v1 (the Lua reference's buttons)
//   v the POV (far, near, cockpit)   r / Enter the car back on the grid        (keys.zig: all of them, and X Y Z)
// M4 audio (racer/audio.zig): z the music, h the effects, j the benchmark laps' audio (silent by default); -Dracer_music: local tunes
// M3 (oval only): e the race (8 cars, 3 laps; fire or s starts the countdown, r / Enter aborts or goes again)
//   x bench lap v2 (the reference benchmark)   a the recorded driver   w warp (16 ticks a frame)   k the crest test pose
// One plane in two pages (the shown one is enabled), the sky a per-line palette entry on the copper, the
// backdrop one AFFINE op. No float. Benchmark lines go to the console: racer/bench.zig, racer/drive.zig.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const draw = @import("racer/draw.zig");
const bench = @import("racer/bench.zig");
const cam = @import("racer/cam.zig");
const clip = @import("racer/clip.zig");
const drive = @import("racer/drive.zig");
const frame = @import("racer/frame.zig");
const fx = @import("racer/fx.zig");
const game = @import("racer/game.zig");
const keys = @import("racer/keys.zig");
const audio = @import("racer/audio.zig");
const Hud = @import("racer/hud.zig").Hud;
const data = @import("racer/data.zig");
const minimap = @import("racer/minimap.zig");
const palette = @import("racer/palette.zig");
const present = @import("racer/present.zig");
const report = @import("racer/report.zig");
const setup = @import("racer/setup.zig");
const sinks = @import("racer/sinks.zig");
const trk = @import("racer/trk.zig");
const xf = @import("racer/xform.zig");

extern fn hostMicros() u32;
const BLOBS = [_][]align(4) const u8{ data.oval, data.city };
const GROUND_RAMP = [_]usize{ 1, 8 }; // the ramp the ground beyond R takes: grass, plaza

var sky_tbl: [2][1]zg.copper.Table = undefined;

fn micros() u32 {
    return hostMicros();
}
pub const Demo = struct {
    os: *zg.ZigOS = undefined,
    tracks: [2]trk.Track = undefined,
    which: usize = 0,
    f: frame.Frame = undefined,
    drive: drive.Drive = undefined,
    game: game.Game = undefined,
    map: minimap.Map = undefined,
    caches: [2]xf.Cache = undefined, // the car's and the skidmarks' vertex caches
    p: draw.Painter = undefined,
    hud: Hud = .{},
    bench: bench.Bench = .{ .now = micros },
    r: u32 = 5,
    decals: bool = true,
    osd: bool = false,
    uncapped: bool = false,
    paused: bool = false,
    pose: ?u32 = null, // a fixed pose (A-H) instead of the lap script
    script: u32 = 0, // the lap script's frame: advanced by frames, never by the clock
    back: usize = 0,
    rep: report.Reporter = .{},
    wants_quit: bool = false,
    audio: audio.Audio = .{}, // M4: music + effects on the BARD queue's FM device (racer/audio.zig; z, h, j)

    pub fn init(self: *Demo, zigos: *zg.ZigOS) void {
        self.* = .{};
        self.os = zigos;
        self.bench = .{ .now = micros };
        self.audio.now = micros;
        for (BLOBS, 0..) |b, i| self.tracks[i] = trk.parse(b) catch |e| @panic(@errorName(e));
        const nv = @max(self.tracks[0].verts.len, self.tracks[1].verts.len);
        const nf = @max(self.tracks[0].faces.len, self.tracks[1].faces.len);
        self.f = setup.frameFor(nv, nf);
        self.caches = .{ setup.carCache(), setup.skidCache() };
        self.drive = drive.Drive.init(&self.tracks[0]);
        self.drive.now = micros;
        self.game = game.Game.init(&self.tracks[0], micros) catch |e| @panic(@errorName(e));
        self.map = minimap.Map.init(&self.tracks[0]);
        self.p = .{ .os = zigos, .aff = .{ .buf = zg.mem.mustAlloc(sinks.Span, 2 * sinks.CHUNK) } };
        for (0..2) |p| {
            const fb = &zigos.lfbs[p];
            palette.install(fb, &self.tracks[0], GROUND_RAMP[0]);
            zg.copper.install(fb, &.{palette.SKY}, &sky_tbl[p], .{});
            palette.skyFill(zg.copper.visible(fb, 0));
            fb.is_enabled = p == 0;
        }
        zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        zigos.blitAsync(true);
        zg.Console.log("racer: oval {} faces, city {} faces, cart RAM free {} KB", .{ self.tracks[0].faces.len, self.tracks[1].faces.len, zg.mem.free() / 1024 });
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    pub fn key(self: *Demo, cp: u32) void {
        keys.handle(self, cp);
    }

    /// The arrows and the board's joystick (0 up, 1 down, 2 left, 3 right, 5 fire).
    pub fn input(self: *Demo, dir: u8) void {
        self.drive.press(dir, true);
        self.game.press(dir, true);
    }

    pub fn inputRelease(self: *Demo, dir: u8) void {
        self.drive.press(dir, false);
        self.game.press(dir, false);
    }

    /// Driving needs the oval (the physics fixtures and the car's grid are its).
    pub fn setDrive(self: *Demo, m: drive.Mode) void {
        if (m != .off and self.which != 0) self.setTrack(0);
        self.pose = null;
        self.game.setMode(.off);
        self.drive.setMode(m);
        self.rep = .{ .crc_on = self.rep.crc_on };
        self.bench.resetLap();
    }

    /// The race (M3), likewise on the oval; it replaces driving.
    pub fn setGame(self: *Demo, m: game.Mode) void {
        if (m != .off and self.which != 0) self.setTrack(0);
        self.pose = null;
        self.drive.setMode(.off);
        self.game.setMode(m);
        self.rep = .{ .crc_on = self.rep.crc_on };
        self.bench.resetLap();
    }

    pub fn setTrack(self: *Demo, w: usize) void {
        self.which = w;
        self.script = 0;
        self.f.seen_stamp = 0;
        @memset(self.f.seen, 0);
        for (self.f.cache.e) |*e| e.stamp = 0;
        for (0..2) |p| palette.install(&self.os.lfbs[p], &self.tracks[w], GROUND_RAMP[w]);
    }

    pub fn update(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        if (self.paused) return audio.pause(self);
        if (self.pose == null and self.drive.mode == .off and self.game.mode == .off) self.script +%= 1;
        self.drive.update();
        self.game.update();
        audio.frame(self);
    }

    pub fn render(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = dt;
        self.bench.frameStart();
        const done = self.back;
        zigos.lfbs[done].is_enabled = true;
        zigos.lfbs[done ^ 1].is_enabled = false;
        self.back = done ^ 1;
        const fb = &zigos.lfbs[self.back];
        const t = &self.tracks[self.which];
        const racing = self.game.mode != .off;
        const pose = if (self.pose) |k| cam.fixedPose(t, k) else if (racing) self.game.pose() else if (self.drive.mode != .off) self.drive.pose() else cam.lapPose(t, self.script, cam.povAt(self.script));
        clip.near = if (self.pose != null) clip.NEAR else if (racing) self.game.near() else self.drive.near();
        var v = cam.view(pose);
        if (fx.use_f32) cam.floatView(&v);
        self.p.sky(fb, &v, pose.yaw);
        self.bench.lap(.sky);
        self.f.visibility(t, &v, self.r);
        self.bench.lap(.vis);
        self.f.collect(t, &v, self.decals);
        present.addCars(self, &v);
        self.bench.lap(.collect);
        self.f.sort();
        self.bench.lap(.sort);
        const counts = self.p.fill(fb, &self.f);
        self.bench.lap(.fill);
        present.finish(self, zigos, fb, counts);
    }
};

const std = @import("std");
