// --------------------------------------------------------------------------
// The Union Demo (1989), TCB2: The Carebears' "WOW!-SCROLLER", ported from
// shazz's melonJS "Union Demo HTML5 Remake" 0.9.8 (screens/superscroller/
// screen.js, loader.js). Program by Nick and Jas, graphics by ES, sampled
// sound by An Cool: all The Carebears' / The Union's.
//
// On screen, in draw order (screen.js:106-138), one plane:
//   back.png, three copies 398 canvas rows apart, scrolling up 3.35 a frame
//   the scroller: 384x380 letters, 7 px a frame, coloured 'source-atop' by five
//     copies of rasters.png scrolling up 2 a frame, at canvas y 14
//   overlay.png, two copies riding with the back
//
// Geometry: a 640x400 canvas = ST 320x200 doubled; ST pixel (x, y) is canvas
// pixel (2x, 2y), so nothing needs the borders.
//
// The fractional scroll is the look. Chrome does not snap 3.35 px: it filters
// (chrome_draw.zig, measured on the remake's own frames), so the rows of the
// back and overlay blend in 16ths while they move. Those blends are exact per
// line through a line palette (linepal.zig): 80 entries a line, 56 the most any
// line needs. The JS replay of screen.js with that filtering matches Chrome at
// 0 px on 29 frames (apps/union_superscroller_replay.mjs).
//
// Loading: the remake's TEX loader panel (loader.js) is the real depack here:
// superscroller.bin ships ZX0-packed with fx = tex_loader and that panel. The
// "PRESS SPACE TO ENTER" wait is not kept: the screen starts when the data is in.
//
// Leaving: Escape or Space ('exit' / 'enter', screen.js:93-97) goes back to the
// hub, as me.state.change(MENU_LOADER) does. 1, 2 and 3 pick how the tune is
// played (zg.requestSndhMode, libs/zig/players/sndh_native.zig), as on BEAT DIS:
// 1 its 68000 code, 2 native (the same sound, the default), 3 the samples on PCM.
//
// The text starts at jsApp.mainscrollerPos (screen.js:44, 61), from the hub's ROM
// scratch note (union_demo/hub_note.zig) when it is this door's; our text is a
// byte-identical copy of the hub's (the harness checks). screen.js:84 hands back
// scroffset, so leaving rewrites that note with its x/y and our offset; without
// an accepted note nothing is written.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const DepackFx = @import("depackers").depack_fx.Runner(zg, null);
const packed_assets = @import("packed_assets");

const A = @import("union_superscroller/assets.zig");
const Motion = @import("union_superscroller/motion.zig").Motion;
const compose = @import("union_superscroller/compose.zig");
const inkmask = @import("union_superscroller/inkmask.zig");
const layers = @import("union_superscroller/layers.zig");
const rowpal = @import("union_superscroller/rowpal.zig");
const hub_note = @import("union_demo/hub_note.zig").HubNote("union_superscroller");
const TEXT_LEN = @import("union_superscroller/motion.zig").TEXT.len;

// me.audio.playTrack("zik_tcb2") (screen.js:67): the remake plays a sample,
// data/music/zik_tcb2.ogg, An Cool's sampled sound (loader.js:28-29 credits it).
// The Mad_Max/Demos/Union_Demo folder has no TCB2 tune, so this SNDH comes from
// OUTSIDE that folder, by Matt's call (2026-09-14): AN_Cool/Wow_Scroller.sndh,
// tune 1 ("Wow Scroller", AN Cool, 1989, one subtune, FLAG ~ay). Its samples go
// through the YM's volume registers, so it plays here: sndh_headless.mjs gives
// SNDH mode, peak 0.3300, volumes written on voices A and C, no stuck PC.
const MUSIC = "union/wow_scroller.sndh";
const MUSIC_TUNE = 1; // its one subtune, asked for by number
const HUB = "union_demo";
// 140,601 bytes at 5 a line (1,400 a frame) depack in 101 frames; the remake's
// panel lands its 437th letter after 94 (13,130 ms at 140 ms a frame).
const DEPACK_BYTES_PER_LINE = 5;
// The layer tables (layers.zig) build over the loading frames as their bytes
// arrive (the overlay's rows from frame 46 on, the colours at frame 92 of 101),
// this much a frame at most: 9 rows arrive a frame.
const TABLE_UNITS_PER_FRAME = 12;
const K_ESC: u32 = 0xE012;
// Module scope: the runner needs a stable address.
var depack: DepackFx = undefined;

const Phase = enum { loading, running, left };

