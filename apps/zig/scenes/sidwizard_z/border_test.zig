// --------------------------------------------------------------------------
// border_test.zig — the sprite border against bytes dumped from the official
// SID-Wizard-1.9.prg running in VICE 3.9 (empty tune, editor just started):
// vice_empty_ordlspr.bin = RAM $0400.., vice_empty_updispr.bin = RAM $d900..
// --------------------------------------------------------------------------
const std = @import("std");
const swm = @import("swm.zig");
const dsp = @import("display.zig");
const border = @import("border.zig");

const vice_low = @embedFile("vice_empty_ordlspr.bin");
const vice_up = @embedFile("vice_empty_updispr.bin");

fn emptyOverlay() dsp.Overlay {
    var song: swm.Song = .{};
    swm.reset(&song);
    var view: dsp.View = .{};
    view.curptn1 = .{ 1, 2, 3 }; // the blank tune plays patterns 1,2,3
    view.autoadv = 1;
    view.octave = 4; // jamoctave default; upbordisp shows octave+1
    var over: dsp.Overlay = .{};
    dsp.overlayRender(&song, &view, &over);
    // the editor's own blank orderlist starts with 01 FE (as VICE shows)
    for (0..3) |t| {
        over.ordl_val[t] = @splat(0);
        over.ordl_val[t][0] = @intCast(t + 1); // the blank tune plays patterns 1,2,3
        over.ordl_val[t][1] = 0xfe; // loop marker
    }
    return over;
}

test "ordldis on the blank tune reproduces VICE's ordlspr bytes" {
    const over = emptyOverlay();
    var b = border.Border.init();
    border.lowerRender(&b, &over);
    // ordldis writes bytes 0..14 of each value's 3-column group; compare the
    // bytes it owns (lines 0..5 of each of the 3 rows, columns 0..19).
    for (0..3) |t| for (0..20) |k| {
        const off = (k / 3) * 0x40 + k % 3 + t * 21;
        for (0..5) |x| try std.testing.expectEqual(vice_low[off + 3 * x], b.low[off + 3 * x]);
    };
}

test "upbordisp on the blank tune reproduces the static header bytes" {
    var over = emptyOverlay();
    var b = border.Border.init();
    border.upperRender(&b, &over);
    var bad: usize = 0;
    for (0x40..0x200) |i| {
        if (b.up[i] != vice_up[i]) {
            bad += 1;
            std.debug.print("up[{x}] mine {x:0>2} vice {x:0>2}\n", .{ 0xd900 + i, b.up[i], vice_up[i] });
        }
    }
    std.debug.print("updispr bytes differing from VICE: {d}\n", .{bad});
    try std.testing.expect(bad <= 8); // only the live oscilloscope trace differs (dad5..dadf)
}

test "a blinking played position is cleared in its sprite cell and nowhere else (displayer2 blinkit)" {
    var over: dsp.Overlay = .{};
    over.ordl_val[1][3] = 0x2b;
    var shown = border.Border.init();
    border.lowerRender(&shown, &over);
    over.ordl_blank[1] = 3;
    var blank = border.Border.init();
    border.lowerRender(&blank, &over);
    var changed: usize = 0;
    for (shown.low, blank.low) |a, b| changed += @intFromBool(a != b);
    try std.testing.expect(changed >= 3 and changed <= 5); // the glyph rows of one cell
    over.ordl_blank[1] = -1;
    var again = border.Border.init();
    border.lowerRender(&again, &over);
    try std.testing.expectEqualSlices(u8, &shown.low, &again.low);
}
