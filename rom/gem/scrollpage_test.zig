// gui/scrollpage.zig natively (build.sh's NATIVE_TESTS). Here, not beside it: gui/ imports
// ../gem_glyphs.zig, so `zig test` needs rom/gem as its root.
const std = @import("std");
const types = @import("gui/types.zig");
const sp = @import("gui/scrollpage.zig");

fn window() types.Window {
    var w: types.Window = .{ .r = .{ .x = 0, .y = 20, .w = 200, .h = 120 }, .title = "A:\\" };
    w.vslide = 250;
    w.vmax = 9;
    w.vpage = 3;
    w.hslide = 500;
    w.hmax = 14;
    w.hpage = 23;
    return w;
}

test "a click in the vertical track pages by vpage towards it, clamped to 0..vmax" {
    var w = window();
    const tr = types.vTrack(&w);
    const below = tr.y + tr.h - 2; // under the slider
    try std.testing.expect(sp.trackPress(&w, tr.x + 2, below));
    try std.testing.expectEqual(@as(i16, 3), w.vscroll);
    w.vscroll = 7;
    try std.testing.expect(sp.trackPress(&w, tr.x + 2, below)); // 7 + 3 is past the end
    try std.testing.expectEqual(@as(i16, 9), w.vscroll);
    w.vscroll = 8;
    try std.testing.expect(sp.trackPress(&w, tr.x + 2, tr.y + 1)); // above the slider: back a page
    try std.testing.expectEqual(@as(i16, 5), w.vscroll);
}

test "a click in the horizontal track pages by hpage, clamped" {
    var w = window();
    const tr = types.hTrack(&w);
    try std.testing.expect(sp.trackPress(&w, tr.x + tr.w - 2, tr.y + 2)); // right of the slider
    try std.testing.expectEqual(@as(i16, 14), w.hscroll); // 0 + 23, clamped to hmax
    try std.testing.expect(sp.trackPress(&w, tr.x + 1, tr.y + 2)); // left of it now
    try std.testing.expectEqual(@as(i16, 0), w.hscroll);
}

test "the slider, the work area and a window with nothing to scroll are not pages" {
    var w = window();
    w.vscroll = 5;
    const tr = types.vTrack(&w);
    const s = types.sliderBox(tr, w.vslide, w.vscroll, w.vmax, true);
    try std.testing.expect(!sp.trackPress(&w, tr.x + 2, s.y + 1)); // the slider drags (window.zig)
    try std.testing.expect(!sp.trackPress(&w, 100, 60)); // the work area
    w.vmax = 0;
    w.vslide = 1000;
    try std.testing.expect(!sp.trackPress(&w, tr.x + 2, tr.y + tr.h - 2)); // all of it shows
    try std.testing.expectEqual(@as(i16, 5), w.vscroll);
}
