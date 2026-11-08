// The ripped data, embedded (tools/c64_transmission64_rip.py writes it; data.zig gives it its layout).
const data = @import("data.zig");
const DIR = "../../assets/screens/c64_transmission64/";

pub const all = data.Data{
    .part1 = .{ .b = @embedFile(DIR ++ "part1.bin") },
    .wipe = .{ .b = @embedFile(DIR ++ "wipe.bin") },
    .part2 = .{ .b = @embedFile(DIR ++ "part2.bin") },
    .part3 = .{ .b = @embedFile(DIR ++ "part3.bin") },
};
