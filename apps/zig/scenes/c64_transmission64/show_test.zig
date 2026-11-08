// The show against VICE's clock: the parts and the part-3 handlers change on the frames VICE 3.9
// x64sc ran them (prototypes/transmission64_re/tools/starts.py, probe2.py, probe3.py), with the
// ripped data read from the repo root.
//   zig test apps/zig/scenes/c64_transmission64/show_test.zig
const std = @import("std");
const S = @import("show.zig");
const P3 = @import("part3.zig");

const DIR = "apps/zig/assets/screens/c64_transmission64/";

fn load(a: std.mem.Allocator, name: []const u8) ![]u8 {
    var path: [128]u8 = undefined;
    const p = try std.fmt.bufPrint(&path, "{s}{s}", .{ DIR, name });
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, p, a, .limited(1 << 20));
}

const Mark = struct { frame: u32, state: S.State, irq: P3.Irq = .wait };

// (frame, state after it): part 1 to 726, the wipe's $0986 727..736, part 2 from 866 (its
// first IRQ 870) to 3012, part 3 from 3151; part 3's handlers as VICE's probe listed them:
// $40AA 3156..3628, $3DC1 3629..3640, $3E52 3641..4014, $3F3D 4015..4114, $4016 4115..4125,
// $40AA from 4126 (and the same 969 frames later).
const MARKS = [_]Mark{
    .{ .frame = 726, .state = .off },          .{ .frame = 736, .state = .wipe },
    .{ .frame = 865, .state = .part2_init },   .{ .frame = 870, .state = .part2 },
    .{ .frame = 3012, .state = .off },         .{ .frame = 3150, .state = .part3 },
    .{ .frame = 3155, .state = .part3, .irq = .dots },      .{ .frame = 3628, .state = .part3, .irq = .flash },
    .{ .frame = 3640, .state = .part3, .irq = .panel_in },  .{ .frame = 4014, .state = .part3, .irq = .panel_out },
    .{ .frame = 4114, .state = .part3, .irq = .back },      .{ .frame = 4125, .state = .part3, .irq = .dots },
    .{ .frame = 4597, .state = .part3, .irq = .flash },     .{ .frame = 5094, .state = .part3, .irq = .dots },
};

test "parts and handlers change on VICE's frames; no dot ever has a depth past $C0" {
    const a = std.testing.allocator;
    var bufs: [4][]u8 = undefined;
    for ([_][]const u8{ "part1.bin", "wipe.bin", "part2.bin", "part3.bin" }, 0..) |n, i| bufs[i] = try load(a, n);
    defer for (bufs) |b| a.free(b);
    const show = try a.create(S.Show);
    defer a.destroy(show);
    show.init(.{ .part1 = .{ .b = bufs[0][0..S.data.PART1_LEN] }, .wipe = .{ .b = bufs[1][0..S.data.WIPE_LEN] }, .part2 = .{ .b = bufs[2] }, .part3 = .{ .b = bufs[3] } });
    const pix = try a.create([S.vic.Out.ROWS_COLS]u8);
    defer a.destroy(pix);
    @memset(pix, 0);
    var out = S.vic.Out{ .pix = pix };
    var k: usize = 0;
    while (show.frames < 3151 + 969 * 10 + 10) { // part 3's ten shapes
        show.step(&out);
        if (k < MARKS.len and show.frames == MARKS[k].frame) {
            try std.testing.expectEqual(MARKS[k].state, show.state);
            if (show.state == .part3) try std.testing.expectEqual(MARKS[k].irq, show.p3.irq);
            k += 1;
        }
    }
    try std.testing.expectEqual(MARKS.len, k);
    try std.testing.expectEqual(@as(u32, 0), show.p3.dots.bad_depth);
}
