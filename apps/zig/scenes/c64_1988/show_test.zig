// The show against VICE's clock: the parts start and end on the frames VICE 3.9 traced
// (tools/c64/trace_all.py over 1988.prg), with the ripped data read from the repo root.
//   zig test apps/zig/scenes/c64_1988/show_test.zig
const std = @import("std");
const S = @import("show.zig");

const RUNS_CEILING = 160; // the loop's worst frame makes 125; vic_runs.MAX is 640
const DIR = "apps/zig/assets/screens/c64_1988/";

fn load(a: std.mem.Allocator, name: []const u8) ![]u8 {
    var path: [128]u8 = undefined;
    const p = try std.fmt.bufPrint(&path, "{s}{s}", .{ DIR, name });
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, p, a, .limited(1 << 16));
}

test "parts begin and end on VICE's frames; bank 0 off its sprite blocks is never shown" {
    const a = std.testing.allocator;
    const bank3 = try load(a, "bank3.bin");
    defer a.free(bank3);
    const bank0 = try load(a, "bank0.bin");
    defer a.free(bank0);
    const rip = try load(a, "ripped.bin");
    defer a.free(rip);
    const show = try a.create(S.Show);
    defer a.destroy(show);
    show.* = S.Show.init(.{ .bank3 = bank3[0..16384], .bank0 = bank0[0..2048], .rip = rip[0..S.RIPPED_LEN] });
    const pix = try a.create([S.vic.Out.ROWS_COLS]u8);
    defer a.destroy(pix);
    @memset(pix, 0);
    var out = S.vic.Out{ .pix = pix };
    // (frame, state after it): VICE's $1FFE raises on 1645, 1715, 2183; part 1 again at 2185
    const marks = [_]struct { u32, S.State }{
        .{ 2, .logo },    .{ 1644, .logo },      .{ 1645, .wipe },   .{ 1714, .wipe },   .{ 1715, .grid_b },
        .{ 1716, .grid }, .{ 2182, .grid_over }, .{ 2183, .logo_a }, .{ 2184, .logo_b }, .{ 2185, .logo },
    };
    var k: usize = 0;
    var most: usize = 0; // sprite runs in a frame (vic_runs.zig): the rectangles drawn
    while (show.frames < 2186) {
        show.step(&out);
        most = @max(most, out.runs.n);
        if (k < marks.len and show.frames == marks[k][0]) {
            try std.testing.expectEqual(marks[k][1], show.state);
            k += 1;
        }
    }
    try std.testing.expectEqual(marks.len, k);
    std.debug.print("most runs a frame: {d}\n", .{most});
    try std.testing.expect(most <= RUNS_CEILING);
    try std.testing.expectEqual(@as(u32, 0), show.foreign);
    try std.testing.expectEqual(@as(u8, 1), show.logo.text_idx); // the second text is next
}
