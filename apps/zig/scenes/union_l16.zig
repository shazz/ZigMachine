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
// Geometry: an 832x572 canvas = a 416x286 ST fullscreen, doubled. The plane is
// overscan (400x280, borders opened by the flicker trick); 8 ST columns and 3 ST
// rows are cropped off each side, a centred crop Matt chose (union_l16/assets.zig).
//
// One plane, in painter's order: the picture with its holes filled once with
// what shows through them (black, the two rasters as copper entries), the
// scroller in the column's holes, the bob. The scroller's Chrome blends get
// their palette entries per row from the HBL (union_l16/lines.zig): with the
// picture's 174 colours they would not fit one palette a frame.
//
// jsApp.mainscrollerPos: the scroller starts at the hub scroller's next character,
// from the note the hub leaves in the ROM, and writes its own offset back into
// that note on the way out, so the menu resumes from L16's text
// (screen.js:31, :89; union_demo/hub_note.zig). As on the other door screens, a
// note whose scroll is past the text is refused: the text starts at 0 and
// nothing is written back.
//
// Loading: the screen's data depacks for real behind the TEX loader panel of
// loader.js (zx0.Fx.tex_loader, build.zig). Its "PRESS SPACE" wait is not kept.
// Leaving: Escape, or Space once running ('exit' / 'enter', screen.js:99-103).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const blit = zg.blit;
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);
const packed_assets = @import("packed_assets");
const hub_note = @import("union_demo/hub_note.zig").HubNote("union_l16");

const A = @import("union_l16/assets.zig");
const L = @import("union_l16/lines.zig");
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
    canvas: []u8, // the picture, its holes filled (lines.compose): what restore() puts back
    holes: [A.H]u16, // per row, the scroller column's see-through pixels
    row_palettes: *L.RowPalettes,
    rasters: R.Rasters,
    scroller: S.Scroller,
    sprite_pos: usize,
    /// Where the bob was last drawn: the composed picture under it is put back before the next one.
    bob_at: ?struct { x: i32, y: i32 },
    note: ?hub_note.Note, // the hub's note for this door with a scroll inside the text, rewritten on leaving
    leave: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.phase = .failed;
        self.leave = false;
        self.sprite_pos = 0;
        self.bob_at = null;
        self.rasters.init();
        self.note = hub_note.accepted(S.TEXT.len);
        self.scroller.init(if (self.note) |n| n.scroll else 0); // jsApp.mainscrollerPos
        // On zg.mem, taken once: init runs once per cart load.
        const rows = zg.mem.alloc(L.RowPalettes, 1) orelse return fail("no free RAM for the row palettes");
        self.row_palettes = &rows[0];
        const buf = zg.mem.alloc(u8, A.TOTAL) orelse return fail("no free RAM to depack into");
        self.canvas = buf[0 .. A.W * A.H];
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
        const fb = &zigos.lfbs[0];
        const plane = blit.Dst.plane(fb);
        self.rasters.fill(zg.copper.table(fb, 0), zg.copper.table(fb, 1));
        // The picture was copied into the plane once, at start: only the bob and
        // the scroller move. Put the picture back under the bob's last position
        // (the ST's erase-at-the-old-position, not a 112,000-byte copy a frame),
        // repaint the scroller in its holes, then the bob, back to front.
        if (self.bob_at) |at| restore(plane, self.canvas, at.x, at.y, self.images.bob);
        const column = plane.window(@intCast(A.planeX(S.COLUMN_X)), 0, L.SLOTS, A.H);
        self.scroller.draw(column, self.images.font, &self.holes, self.row_palettes);
        const i = self.sprite_pos % A.CURVE_LEN;
        const x = A.planeX(SPRITE_X0 + 2 * A.curve_x[i] - BOB_HANDLE);
        const y = @divExact(SPRITE_Y0 + 2 * A.curve_y[i] - BOB_HANDLE - A.CROP_Y, 2);
        blit.blit(plane, self.images.bob, null, x, y, 0, .copy);
        self.bob_at = .{ .x = x, .y = y };
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
        self.rasters.bind(self.images);
        L.open(&zigos.lfbs[0], self.canvas, &self.holes, self.row_palettes, &copper_tables);
        zg.requestSong(MUSIC); // onResetEvent
        self.phase = .running;
    }
};

/// The picture's pixels under a `bob` drawn at (x, y), clipped to the plane.
fn restore(plane: blit.Dst, picture: []const u8, x: i32, y: i32, bob: blit.Image) void {
    const x0: usize = @intCast(@max(x, 0));
    const y0: usize = @intCast(@max(y, 0));
    const x1: usize = @intCast(std.math.clamp(x + @as(i32, @intCast(bob.w)), 0, @as(i32, A.W)));
    const y1: usize = @intCast(std.math.clamp(y + @as(i32, @intCast(bob.h)), 0, @as(i32, A.H)));
    if (x1 <= x0 or y1 <= y0) return;
    for (y0..y1) |row| @memcpy(plane.buf[row * plane.stride + x0 ..][0 .. x1 - x0], picture[row * A.W + x0 ..][0 .. x1 - x0]);
}

fn fail(why: []const u8) void {
    zg.Console.log("union_l16: {s}", .{why});
}
