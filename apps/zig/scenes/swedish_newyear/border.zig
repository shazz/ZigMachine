// --------------------------------------------------------------------------
// What paints a closed border: colour 0 of its line (frame.c0_next), from the
// global HBL. The board's sequencer paints the background with ONE CLEAR when
// no global handler is set (and no BEAM writes are queued), against a BG pass a
// line with one: 280 passes, ~0.24 Mc a frame. So the handler is set only while
// the table holds more than one colour; otherwise the background register gets
// that colour once, which paints the same borders.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const frame = @import("frame.zig");

const ZigOS = zg.ZigOS;
const Color = zg.Color;

var zos: *ZigOS = undefined;
var hbl_on: bool = false; // borderHbl is installed
var bg: u32 = 0; // the background set while it is not (0: none yet)

pub fn init(zigos: *ZigOS) void {
    zos = zigos;
    hbl_on = false;
    bg = 0;
    sync();
}

/// Global HBL, physical line: a closed border shows colour 0.
fn borderHbl(zigos: *ZigOS, line: u16) void {
    zigos.setBackgroundColor(Color.fromRGBA(frame.c0_next[@min(line, frame.PH - 1)]));
}

/// After every change of frame.c0_next (the end of a render, a key): what paints the
/// next frame's borders. A colour-0 table that is one colour on every line paints
/// exactly what borderHbl would, from the background register alone, and lets the
/// board fuse its 280 background passes into one CLEAR; a raster needs the HBL.
pub fn sync() void {
    const c = frame.c0_next[0];
    for (frame.c0_next[1..]) |v| if (v != c) {
        if (!hbl_on) zos.setHBLHandler(borderHbl);
        hbl_on = true;
        return;
    };
    if (hbl_on) zos.removeHBLHandler();
    if (hbl_on or bg != c) zos.setBackgroundColor(Color.fromRGBA(c));
    hbl_on = false;
    bg = c;
}
