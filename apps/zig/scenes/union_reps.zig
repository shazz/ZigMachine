// --------------------------------------------------------------------------
// The Union Demo (1989), REPS: The Replicants' "wobbly sprites" screen, ported
// from shazz's melonJS "Union Demo HTML5 Remake" 0.9.8 (screens/reps/screen.js,
// loader.js). Program by Excalibur, graphics by Rank Xerox, sound by Big Max
// (Mad Max), composed by Jeroen Tel: all The Replicants' / The Union's.
//
// On screen, in draw order (screen.js:232-286), one plane, one palette:
//   colour 0; six rasterbars bouncing behind the picture's windows
//   overlay.png, the picture with its windows
//   the red and blue scrollers of the menu's text (scroller.zig)
//   "CRACKING IS ... GOOD FOR YOU" and the Atari logos, filled by rasters
//   THE REPLICANTS, fourteen sprites each on its own circle
//   theunion.png over both scrollers, soft-edged
//
// Geometry: a 640x400 canvas, everything inside it, every PNG doubled on the
// (0,0) grid: one normal 320x200 plane, no borders opened.
//
// Both rasters are REAL rasters (raster.zig): the bars are colour 0 changed per
// scanline, so they also run through the closed side borders as on the ST, and
// the mask's ink is one register changed per scanline. The remake drew both as
// pixels.
//
// Loading: the remake's TEX loader panel (loader.js) is the REAL depack here:
// the screen's pictures ship ZX0-packed with fx = tex_loader and this panel
// (build.zig). The loader's "PRESS SPACE" wait is not kept.
//
// The scrollers start where the hub's scroller was, and hand their position
// back when leaving (jsApp.mainscrollerPos, through the hub's ROM-scratch note).
// Joystick left/right speeds the scrollers up and down; Escape or Space
// (screen.js:182-186, 'exit' / 'enter') goes back to the hub.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const blit = zg.blit;
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);
const packed_assets = @import("packed_assets");
const Controls = @import("union_demo/controls.zig").Controls;
const hub_note = @import("union_demo/hub_note.zig").HubNote("union_reps");

const A = @import("union_reps/assets.zig");
const layers = @import("union_reps/layers.zig");
const Scroller = @import("union_reps/scroller.zig").Scroller;
const raster = @import("union_reps/raster.zig");

// The remake plays data/music/ChildrenSongs.ym (its LHA member is U_WOBBLY.BIN);
// this is that tune's SNDH, "Children's Song" by Mad Max.
const MUSIC = "union/childrens_song.sndh";
const HUB = "union_demo";
// 163,519 bytes at 6 a line (1,680 a frame) depack in 98 frames, about the 99
// frames (13,820 ms at 140 ms a frame) the remake's panel takes.
const DEPACK_BYTES_PER_LINE = 6;
const UNION_BOTTOM_Y = 156; // scrollOverlay.draw(maincanvas, 0, 312)
const K_ESC: u32 = 0xE012;
const STEP_MS: f32 = 1000.0 / 60.0; // the screen steps once a frame

/// The plane rows something moves in: the red scroller (RED_Y, 32 rows), the mask and
/// the sprites (rows 73..127: the mask's 54 rows, the sprites' circles 75..105 + 16),
/// the blue scroller (BLUE_Y). Every other row is the overlay (and the union) as drawn
/// at start.
const DYNAMIC_ROWS = [_][2]usize{ .{ 7, 39 }, .{ 73, 127 }, .{ 163, 195 } };

/// Colour 0 and the overlay again on rows a..b: what the plane held before anything moved.
fn restoreRows(dst: blit.Dst, overlay: blit.Image, a: usize, b: usize) void {
    const win = dst.window(0, a, dst.w, b - a);
    win.fill(0, 0, win.w, win.h, 0);
    blit.blit(win, overlay, .{ .x = 0, .y = a, .w = overlay.w, .h = b - a }, 0, 0, 0, .copy);
}

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
    hub_note: ?hub_note.Note, // the hub's note for this door, when it left one
    leave: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.phase = .failed;
        self.leave = false;
        self.bars.init();
        self.rasters.init();
        self.sprites.init();
        self.hub_note = hub_note.accepted(Scroller.TEXT_LEN);
        self.scroller.init(if (self.hub_note) |n| n.scroll else 0);
        self.controls.init();
        // On zg.mem, taken once: init runs once per cart load.
        const buf = zg.mem.alloc(u8, A.TOTAL) orelse return fail("no free RAM to depack into");
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
        self.controls.tick(STEP_MS);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase != .running) return;
        const fb = &zigos.lfbs[0];
        const dst = blit.Dst.plane(fb);
        const img = &self.images;
        // Colour 0 everywhere under the picture: the bars are its colour per line.
        self.bars.paint(raster.background(fb), img);
        var next = self.bars; // the border is painted before the next frame's update
        next.update();
        next.paint(raster.nextBorder(), img);
        // The plane holds the static picture since start(): only the rows the
        // scrollers, the mask and the sprites move in are put back and redrawn.
        for (DYNAMIC_ROWS) |r| restoreRows(dst, img.overlay, r[0], r[1]);
        self.scroller.draw(dst, img.font);
        self.rasters.draw(dst, img.mask, img.rasters, raster.maskInk(fb));
        self.sprites.draw(dst, &img.sprites);
        for (DYNAMIC_ROWS) |r| {
            layers.drawUnionRows(dst, img.theunion, 0, r[0], r[1]);
            layers.drawUnionRows(dst, img.theunion, UNION_BOTTOM_Y, r[0], r[1]);
        }
    }

    /// Host input ids: 0-3 directions, 5 fire, 6 back.
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == 6 or (dir == 5 and self.phase == .running)) {
            self.leaveForHub();
        } else if (self.phase == .running) {
            self.controls.input(dir);
        }
    }

    /// Key-up of a Direction, from a host that sends it (demo_main.inputRelease).
    pub fn inputRelease(self: *Demo, dir: u8) void {
        self.controls.release(dir);
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC or (cp == ' ' and self.phase == .running)) self.leaveForHub();
    }

    /// me.state.change(MENU_LOADER), with jsApp.mainscrollerPos kept current from
    /// scrolltextBlue.scroffset (screen.js:179): the hub's note goes back with the
    /// blue scroller's offset and Charly's position untouched. No note came in, none
    /// goes out.
    fn leaveForHub(self: *Demo) void {
        self.leave = true;
        const n = self.hub_note orelse return;
        self.hub_note = null; // written once, however many leave events follow
        hub_note.handBack(n, self.scroller.offset());
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
        raster.install(zigos, fb);
        const dst = blit.Dst.plane(fb); // colour 0 under the picture, then the picture and the union
        @memset(dst.buf, 0);
        blit.blit(dst, self.images.overlay, null, 0, 0, 0, .copy);
        layers.drawUnion(dst, self.images.theunion, 0);
        layers.drawUnion(dst, self.images.theunion, UNION_BOTTOM_Y);
        zg.requestSong(MUSIC); // onResetEvent
        self.phase = .running;
    }
};


fn fail(why: []const u8) void {
    zg.Console.log("union_reps: {s}", .{why});
}
