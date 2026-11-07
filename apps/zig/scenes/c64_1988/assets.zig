// The ripped data, embedded (tools/c64_1988_rip.py writes it; data.zig gives it its layout).
const data = @import("data.zig");
const DIR = "../../assets/screens/c64_1988/";

pub const all = data.Data{
    .bank3 = @embedFile(DIR ++ "bank3.bin"),
    .bank0 = @embedFile(DIR ++ "bank0.bin"),
    .rip = @embedFile(DIR ++ "ripped.bin"),
};
