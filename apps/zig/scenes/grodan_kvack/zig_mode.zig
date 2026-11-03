// --------------------------------------------------------------------------
// grodan_kvack ZIG mode: the KESTREL showcase of the screen, toggled with Z.
//
// The original stays exactly what it was on plane 0 (default OFF; the harness
// pins its pixels).  ZIG mode leaves plane 0 alone, disables it, and shows two
// other planes, both overscan with every border opened the machine's way (a
// flicker on every line, from the copper records):
//
//   plane 1  GREEN  the green line-art, drawn once, hardware-scrolled
//                   (zig_green.zig); colour 0 is the background copper bars
//   plane 2  MAIN   the pink layer ROTOZOOMED by one CHISEL AFFINE op
//                   (zig_roto.zig), then the original's sprites and scrollers
//                   as keyed blits, plus two vertical scrolltexts in the side
//                   borders (zig_layers.zig); colour 0 is transparent
//
// The copper (zig_raster.zig) writes 24-bit colours per line on both planes.
// Everything is built at the FIRST Z press (VRAM and cart RAM), so the default
// mode allocates nothing it did not before; Z again only swaps which planes
// are enabled.  The animation state is the original's (model.zig), shared.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const model = @import("model.zig");
const C = @import("chunky.zig");
const green = @import("zig_green.zig");
const roto = @import("zig_roto.zig");
const raster = @import("zig_raster.zig");
const layers = @import("zig_layers.zig");

pub const ORIGINAL_PLANE = 0;
pub const GREEN_PLANE = 1;
pub const MAIN_PLANE = 2;

pub var on: bool = false;
var tried: bool = false; // built once at most: a second try would re-allocate VRAM
var usable: bool = false;
/// The machine handle of the last toggle, for the harness's plane reads (testapi).
pub var os: ?*zg.ZigOS = null;

/// Z: switch ZIG mode on or off.  Stays off when its art cannot be built
/// (no chunky art, or cart RAM short).
pub fn toggle(zigos: *zg.ZigOS, art: ?*const C.Art) void {
    os = zigos;
    if (!on) {
        const a = art orelse return;
        if (!tried) {
            tried = true;
            usable = build(zigos, a);
        }
        if (!usable) return;
    }
    on = !on;
    const orig = &zigos.lfbs[ORIGINAL_PLANE];
    orig.is_enabled = !on;
    zigos.lfbs[GREEN_PLANE].is_enabled = on;
    zigos.lfbs[MAIN_PLANE].is_enabled = on;
    // The hidden plane 0's copper list is unpublished, so copper.endFrame stops
    // rebuilding it every frame (~0.05 Mc); its tables never change, so
    // re-publishing the same buffer gives the original back as it was.
    if (on) {
        orig_list = orig.copperBuffer() != null;
        orig.clearCopperList();
    } else if (orig_list) {
        _ = orig.copperList(zg.copper.LIST_WORDS);
    }
}
var orig_list: bool = false;

/// VRAM: the 720x480 green plane (345,600 B) + the 400x280 main plane (112,000)
/// + two copper lists (~11 KB each) on top of the four normal planes (256,000)
/// and plane 0's list: ~750 KB of the 1 MiB pool.
fn build(zigos: *zg.ZigOS, art: *const C.Art) bool {
    if (!roto.build(art.pink)) return false;
    const g = &zigos.lfbs[GREEN_PLANE];
    const m = &zigos.lfbs[MAIN_PLANE];
    g.palette[0] = A.PALETTE[A.BLACK].toRGBA();
    g.palette[A.GREEN] = A.PALETTE[A.GREEN].toRGBA();
    for (0..256) |i| m.palette[i] = 0; // 0: transparent, the green plane shows
    for (1..8) |i| m.palette[i] = A.PALETTE[i].toRGBA();
    green.build(g, art.green);
    m.setOverscanBuffer();
    return raster.install(m, g);
}

/// One ZIG frame: pan the green plane, this tick's copper colours, the
/// rotozoomed pink (it also clears the plane), then the foreground layers.
pub fn render(zigos: *zg.ZigOS, st: *const model.State, tick: u32, bl: *zg.Blitter, art: *const C.Art) void {
    green.pan(&zigos.lfbs[GREEN_PLANE], st);
    raster.frame(tick);
    const m = &zigos.lfbs[MAIN_PLANE];
    roto.draw(m, st, tick);
    layers.draw(st, m, bl, art);
}
