// --------------------------------------------------------------------------
// The Union Demo (1989), LEVEL 16 FULLSCREEN: program by Ilja, graphics by Don,
// music by Mad Max. Ported from shazz's melonJS "Union Demo HTML5 Remake" 0.9.8
// (screens/L16/screen.js, loader.js). Artwork, music and scrolltext belong to
// Level 16 / The Union.
//
// On screen, in draw order (screen.js:112-131):
//   black; raster.png at canvas x 340 (up 1.8 px a frame); watergrad2.png at x 20
//   (down 1.5); the Union scrolltext in a 32 px column at x 736 (up 1.8); the
//   picture, whose holes show those three; the Union bob on its CurveRipper path.
//
// Geometry: an 832x572 canvas = a 416x286 ST fullscreen, doubled. Both planes are
// overscan (400x280, borders opened by the flicker trick); 8 ST columns and 3 ST
// rows are cropped off each side, a centred crop Matt chose (union_l16/assets.zig).
//
// Two planes, because the original composites two layers and they need two
// palettes. The top plane is the picture and the bob (173 colours). The bottom
// plane is maincanvas before the picture: black, the two rasters as copper
// entries, and the scroller, whose fractional position Chrome resamples into up
// to 141 blends a frame (union_l16/scroller.zig).
//
// jsApp.mainscrollerPos: the scroller starts at the hub scroller's next character,
// from the note the hub leaves in the ROM, and writes its own offset back into
// that note on the way out, so the menu resumes from L16's text
// (screen.js:31, :89; union_demo/hub_note.zig).
//
// Loading: the screen's data depacks for real behind the TEX loader panel of
// loader.js (zx0.Fx.tex_loader, build.zig). Its "PRESS SPACE" wait is not kept.
// Leaving: Escape, or Space once running ('exit' / 'enter', screen.js:99-103).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);
const packed_assets = @import("packed_assets");
const hub_note = @import("union_demo/hub_note.zig").HubNote("union_l16");

const A = @import("union_l16/assets.zig");
const R = @import("union_l16/rasters.zig");
const S = @import("union_l16/scroller.zig");

// data/music/Level16.ym ("L16.BIN") in the remake; this is Mad Max's Union Demo
// Level 16 as an SNDH, one subtune.
const MUSIC = "union/level_16.sndh";
const HUB = "union_demo";
// 147,176 bytes at 5 a line (1,400 a frame) depack in 106 frames, near the 99
// frames (13,820 ms) the remake's panel takes to write itself.
const DEPACK_BYTES_PER_LINE = 5;
const K_ESC: u32 = 0xE012;

// The bottom plane's entries.
const BLACK: u8 = 0;
const RASTER: u8 = 1;
const WATER: u8 = 2;
const SCROLL_FIRST: u8 = 3;

// The bob: canvas (70 + 2x, 20 + 2y) (screen.js:48-52), mid-handled at
// (parseInt(32/2), parseInt(33/2)) = (16, 16).
const SPRITE_X0 = 70;
const SPRITE_Y0 = 20;
const BOB_HANDLE = 16;

// Module scope: the runner needs a stable address, and copper tables belong to the scene.
var depack: DepackFx = undefined;
var copper_tables: [2]zg.copper.Table = undefined;

const Phase = enum { loading, running, failed };

pub const Demo = struct {
    phase: Phase,
    images: A.Images,
    rasters: R.Rasters,
    scroller: S.Scroller,
    sprite_pos: usize,
    note: ?hub_note.Note, // the hub's note about this launch, rewritten on leaving
    warned: bool,
    leave: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.phase = .failed;
        self.leave = false;
        self.warned = false;
        self.sprite_pos = 0;
        self.rasters.init();
        self.note = hub_note.mine();
        self.scroller.init(SCROLL_FIRST, startOffset(self.note, S.TEXT.len));
        const buf = freeRam(A.TOTAL) orelse return fail("no free RAM to depack into");
        if (!depack.start(zigos, packed_assets.union_l16, buf, DEPACK_BYTES_PER_LINE))
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
        self.sprite_pos += 1; // this.spritePos++
        self.rasters.update();
        self.scroller.update();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase != .running) return;
        const bottom = &zigos.lfbs[0];
        const top = blit.Dst.plane(&zigos.lfbs[1]);
        self.rasters.fill(zg.copper.table(bottom, 0), zg.copper.table(bottom, 1), self.images);
        const column = blit.Dst.plane(bottom).window(@intCast(A.planeX(S.COLUMN_X)), 0, S.COLUMN_W / 2, A.H);
        self.scroller.draw(column, self.images.font, bottom.palette, BLACK);
        if (self.scroller.lost > 0 and !self.warned) {
            self.warned = true;
            fail("scroller blends outran the palette");
        }
        @memcpy(top.buf[0 .. A.W * A.H], self.images.picture);
        const i = self.sprite_pos % A.CURVE_LEN;
        const x = A.planeX(SPRITE_X0 + 2 * A.curve_x[i] - BOB_HANDLE);
        const y = @divExact(SPRITE_Y0 + 2 * A.curve_y[i] - BOB_HANDLE - A.CROP_Y, 2);
        blit.blit(top, self.images.bob, null, x, y, 0, .copy);
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
        if (self.note) |n| hub_note.handBack(n, self.scroller.next); // jsApp.mainscrollerPos = scroffset
        return 1;
    }

    pub fn cartTag(self: *Demo) []const u8 {
        _ = self;
        return HUB;
    }

    fn start(self: *Demo, zigos: *ZigOS) void {
        const bottom = &zigos.lfbs[0];
        bottom.is_enabled = true;
        bottom.setOverscanBuffer();
        bottom.setPaletteEntry(BLACK, Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        zg.copper.install(bottom, &.{ RASTER, WATER }, &copper_tables, .{ .flicker = true });
        const dst = blit.Dst.plane(bottom);
        @memset(dst.buf, BLACK);
        fillColumns(dst, R.RASTER_X, R.RASTER_W, RASTER);
        fillColumns(dst, R.WATER_X, R.WATER_W, WATER);

        const top = &zigos.lfbs[1];
        top.is_enabled = true;
        top.openBorders(.all);
        top.setPalette(A.picture_palette);
        top.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        zg.requestSong(MUSIC); // onResetEvent
        self.phase = .running;
    }
};

/// A gradient's canvas columns, all rows: its colour comes from the copper.
fn fillColumns(dst: blit.Dst, canvas_x: i32, canvas_w: i32, entry: u8) void {
    const x: usize = @intCast(A.planeX(canvas_x));
    const w: usize = @intCast(@divExact(canvas_w, 2));
    for (0..dst.h) |y| @memset(dst.buf[y * dst.stride + x ..][0..w], entry);
}

/// Where the text starts: the note's character, or 0 without a note or when it
/// is not a character of this text. A note for this door is still rewritten on
/// leaving, even when its character is out of range.
fn startOffset(note: ?hub_note.Note, text_len: usize) usize {
    const n = note orelse return 0;
    return if (n.scroll < text_len) n.scroll else 0;
}

fn fail(why: []const u8) void {
    zg.Console.log("union_l16: {s}", .{why});
}

/// `len` bytes of the cart's RAM window above its statics and stack.
fn freeRam(len: usize) ?[]u8 {
    if (hw.hwRamFree() < len) return null;
    const base: usize = hw.hwRamBase() + hw.hwRamUsed();
    return @as([*]u8, @ptrFromInt(base))[0..len];
}
