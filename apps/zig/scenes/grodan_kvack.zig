// --------------------------------------------------------------------------
// GRODAN & KVACK-KVACK -- the olivierh59500 Go/Ebitengine demo
// github.com/olivierh59500/grodan-kvack-kvack-demo, ported to the ZigMachine.
//
// The Go demo is one 640x400 Ebitengine screen at 60 TPS (its default; it never
// calls SetTPS) built from six layers, drawn back to front exactly as its Draw()
// orders them:
//
//     bgGreen (tiled line-art)        moveX/moveY, both scroll on a 200-tick
//     bgPink  (tiled line-art)        moveX/bgcount cycle (10 then reset at 20)
//     12 cyan sprites                 swing/swingy on two sine phases
//     big font (BIG canvas)           mainText,  horizontal
//     vertical font (VERT canvas)     vertText,  vertical
//     small fonts (SMALL canvas x2)   smallText1/2, horizontal
//
// This cart is the SAME demo at 320x200 (the Go art sampled at every even
// pixel/row, see assets.zig) with every float in Update()/Draw() replaced by the
// integer/fixed-point state in model.zig -- the port's only departure from the
// Go's pixels is its own sub-pixel phase on the tiled backgrounds (the Go's odd
// offsets have no half-scale pixel) and <= 1 px on ~0.3% of the sprite corners
// (fixtrig's sine interpolation).
//
// THREE COLOUR SOURCES. The four scroll canvases carry per-line colour, which
// the Go gets from source-atop masks over colour rasters; on an ST that is a
// colour register rewritten per scanline, so this cart plays them from a real
// raster (zg.copper, CLAUDE.md: "a fake raster must become a real one"):
//   * BIG   palette entry 4: bigraster.pal rows 100..195, white below it (the
//           glyphs' own colour past the canvas' 192-row raster).
//   * VERT  palette entry 5: upraster.pal, one colour a row, 200 rows.
//   * SMALL palette entry 6: upraster.pal rows 16..19 (small1) and 64..67
//           (small2), each row doubled -- the two 4-row subimages the Go scaled
//           by 2. Bands outside them stay black.
// Entries 0..3 and 7 are static: black, Grodan_green's ink, Grodan_pink's ink,
// the sprite's cyan and white. All eight are the Go PNGs' literal colours, every
// channel a multiple of 32 (an ST colour register) -- no DAC expansion.
//
// MUSIC: ronken.mod, a 4-channel ProTracker module (M.K., 71,710 bytes, title
// "ronken"): the tune of So Watt's "Grodan and Kvack" demo, RONKEN.MOD from
// fujiology.org's MUSIC/FT/TUNEZ/DEMOS/ST/SOWATT/GRODAN (Matt found it). It
// replaces the earlier silence (the Go demo's own music.ym is an LHA-packed YM
// chip dump, which this project no longer uses) and is a MOD, not an SNDH: the
// ST demo played it as samples. The MOD player mixes it to DMA, as on the board.
//
// Escape hands the screen back to the menu (demo_main.zig's default: this cart
// declares no key(), so the host's Escape is the way out).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const copper = zg.copper;
const model = @import("grodan_kvack/model.zig");
const assets = @import("grodan_kvack/assets.zig");

const MUSIC = "ronken.mod";

const PLANE = 0;
const W: usize = zg.WIDTH; // 320
const H: usize = zg.HEIGHT; // 200

/// One 60 Hz tick. The Go runs at Ebitengine's default TPS (60) and its Update()
// steps every counter once per call; dt arrives here in MILLISECONDS.
const TICK_MS: f32 = 1000.0 / 60.0;

/// The demo's animation state and the tick count, module scope so the headless
/// harness's exports can read the very words compose() draws from.
pub var state: model.State = undefined;
pub var tick: u32 = 0;

/// The three raster tables (entries 4/5/6), one colour per physical row.
var copper_tables: [3]copper.Table = undefined;

pub const Demo = struct {
    acc: f32,
    ready: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.acc = 0;
        self.ready = false;
        state = model.State.init();
        tick = 0;

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        for (assets.PALETTE, 0..) |c, i| fb.palette[i] = c.toRGBA();
        for (8..256) |i| fb.palette[i] = 0; // unused above 8: transparent, never shown
        zigos.setBackgroundColor(assets.PALETTE[assets.BLACK]);

        // Entries 4/5/6 get per-line colours; 0..3 and 7 are the statics above.
        copper.install(fb, &.{ assets.BIG, assets.VERT, assets.SMALL }, &copper_tables, .{});
        model.fillRasters(copper.visible(fb, 0), copper.visible(fb, 1), copper.visible(fb, 2));

        state.compose(fb.fb[0 .. W * H]);
        zg.requestSong(MUSIC);
        self.ready = true;
    }

    pub fn update(self: *Demo, _: *ZigOS, dt_ms: f32) void {
        if (!self.ready) return;
        // dt > 0 is false for NaN, so a non-finite delta can never advance the
        // counter. The cap stops a stalled tab replaying minutes of the intro.
        if (dt_ms > 0) self.acc = @min(self.acc + @min(dt_ms, 200.0), TICK_MS * 4);
        while (self.acc >= TICK_MS) : (self.acc -= TICK_MS) {
            state.update();
            tick += 1;
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, _: f32) void {
        if (!self.ready) return;
        state.compose(zigos.lfbs[PLANE].fb[0 .. W * H]);
    }
};

// The testapi exports exist only when this scene IS the registered cart, so they
// never leak into another cart's build (kickoff2's pattern).
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("grodan_kvack/testapi.zig");
    }
}
