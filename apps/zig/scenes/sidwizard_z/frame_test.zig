// --------------------------------------------------------------------------
// frame_test.zig — frame.zig: charset provenance, the two raster bars around
// the 26th row, the border sprites and the low-border ghost-pixel columns.
// --------------------------------------------------------------------------
const std = @import("std");
const dsp = @import("display.zig");
const border = @import("border.zig");
const frame = @import("frame.zig");

var fr: frame.Frame = .{};

test "editor_charset.bin is the 2 KB VICE dump (glyph 0 is the digit '0')" {
    try std.testing.expectEqual(@as(usize, 2048), frame.charset.len);
    const zero = [_]u8{ 0x00, 0x1c, 0x36, 0x36, 0x36, 0x36, 0x1c, 0x00 };
    try std.testing.expectEqualSlices(u8, &zero, frame.charset[0..8]);
}

test "26th row sits between two colour-15 raster bars (irq.inc $d021 splits)" {
    const scr: dsp.Screen = .{};
    var over: dsp.Overlay = .{};
    over.row26[0] = 'H'; // inverse 'H': glyph lines 1..7 at y=237..243
    frame.compose(&fr, &scr, &over, null);
    try std.testing.expectEqual(frame.bar_col, fr.px[236][40]);
    try std.testing.expectEqual(frame.bar_col, fr.px[244][359]);
    try std.testing.expectEqual(@as(u8, 12), fr.px[237][40]); // 'H' line 1 = 10011001
    try std.testing.expectEqual(@as(u8, 0), fr.px[237][41]);
}

test "border sprites: logo above the window, orderlist below, ghost columns blank" {
    const scr: dsp.Screen = .{};
    var over: dsp.Overlay = .{};
    over.ordl_val[0][0] = 0xff; // pair of separators: line 2 is a solid byte
    var b = border.Border.init();
    border.upperRender(&b, &over);
    border.lowerRender(&b, &over);
    frame.compose(&fr, &scr, &over, &b);
    var lit: usize = 0;
    for (14..35) |y| for (0..frame.W) |x| {
        if (fr.px[y][x] == frame.sprite_col) lit += 1;
    };
    try std.testing.expect(lit > 1000); // the SID-WIZARD logo strip
    // orderlist row 0, line 2 (y=248): columns 0 and 7 of each cell are blank
    try std.testing.expectEqual(@as(u8, 0), fr.px[248][40]);
    try std.testing.expectEqual(frame.sprite_col, fr.px[248][41]);
    try std.testing.expectEqual(@as(u8, 0), fr.px[248][47]);
}
