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
// The scroller resumes where the hub's banner scroller left off, and the hub
// resumes where this one left off: jsApp.mainscrollerPos (screen.js:61,85,
// screen2.js:93,116), carried in the hub's ROM note (hub_note.zig).
//
// Keys: the cart owns the keyboard, so SPACE and RETURN arrive as themselves
// rather than both as "fire". On the screen, ESC or SPACE (screen.js:88,
// 'exit' / 'enter') go back to the hub; RETURN does nothing, as in the remake.
// A fire that is not a key (touch, pad) answers the question with "any other".
//
// Key lock: the remake binds SPACE and RETURN with lock set (main.js:391-392,
// me.input.bindKey(..., true)), so a key held down to answer the question fires
// once. The host forwards no key-up, and a held key auto-repeats about every
// 33 ms, which would answer the question AND leave the screen. So after the
// choice, SPACE, RETURN and fire are ignored until none has come for
// KEY_LOCK_QUIET_MS of frame time: repeats keep it armed, letting go releases it.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);
const packed_assets = @import("packed_assets");

const A = @import("union_beatdis/assets.zig");
const prompt = @import("union_beatdis/prompt.zig");
const hub_note = @import("union_beatdis/hub_note.zig");
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
const KEY_LOCK_QUIET_MS: f32 = 100; // three missed repeats
const BACK: u8 = 6;

var depack: DepackFx = undefined; // module scope: the runner needs a stable address

const Phase = enum { loading, asking, running, failed };

pub const Demo = struct {
    phase: Phase,
    images: A.Images,
    screen: Screen,
    chosen: ?Version,
    hub: ?hub_note.Note, // the note this screen started from, given back on leaving
    key_lock: bool, // armed by the choice until SPACE/RETURN/fire go quiet
    lock_quiet_ms: f32, // frame time since the last of them while armed
    leave: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.phase = .failed;
        self.chosen = null;
        self.hub = null;
        self.key_lock = false;
        self.lock_quiet_ms = 0;
        self.leave = false;
        self.screen.init(.k1024, 0);
        const buf = freeRam(A.TOTAL) orelse return self.abandon("no free RAM to depack into");
        if (!depack.start(zigos, packed_assets.union_beatdis, buf, DEPACK_BYTES_PER_LINE))
            return self.abandon("packed image unreadable");
        self.images = A.Images.split(buf);
        self.phase = .loading;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        if (self.key_lock) {
            self.lock_quiet_ms += dt;
            if (self.lock_quiet_ms >= KEY_LOCK_QUIET_MS) self.key_lock = false;
        }
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
        if ((cp == ' ' or cp == K_RETURN) and self.swallowed()) return;
        switch (self.phase) {
            .asking => if (cp == ' ') {
                self.choose(.k1024);
            } else if (cp == K_RETURN) {
                self.choose(.k512);
            },
            .running => if (cp == ' ') {
                self.leave = true;
            },
            else => {},
        }
    }

    pub fn input(self: *Demo, dir: u8) void {
        if (dir == BACK) self.leave = true;
        if (dir != FIRE or self.swallowed()) return;
        if (self.phase == .asking) self.choose(.k1024);
        if (self.phase == .running) self.leave = true;
    }

    /// The question's answer, once; it arms the key lock.
    fn choose(self: *Demo, version: Version) void {
        if (self.chosen != null) return;
        self.chosen = version;
        self.key_lock = true;
        self.lock_quiet_ms = 0;
    }

    /// SPACE, RETURN or fire while the lock is armed: keep it armed and drop the event.
    fn swallowed(self: *Demo) bool {
        if (!self.key_lock) return false;
        self.lock_quiet_ms = 0;
        return true;
    }

    pub fn pollCart(self: *Demo) i32 {
        if (!self.leave) return 0;
        self.leave = false;
        // only a running scroller has a position to give back
        if (self.phase == .running) if (self.hub) |note| hub_note.leave(note, self.screen.letters.next);
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
        self.hub = hub_note.peek();
        self.screen.init(version, if (self.hub) |note| note.scroll else 0);
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
