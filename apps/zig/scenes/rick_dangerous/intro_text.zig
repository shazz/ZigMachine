// --------------------------------------------------------------------------
// The level intro screen's prints (the model's d_intro.py, literal): the 6x6
// picture frame, the level's text, and the border prints the intro loop
// repeats every frame. intro.zig runs them.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const core = @import("core.zig");
const clock = @import("clock.zig");
const screen = @import("screen.zig");

/// 6 rows of the 6 tiles d2, d2+1, ... ($38EE8 at $1941 + n x $500).
pub fn pictureTiles(d2_: i64) void {
    var d2 = d2_;
    var d0: i64 = 0x1941;
    for (0..6) |_| {
        var k: i64 = 0;
        while (k < 6) : (k += 1) {
            m.wb(0x3B23C + k, d2);
            d2 = (d2 + 1) & 0xFFFF;
        }
        clock.work(180 + clock.PRINT_CHAR * 6 + 150);
        core.printText(d0, 0x3B23C);
        d0 = (d0 + 0x500) & 0xFFFF;
    }
}

/// One tile per column from column 5; $FF = the next line (row 2, then 13,
/// 14, ..); $FE = the end.
pub fn textPrint(a2_: i64) void {
    var a2 = a2_;
    var d1: i64 = 2;
    while (true) {
        var d0: i64 = 5;
        while (true) {
            const d2 = m.rb(a2);
            a2 += 1;
            if (d2 == 0xFF) {
                d1 += 1;
                if (d1 == 3) d1 = 0xD;
                break;
            }
            if (d2 == 0xFE) return;
            m.wb(0x3B23A, d2);
            screen.printAt(d0, d1, 0x3B23A);
            d0 += 1;
        }
    }
}

/// $3B18A..$3B1E6: the border prints on single screens.
pub fn frameText() void {
    _ = screen.printOne(0x79440, 0x3B244);
    for ([2][2]i64{ .{ 0x79940, 0x3B258 }, .{ 0x71440, 0x3B25A } }) |bt| {
        var a1 = bt[0];
        for (0..7) |_| {
            _ = screen.printOne(a1, bt[1]);
            a1 += 0x19;
            _ = screen.printOne(a1, bt[1]);
            a1 += 0x4E7;
        }
        if (bt[0] == 0x71440) _ = screen.printOne(a1, 0x3B24E);
    }
}
