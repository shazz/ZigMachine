// --------------------------------------------------------------------------
// F1 against the ORIGINAL code, byte for byte: every CRC32 is of the part's
// memory after N VBLs on the Musashi oracle (prototypes/snyd90_re/m68run;
// `oracle_expect.py f1` prints these). `mem` is $1000..$70000 without the
// VBL's flags ($10EA..$10EE) and the music ($3B24..$5B24, the SNDH's); `b`
// the screen ($78000); `pal` the colour registers.
// Run through apps/zig/scene_tests.zig.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("../swedish_newyear/st.zig");
const f1 = @import("f1.zig");
const oracle = @import("oracle_crc.zig");

const IMAGE = @embedFile("../../assets/screens/snyd_90/f1.raw");

var mem: [f1.TOP - f1.BASE]u8 = undefined;

const EXPECT = [_]oracle.Expect{
    .{ .vbl = 1, .mem = 0xa1c59c25, .a = 0x5bd12871, .b = 0x33fbb9a2, .pal = 0x0ac57b71 },
    .{ .vbl = 2, .mem = 0xc835b301, .a = 0x5bd12871, .b = 0x33fbb9a2, .pal = 0x0ac57b71 },
    .{ .vbl = 3, .mem = 0x3aa84d62, .a = 0x5bd12871, .b = 0x33fbb9a2, .pal = 0x0ac57b71 },
    .{ .vbl = 50, .mem = 0xc0c8d638, .a = 0x5bd12871, .b = 0x33fbb9a2, .pal = 0x0ac57b71 },
    .{ .vbl = 193, .mem = 0xdb8bd1a5, .a = 0x5bd12871, .b = 0x33fbb9a2, .pal = 0x0ac57b71 },
    .{ .vbl = 700, .mem = 0x0a41a7d3, .a = 0x5bd12871, .b = 0xf80d644e, .pal = 0x0ac57b71 },
    .{ .vbl = 1500, .mem = 0x7e64085b, .a = 0x5bd12871, .b = 0xf1d4a701, .pal = 0x0ac57b71 },
};

const HOLES = [_][2]u32{ .{ 0x10EA, 0x10EE }, .{ 0x3B24, 0x5B24 } };

test "F1 matches the original code's memory after 1..1500 VBLs" {
    @memcpy(&mem, IMAGE);
    const r = st.Ram{ .base = f1.BASE, .m = &mem };
    var done: u32 = 0;
    for (EXPECT) |e| {
        while (done < e.vbl) : (done += 1) f1.frame(&r);
        try oracle.check(&r, e, &HOLES, f1.PALETTE);
    }
}
