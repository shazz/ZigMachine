// --------------------------------------------------------------------------
// RACER (R82, Kestrel Racing M1): the renderer spike. An original flat-shaded track (our own
// generator, tools/racer/gen_track.py) drawn by the engine of freds72's PICO-8 racer (MIT; the
// tile/PVS/painter pipeline), in Q16 integers + ZM-X mulsh: a camera flies the racing line
// (the benchmark's lap v0), the PVS and a ray DDA pick the tiles, faces are back-face culled,
// transformed, clipped, bucket-sorted far to near and filled flat. docs/ports/kestrel_racing/.
//
//   3-8 draw distance R (tiles; 8 by default, the bench laps b and x pin 5)   f the fill path: CPU word stores / CHISEL AFFINE spans   m mulsh / plain twin
//   g the vertex transform in f32   d decals on / off   t the next track (the oval, then the disk's *.KTR files and C:\RACER\'s: racer/library.zig)   p pause   o the benchmark OSD
//   u the cart-only rate   c the lap CRC on / off   l back to the lap   A-H a fixed pose   i the VR shading (M5_VR.md)
//   y the cars' shadow: REAL (one ramp level darker, the default) / the arcade's checkerboard (HUD "/DITHER"; M5.md step 3)
// M5 step 4 (racer/front.zig): boots on the TITLE; fire / Enter the select, Backspace back; a key above drops to the bench view
// M5 finish: right on the title / select = the OPTIONS (laps, shadow, shading, R, music: racer/options.zig); Enter, Backspace, fire once a press
// M2 (oval only): n drive (arrows or joystick, fire = accelerate)   b bench lap v1 (the Lua reference's buttons)
//   v the POV (far, near, cockpit)   r / Enter the car back on the grid        (keys.zig: all of them, and X Y Z)
// M4 audio (racer/audio.zig): z the music, h the effects (both on by default), j the bench laps' audio (on); -Dracer_music: local tunes
// M3 (oval only): e the race (8 cars, 3 laps; fire or s starts the countdown, r / Enter aborts or goes again)
//   x bench lap v2 (the reference benchmark)   a the recorded driver   w warp (16 ticks a frame)   k the crest test pose
// R82 32X feel (FEEL.md): T physics ARCADE / CLASSIC   M car class   L the AI pilot in the option's physics   9 the shadow headroom
//   I --break feel   Backspace leaves a running bench lap for the select
// Board batch (BATCH.md): ] / [ the next / previous car (the garage: the disk's and C:'s *.KCR, then the GT), _ the effects'
//   PSG layout; the select's fire opens the CAR SELECT; --break & (wheels still) ~ (old near camera) * (models still)
//   < (no bench HUD) > (tag class ignored) | (panorama PIXEL ignored)
// One plane in two pages (the shown one is enabled), the sky a per-line palette entry on the copper, the
// backdrop one AFFINE op. No float. Benchmark lines go to the console: racer/bench.zig, racer/drive.zig.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const draw = @import("racer/draw.zig");
const bench = @import("racer/bench.zig");
const drive = @import("racer/drive.zig");
const frame = @import("racer/frame.zig");
const game = @import("racer/game.zig");
const keys = @import("racer/keys.zig");
const audio = @import("racer/audio.zig");
const Hud = @import("racer/hud.zig").Hud;
const minimap = @import("racer/minimap.zig");
const hudpic = @import("racer/hudpic.zig");
const palette = @import("racer/palette.zig");
const present = @import("racer/present.zig");
const report = @import("racer/report.zig");
const setup = @import("racer/setup.zig");
const sinks = @import("racer/sinks.zig");
const trk = @import("racer/trk.zig");
const ts = @import("racer/trackset.zig");
const library = @import("racer/library.zig");
const xf = @import("racer/xform.zig");
const backdrop = @import("racer/backdrop.zig");
const pano = @import("racer/pano.zig");
const front = @import("racer/front.zig");
const view = @import("racer/view.zig");

extern fn hostMicros() u32;
// Draw distance (tiles). 8 by default (Matt, 24 Nov: it avoids the far-view cut; the oval holds 60 fps there on the board).
// The benchmark laps (b, x) pin 5, as every earlier CRC list and board number was taken, whatever the default is.
pub const PLAY_R: u32 = 8;
pub const BENCH_R: u32 = 5;

var sky_tbl: [2][1]zg.copper.Table = undefined;

fn micros() u32 {
    return hostMicros();
}

