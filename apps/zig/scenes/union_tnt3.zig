// --------------------------------------------------------------------------
// The Union Demo (1989), TNT3: the TNT Crew's vector screen, ported from
// shazz's melonJS "Union Demo HTML5 Remake" 0.9.8 (screens/tnt3/screen.js,
// loader.js). Program by Jojo and Hexogen (the TNT Crew); objects, scrolltext
// and music belong to them, The Union and Mad Max.
//
// On screen, in draw order (screen.js:806-838), one plane, one palette:
//   stars.png, static
//   the chosen object: one to three codef3D engines (three.js r49 canvas faces,
//     replayed exactly by zg.zig3d), each filling its faces far to near
//   a black band over the top 18 canvas rows, and the up-and-down scroller in
//     it (union_tnt3/scroller.zig)
// Keys 1..5 (or A..E) pick the Union logo, TNT logo, ball, glider or carrier;
// the object flies away and the new one comes in (union_tnt3/show.zig).
//
// Geometry: a 640x400 canvas = ST 320x200 doubled. Every draw halves: the
// pictures on their measured (0,0) 2x grid, and the faces by taking canvas
// pixel (2X, 2Y) for ST pixel (X, Y) (zg.canvas_poly), where the browser
// antialiases.
//
// Loading: the remake's TEX loader panel (loader.js) is the REAL depack. The
// stars and font ship ZX0-packed with fx = tex_loader and that panel
// (build.zig); its "PRESS SPACE TO ENTER" wait is not kept.
//
// Leaving: ESC or SPACE (screen.js:714-719) sends the object away like any
// change, and the hub loads when the camera is out, as MENU_LOADER did.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);
const packed_assets = @import("packed_assets");

const A = @import("union_tnt3/assets.zig");
const show_mod = @import("union_tnt3/show.zig");
const Show = show_mod.Show;
const Work = show_mod.Work;
const Key = show_mod.Key;
const Scroller = @import("union_tnt3/scroller.zig").Scroller;
const BAND_ROWS = @import("union_tnt3/scroller.zig").BAND_ROWS;

// The remake plays data/music/NinjaRemix.ym, an LHA of U_TNTVEC.BIN ("TNT Vector
// Screen (UNION DEMO)", Mad Max, 8,542 frames). Despite the name it is not Ninja
// Remix: Mad_Max/Games/Ninja_Remix.sndh matches its YM registers 0% on all six
// subtunes. A sweep of every subtune of all 357 Mad Max SNDHs found it:
// Chambers_Of_Shaolin.sndh #7, a 100.0% register match over 3,000 frames at
// offset 0. union_tnt3_headless.mjs reads these two lines.
const MUSIC = "union/chambers_of_shaolin.sndh";
const MUSIC_TUNE = 7;
const HUB = "union_demo";
// 68,608 bytes at 3 a line (840 a frame) depack in 82 frames; the remake's
// panel lands its 414th letter after 89 (12,440 ms at 140 ms a frame).
const DEPACK_BYTES_PER_LINE = 3;
const K_ESC: u32 = 0xE012;

// Module scope: the runner needs a stable address.
var depack: DepackFx = undefined;

const Phase = enum { loading, running, failed };

pub const Demo = struct {
    phase: Phase,
    images: A.Images,
    show: Show,
    scroller: Scroller,
    keys: show_mod.Keys, // pressed since the last update
    leave: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.phase = .failed;
        self.leave = false;
        self.keys = .initEmpty();
        self.scroller.init();
        const ram = freeRam(A.TOTAL + @alignOf(Work) + @sizeOf(Work)) orelse return fail("no free RAM to depack into");
        const buf = ram[0..A.TOTAL];
        self.show.init(@ptrFromInt(std.mem.alignForward(usize, @intFromPtr(buf.ptr) + A.TOTAL, @alignOf(Work))));
        if (!depack.start(zigos, packed_assets.union_tnt3, buf, DEPACK_BYTES_PER_LINE))
            return fail("packed image unreadable");
        self.images = A.Images.split(buf);
        self.phase = .loading;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase == .loading) switch (depack.frame(zigos)) {
            .more => return,
            .done => self.start(zigos), // and this frame is the screen's first
            .failed => {
                self.phase = .failed;
                return fail("depack failed");
            },
        };
        if (self.phase != .running) return;
        self.scroller.update();
        self.show.update(self.keys);
        self.keys = .initEmpty();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase != .running) return;
        const dst = blit.Dst.plane(&zigos.lfbs[0]);
        blit.blit(dst, self.images.stars, null, 0, 0, null, .copy);
        self.show.draw(dst);
        @memset(dst.buf[0 .. BAND_ROWS * dst.stride], A.BLACK); // quad(0,0,640,0,640,18,0,18)
        self.scroller.draw(dst, self.images.font);
    }

    /// Host input ids: 5 fire, 6 back.
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == 5 or dir == 6) self.press(.exit);
    }

    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            K_ESC, ' ' => self.press(.exit),
            '1', 'A', 'a' => self.press(.union_logo),
            '2', 'B', 'b' => self.press(.tnt),
            '3', 'C', 'c' => self.press(.ball),
            '4', 'D', 'd' => self.press(.glider),
            '5', 'E', 'e' => self.press(.carrier),
            else => {},
        }
    }

    /// While there is no screen to send away, leaving is immediate.
    fn press(self: *Demo, k: Key) void {
        if (self.phase == .running) self.keys.insert(k) else if (k == .exit) self.leave = true;
    }

    pub fn pollCart(self: *Demo) i32 {
        if (!self.leave and !(self.phase == .running and self.show.finished)) return 0;
        self.leave = false;
        self.show.finished = false;
        return 1;
    }

    pub fn cartTag(self: *Demo) []const u8 {
        _ = self;
        return HUB;
    }

    fn start(self: *Demo, zigos: *ZigOS) void {
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(A.palette);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        zg.requestSongTune(MUSIC, MUSIC_TUNE); // onResetEvent
        self.phase = .running;
    }
};

fn fail(why: []const u8) void {
    zg.Console.log("union_tnt3: {s}", .{why});
}

/// `len` bytes of the cart's RAM window above its statics and stack.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}
