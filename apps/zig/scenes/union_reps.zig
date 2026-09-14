// --------------------------------------------------------------------------
// The Union Demo (1989), REPS: The Replicants' "wobbly sprites" screen, ported
// from shazz's melonJS "Union Demo HTML5 Remake" 0.9.8 (screens/reps/screen.js,
// loader.js). Program by Excalibur, graphics by Rank Xerox, sound by Big Max
// (Mad Max), composed by Jeroen Tel: all The Replicants' / The Union's.
//
// On screen, in draw order (screen.js:232-286), one plane, one palette:
//   black; six rasterbars bouncing behind the picture's windows (layers.zig)
//   overlay.png, the picture with its windows
//   the red and blue scrollers of the menu's text (scroller.zig)
//   "CRACKING IS ... GOOD FOR YOU" and the Atari logos, filled by rasters
//   THE REPLICANTS, fourteen sprites each on its own circle
//   theunion.png over both scrollers, soft-edged
//
// Geometry: a 640x400 canvas, everything inside it, every PNG doubled on the
// (0,0) grid: one normal 320x200 plane, no borders.
//
// Loading: the remake's TEX loader panel (loader.js) is the REAL depack here:
// the screen's pictures ship ZX0-packed with fx = tex_loader and this panel
// (build.zig). The loader's "PRESS SPACE" wait is not kept.
//
// Joystick left/right speeds the scrollers up and down; Escape or Space
// (screen.js:182-186, 'exit' / 'enter') goes back to the hub.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);
const packed_assets = @import("packed_assets");
const Controls = @import("union_demo/controls.zig").Controls;

const A = @import("union_reps/assets.zig");
const layers = @import("union_reps/layers.zig");
const Scroller = @import("union_reps/scroller.zig").Scroller;

// The remake plays data/music/ChildrenSongs.ym (its LHA member is U_WOBBLY.BIN);
// this is that tune's SNDH, "Children's Song" by Mad Max.
const MUSIC = "union/childrens_song.sndh";
const HUB = "union_demo";
// 163,519 bytes at 6 a line (1,680 a frame) depack in 98 frames, about the 99
// frames (13,820 ms at 140 ms a frame) the remake's panel takes.
const DEPACK_BYTES_PER_LINE = 6;
const UNION_BOTTOM_Y = 156; // scrollOverlay.draw(maincanvas, 0, 312)
const K_ESC: u32 = 0xE012;

// Module scope: the runner needs a stable address.
var depack: DepackFx = undefined;

const Phase = enum { loading, running, failed };

pub const Demo = struct {
    phase: Phase,
    images: A.Images,
    bars: layers.Bars,
    rasters: layers.Rasters,
    sprites: layers.Sprites,
    scroller: Scroller,
    controls: Controls,
    leave: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.phase = .failed;
        self.leave = false;
        self.bars.init();
        self.rasters.init();
        self.sprites.init();
        self.scroller.init();
        self.controls.init();
        const buf = freeRam(A.TOTAL) orelse return fail("no free RAM to depack into");
        if (!depack.start(zigos, packed_assets.union_reps, buf, DEPACK_BYTES_PER_LINE))
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
        self.rasters.update();
        self.bars.update();
        self.sprites.update();
        const held = self.controls.state();
        if (held.left) self.scroller.faster() else if (held.right) self.scroller.slower();
        self.scroller.update();
        self.controls.tick();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase != .running) return;
        const dst = blit.Dst.plane(&zigos.lfbs[0]);
        const img = &self.images;
        @memset(dst.buf, A.BLACK);
        self.bars.draw(dst, img);
        blit.blit(dst, img.overlay, null, 0, 0, 0, .copy);
        self.scroller.draw(dst, img.font);
        self.rasters.draw(dst, img.mask, img.rasters);
        self.sprites.draw(dst, &img.sprites);
        layers.drawUnion(dst, img.theunion, 0);
        layers.drawUnion(dst, img.theunion, UNION_BOTTOM_Y);
    }

    /// Host input ids: 0-3 directions, 5 fire, 6 back.
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == 6 or (dir == 5 and self.phase == .running)) {
            self.leave = true;
        } else if (self.phase == .running) {
            self.controls.input(dir);
        }
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC or (cp == ' ' and self.phase == .running)) self.leave = true;
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

    fn start(self: *Demo, zigos: *ZigOS) void {
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(A.palette);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        zg.requestSong(MUSIC); // onResetEvent
        self.phase = .running;
    }
};

fn fail(why: []const u8) void {
    zg.Console.log("union_reps: {s}", .{why});
}

/// `len` bytes of the cart's RAM window above its statics and stack.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}
