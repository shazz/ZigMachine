//! Binds an Nfo (nfo.zig) to the KESTREL desk plane (HW 1.17.0: plane 0 alone, 640x480 at 1:1, the
//! square-pixel mode: medium's 640x200 pixels are twice as tall as wide and would stretch the art).
//! `fb` is a zigos LogicalFB, taken as `anytype` so zigdemo needs no zigos import; the cart's
//! `zg.lfbs[0]`. The scroll is `fb.setScroll(0, y)`: the base moves, no pixel does.

/// Allocate the tall desk buffer, load the palette, paint the NFO once. Errors are zigos's
/// (DeskUnavailable on a machine without the mode: the cart should say so and stay low-res).
pub fn attach(nfo: anytype, fb: anytype) !void {
    try fb.setDeskPlaneRows(nfo.bufferRows());
    for (@TypeOf(nfo.*).palette, 0..) |word, i| fb.palette[i] = word;
    nfo.paint(fb.fb[0..nfo.bufferBytes()]);
    fb.setScroll(0, nfo.y);
}

/// Every frame: step the scroll and pan the plane to it.
pub fn frame(nfo: anytype, fb: anytype) void {
    fb.setScroll(0, nfo.update());
}
