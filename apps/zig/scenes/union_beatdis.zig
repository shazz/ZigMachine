// --------------------------------------------------------------------------
// The Union Demo (1989), TCB1: The Carebears' BEAT DIS screen, ported from
// shazz's melonJS "Union Demo HTML5 Remake" 0.9.8 (screens/beatdis/screen.js,
// screen2.js, loader.js). Program by Nick and Jas, graphics by ES, "Beat Dis"
// sampled by An Cool, the soundchip tune by Mad Max: all The Union's.
//
// One door, two screens. The loader asks (prompt.zig): SPACE is the 1 MB
// version with An Cool's sampled Beat Dis, RETURN the 1/2 MB version with Mad
// Max's Pro BMX Simulator B and "THE UNION" riding a curve. The pictures and
// scroller are the same in both (screen.zig), so one cart holds both and the
// loader's own question picks, as it did in the remake.
//
// Geometry: a 640x400 canvas = ST 320x200 doubled. scroll.png runs to canvas
// row 401; its last two rows (black) fall off the canvas as they fall off here.
//
// Loading: the pictures ship ZX0-packed with fx = tex_loader and loader.js's
// panel (build.zig), which assembles as they depack; then the question. The
// loader's own zik_loader.ogg is not played (as in union_multifake).
//
// Not kept: the remake's scroller resumes where the menu's banner scroller
// left off (jsApp.mainscrollerPos, shared by every screen). A cart starts
// fresh, so the text starts at its beginning.
//
// Keys: the cart owns the keyboard, so SPACE and RETURN arrive as themselves
// rather than both as "fire". On the screen, ESC or SPACE (screen.js:88,
// 'exit' / 'enter') go back to the hub; RETURN does nothing, as in the remake.
// A fire that is not a key (touch, pad) answers the question with "any other".
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);
const packed_assets = @import("packed_assets");

const A = @import("union_beatdis/assets.zig");
const prompt = @import("union_beatdis/prompt.zig");
const Screen = @import("union_beatdis/screen.zig").Screen;
const Version = @import("union_beatdis/screen.zig").Version;

// The two tunes, chosen by name (Matt, 2026-09-13): the 1 MB screen plays
// me.audio.playTrack("zik_beatdis"), An Cool's sampled "Beat Dis!" (1989);
// the 1/2 MB one data/music/ProBMXSimulatorB.ym, "Pro BMX Simulator B" by
// Mad Max, the Union Demo folder's own SNDH.
const MUSIC_1024 = "union/beat_dis.sndh";
const MUSIC_512 = "union/pro_bmx_simulator_b.sndh";
const MUSIC_TUNE = 1; // each image holds one subtune
const HUB = "union_demo";
// 325,408 bytes at 9 a line (2,520 a frame) depack in 130 frames; the remake's
// panel lands its 575th letter after 17,270 ms, 124 frames at 140 ms a frame.
const DEPACK_BYTES_PER_LINE = 9;
const K_ESC: u32 = 0xE012;
const K_RETURN: u32 = 13;
const FIRE: u8 = 5;
const BACK: u8 = 6;

var depack: DepackFx = undefined; // module scope: the runner needs a stable address

const Phase = enum { loading, asking, running, failed };

pub const Demo = struct {
    phase: Phase,
    images: A.Images,
    screen: Screen,
    chosen: ?Version,
    leave: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.phase = .failed;
        self.chosen = null;
        self.leave = false;
        self.screen.init(.k1024);
        const buf = freeRam(A.TOTAL) orelse return self.abandon("no free RAM to depack into");
        if (!depack.start(zigos, packed_assets.union_beatdis, buf, DEPACK_BYTES_PER_LINE))
            return self.abandon("packed image unreadable");
        self.images = A.Images.split(buf);
        self.phase = .loading;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        switch (self.phase) {
            .loading => switch (depack.frame(zigos)) {
                .more => {},
                .done => self.ask(zigos),
                .failed => self.abandon("depack failed"),
            },
            .asking => if (self.chosen) |version| {
                self.start(zigos, version);
                self.screen.update(); // onResetEvent, then this frame's update
            },
            .running => self.screen.update(),
            .failed => {},
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase != .running) return;
        self.screen.draw(zg.blit.Dst.plane(&zigos.lfbs[0]), self.images);
    }

    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) self.leave = true;
        switch (self.phase) {
            .asking => if (cp == ' ') {
                self.chosen = .k1024;
            } else if (cp == K_RETURN) {
                self.chosen = .k512;
            },
            .running => if (cp == ' ') {
                self.leave = true;
            },
            else => {},
        }
    }

    pub fn input(self: *Demo, dir: u8) void {
        if (dir == BACK) self.leave = true;
        if (dir != FIRE) return;
        if (self.phase == .asking and self.chosen == null) self.chosen = .k1024;
        if (self.phase == .running) self.leave = true;
    }

    pub fn pollCart(self: *Demo) i32 {
        if (!self.leave) return 0;
        self.leave = false;
        return 1;
    }

    pub fn cartTag(self: *Demo) []const u8 {
        _ = self;
        return HUB;
    }

    /// The panel has landed: show it with loader.js's question under it.
    fn ask(self: *Demo, zigos: *ZigOS) void {
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(A.palette);
        prompt.draw(fb, depack.text, depack.cols, A.INK, A.BLACK);
        self.phase = .asking;
    }

    fn start(self: *Demo, zigos: *ZigOS, version: Version) void {
        zigos.lfbs[0].setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        self.screen.init(version);
        zg.requestSongTune(switch (version) {
            .k1024 => MUSIC_1024,
            .k512 => MUSIC_512,
        }, MUSIC_TUNE);
        self.phase = .running;
    }

    /// Without its pictures there is no screen: say why and go back to the hub.
    fn abandon(self: *Demo, why: []const u8) void {
        zg.Console.log("union_beatdis: {s}, back to the menu", .{why});
        self.phase = .failed;
        self.leave = true;
    }
};

/// `len` bytes of the cart's RAM window above its statics and stack.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}
