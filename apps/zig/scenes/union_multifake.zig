// --------------------------------------------------------------------------
// The Union Demo (1989), TCB3: The Carebears' "super-multiplane-3D-sine-
// distorted-and-whole-lotta-things-more scroller", ported from shazz's melonJS
// "Union Demo HTML5 Remake" 0.9.8 (screens/multifake/screen.js, loader.js).
// Artwork, music and scrolltext belong to The Carebears / The Union; the
// music is Mad Max's Thundercats conversion (Rob Hubbard).
//
// On screen, in draw order (screen.js:89-134), one plane, one palette:
//   32 bands of mountains, each scrolling at its own bgspeed (layers.zig)
//   "THE", stretched vertically by sin(the)
//   "CAREBEARS", each row swayed by its own sine
//   the scroller, swinging 120 canvas px, coloured by rasters.png (scroller.zig)
//
// Geometry: a 640x400 canvas drawn at 640x404 (screen.js:92-93) = ST 320x200
// doubled. Everything halves to 320x200 except the last mountain band, which
// runs to canvas row 403: its bottom two ST rows (200, 201) are cropped.
//
// Loading: the remake's TEX loader panel (loader.js) is the REAL depack here.
// The screen's pictures ship ZX0-packed with fx = tex_loader and this panel
// (build.zig), and the panel assembles as they depack. The loader's "PRESS
// SPACE TO ENTER" wait is not kept: the screen starts when the data is in.
//
// Leaving: Escape or Space (screen.js:76-80, 'exit' / 'enter') goes back to the
// hub, as me.state.change(MENU_LOADER) does.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);
const packed_assets = @import("packed_assets");

const A = @import("union_multifake/assets.zig");
const layers = @import("union_multifake/layers.zig");
const Scroller = @import("union_multifake/scroller.zig").Scroller;

// The remake plays data/music/Thundercats.ym ("TCB Scroller (UNION DEMO)", Mad
// Max). This SNDH is that tune's own replay: registers 0-5/8-10 match the YM5
// dump 100.0% over 800 frames at offset 0 (Hubbard's original: 11.2%).
const MUSIC = "union/thundercats.sndh";
const HUB = "union_demo";
// 156,511 bytes at 6 a line (1,680 a frame) depack in 94 frames, about the 99
// frames (13,820 ms at 140 ms a frame) the remake's panel takes.
const DEPACK_BYTES_PER_LINE = 6;
const K_ESC: u32 = 0xE012;

// Module scope: the runner needs a stable address.
var depack: DepackFx = undefined;

const Phase = enum { loading, running, failed };

pub const Demo = struct {
    phase: Phase,
    images: A.Images,
    mountains: layers.Mountains,
    the: layers.The,
    carebears: layers.Carebears,
    scroller: Scroller,
    leave: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.phase = .failed;
        self.leave = false;
        self.mountains.init();
        self.the.init();
        self.carebears.init();
        self.scroller.init();
        const buf = freeRam(A.TOTAL) orelse return fail("no free RAM to depack into");
        if (!depack.start(zigos, packed_assets.union_multifake, buf, DEPACK_BYTES_PER_LINE))
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
        self.mountains.update();
        self.the.update();
        self.carebears.update();
        self.scroller.update();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase != .running) return;
        const fb = &zigos.lfbs[0];
        const dst = blit.Dst.plane(fb);
        // maincanvas.fill('#000000'): every other row is overwritten by opaque mountains
        const M = layers.Mountains;
        @memset(dst.buf[M.GAP_TOP * dst.stride .. M.GAP_BOTTOM * dst.stride], A.BLACK);
        self.mountains.draw(dst, self.images.mountains);
        self.the.draw(dst, self.images.the);
        self.carebears.draw(dst, self.images.logo);
        self.scroller.draw(dst, self.images.font, self.images.rasters);
    }

    /// Host input ids: 5 fire, 6 back.
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == 6 or (dir == 5 and self.phase == .running)) self.leave = true;
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
    zg.Console.log("union_multifake: {s}", .{why});
}

/// `len` bytes of the cart's RAM window above its statics and stack.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}