pub const Demo = struct {
    phase: Phase,
    buf: []u8,
    images: A.Images,
    motion: Motion,
    /// 200 lines x 80 colours: on zg.mem next to the depacked image, not in the cart's data.
    palette: *compose.Palette,
    /// The row's colour-key cache (inkmask.zig): on zg.mem, not in the cart's data.
    cache: *inkmask.KeyCache,
    /// The frame-independent entry images and colour tables (layers.zig), on zg.mem.
    tables: *layers.Tables,
    font_store: *A.FontStore, // the font's u16 tables, aligned (spanfont.aligned), on zg.mem
    /// The per-row descriptors the HBL reads (rowpal.zig).
    rows: rowpal.Ctx,
    blitter: zg.Blitter,
    tables_built: layers.Progress,
    /// The hub's note for this door, peeked at init; null: none, or another door's.
    note: ?hub_note.Note,
    leave: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.phase = .left;
        self.buf = &.{};
        self.images = undefined;
        self.leave = false;
        self.note = hub_note.accepted(TEXT_LEN);
        self.motion.init(if (self.note) |n| n.scroll else 0);
        // On zg.mem, taken once: init runs once per cart load.
        self.buf = zg.mem.alloc(u8, A.TOTAL) orelse return self.abandon("no free RAM to depack into");
        const palette = zg.mem.alloc(compose.Palette, 1) orelse return self.abandon("no free RAM for the palette");
        self.palette = &palette[0];
        const cache = zg.mem.alloc(inkmask.KeyCache, 1) orelse return self.abandon("no free RAM for the colour cache");
        self.cache = &cache[0];
        self.cache.init();
        self.palette.init();
        const tables = zg.mem.alloc(layers.Tables, 1) orelse return self.abandon("no free RAM for the layer tables");
        self.tables = &tables[0];
        self.tables.builder = .{};
        self.font_store = &(zg.mem.alloc(A.FontStore, 1) orelse return self.abandon("no free RAM for the font"))[0];
        self.tables_built = .more;
        self.blitter.init();
        if (!depack.start(zigos, packed_assets.union_superscroller, self.buf, DEPACK_BYTES_PER_LINE))
            return self.abandon("packed image unreadable");
        self.phase = .loading;
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase == .loading) switch (depack.frame(zigos)) {
            .more => return self.buildTables(TABLE_UNITS_PER_FRAME),
            .done => self.start(zigos), // and this frame is the screen's first
            .failed => return self.abandon("depack failed"),
        };
        if (self.phase != .running) return;
        self.motion.step();
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (self.phase != .running) return;
        compose.drawFrame(.{
            .fb = &zigos.lfbs[0],
            .blitter = &self.blitter,
            .img = &self.images,
            .tables = self.tables,
            .desc = &self.rows.desc,
            .cache = self.cache,
            .m = &self.motion,
            .pal = self.palette,
        });
    }

    /// Host input ids: 5 fire, 6 back.
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == 6 or (dir == 5 and self.phase == .running)) self.leaveForHub();
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC or (cp == ' ' and self.phase == .running)) self.leaveForHub();
        if (self.phase == .running and cp >= '1' and cp <= '3') _ = zg.requestSndhMode(@intCast(cp - '0'));
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

    /// Some of the layer tables, as the bytes they read are depacked.
    fn buildTables(self: *Demo, units: usize) void {
        if (self.tables_built != .more) return;
        self.images = A.Images.split(self.buf); // views; the colours it reads are final by the time F needs them
        self.tables_built = self.tables.builder.step(self.tables, &self.images, depack.stream.written(), units);
    }

    fn start(self: *Demo, zigos: *ZigOS) void {
        self.buildTables(layers.UNITS); // whatever the loading frames left
        if (self.tables_built != .done) return self.abandon("a row holds more keys than the layer tables take");
        self.images.useFont(self.font_store);
        self.rows = .{ .desc = @splat(.{}), .tables = self.tables, .pal = self.palette, .img = &self.images, .motion = &self.motion };
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        rowpal.install(&self.rows, fb);
        zg.requestSongTune(MUSIC, MUSIC_TUNE); // onResetEvent
        self.phase = .running;
    }

    /// me.state.change(MENU_LOADER), with jsApp.mainscrollerPos where this
    /// scroller stands: the next character to enter, as the hub counts it.
    fn leaveForHub(self: *Demo) void {
        self.leave = true;
        if (self.phase != .running) return; // the text never moved
        const n = self.note orelse return;
        hub_note.handBack(n, self.motion.scroffset());
    }

    /// Without its pictures there is no screen: say why and go back to the hub.
    fn abandon(self: *Demo, why: []const u8) void {
        zg.Console.log("union_superscroller: {s}, back to the menu", .{why});
        self.phase = .left;
        self.leave = true;
    }
};