// keyUp: a key's release (M5 finish: the front end takes fresh presses only, racer/press.zig). demo_main forwards none,
// so the cart exports its own (joust's pattern); the browser and glass call it when a cart has it.
var g_demo: ?*Demo = null;
comptime {
    if (@import("../cart.zig").Cart == Demo) @export(&keyUpExport, .{ .name = "keyUp" });
}
fn keyUpExport(cp: u32) callconv(.c) void {
    if (g_demo) |d| front.keyUp(d, cp);
}
pub const Demo = struct {
    os: *zg.ZigOS = undefined,
    tracks: [2]trk.Track = undefined, // the built-in oval, the library buffer's track (trackset.zig)
    lib: library.Library = .{},
    which: usize = 0,
    f: frame.Frame = undefined,
    drive: drive.Drive = undefined,
    game: game.Game = undefined,
    map: minimap.Map = undefined,
    pmap: minimap.Map = undefined, // the picture HUD's bigger map (racer/hudpic.zig)
    caches: [2]xf.Cache = undefined, // the car's and the skidmarks' vertex caches
    p: draw.Painter = undefined,
    hud: Hud = .{},
    bench: bench.Bench = .{ .now = micros },
    r: u32 = PLAY_R, // the draw distance in force (the benchmark laps pin BENCH_R while they run)
    play_r: u32 = PLAY_R, // the one the player picked: what drive / race / the free view use, restored after a bench lap
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
    front: front.Front = .{}, // M5 step 4: the title, the track select, the results (racer/front.zig)
    recs: [library.MAX]@import("racer/records.zig").Records = @splat(.{}), // the session's records, a track each

    pub fn init(self: *Demo, zigos: *zg.ZigOS) void {
        self.* = .{};
        g_demo = self;
        self.os = zigos;
        self.bench = .{ .now = micros };
        self.audio.now = micros;
        @import("racer/prof.zig").now = micros;
        self.tracks[0] = library.builtin();
        self.tracks[1] = self.tracks[0]; // the buffer's view: nothing loaded yet
        self.f = setup.frameFor(library.MAX_VERTS, library.MAX_FACES);
        self.caches = .{ setup.carCache(), setup.smokeCache() };
        self.drive = drive.Drive.init(&self.tracks[0]);
        self.drive.now = micros;
        self.game = game.Game.init(&self.tracks[0], micros) catch |e| @panic(@errorName(e));
        self.map = minimap.Map.init(&self.tracks[0]);
        self.pmap = hudpic.fitMap(&self.tracks[0]);
        self.p = .{ .os = zigos, .aff = .{ .buf = zg.mem.mustAlloc(sinks.Span, 2 * sinks.CHUNK), .os = zigos } };
        for (0..2) |p| {
            const fb = &zigos.lfbs[p];
            zg.copper.install(fb, &.{palette.SKY}, &sky_tbl[p], .{});
            fb.is_enabled = p == 0;
        }
        backdrop.init(pano.largest()); // before the library: the disk's largest panorama, or the shapes' 64 KB
        ts.look(self);
        zigos.setBackgroundColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
        zigos.blitAsync(true);
        self.lib.scan(micros); // last: its buffers take what the RAM window has left (library.RESERVE kept)
        self.lib.report();
        front.boot(self);
    }

    pub fn cur(self: *Demo) *const trk.Track {
        return &self.tracks[ts.slotOf(self.which)];
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
        if (front.input(self, dir)) return;
        self.drive.press(dir, true);
        self.game.press(dir, true);
    }

    pub fn inputRelease(self: *Demo, dir: u8) void {
        front.release(self, dir);
        self.drive.press(dir, false);
        self.game.press(dir, false);
    }

    /// Driving needs a racing line: any track but a benchmark-only one (the city); lap v1 (its stream) the oval.
    pub fn setDrive(self: *Demo, m: drive.Mode) void {
        if (m != .off and ts.needsOval(self.cur(), self.which, m == .bench) and self.which != 0) self.setTrack(0);
        self.pose = null;
        self.game.setMode(.off);
        self.drive.setMode(m);
        self.r = if (m == .bench) BENCH_R else ts.playR(self);
        self.rep = .{ .crc_on = self.rep.crc_on };
        self.bench.resetLap();
    }

    /// The race (M3), likewise; it replaces driving.
    pub fn setGame(self: *Demo, m: game.Mode) void {
        if (m != .off and ts.needsOval(self.cur(), self.which, false) and self.which != 0) self.setTrack(0);
        self.pose = null;
        self.drive.setMode(.off);
        self.game.setMode(m);
        self.r = if (m == .bench) BENCH_R else ts.playR(self);
        self.rep = .{ .crc_on = self.rep.crc_on };
        self.bench.resetLap();
    }

    pub fn setTrack(self: *Demo, w: usize) void {
        ts.setTrack(self, w, micros);
    }

    pub fn update(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        if (self.paused) return audio.pause(self);
        self.bench.tickStart();
        defer self.bench.tickEnd();
        if (self.pose == null and self.drive.mode == .off and self.game.mode == .off) self.script +%= 1;
        self.drive.update();
        self.game.update();
        audio.frame(self);
        front.update(self);
    }

    pub fn render(self: *Demo, zigos: *zg.ZigOS, dt: f32) void {
        _ = dt;
        view.render(self, zigos);
    }
};
