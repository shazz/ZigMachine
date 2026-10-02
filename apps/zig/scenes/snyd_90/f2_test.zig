// --------------------------------------------------------------------------
// F2 against the ORIGINAL code, byte for byte: every CRC32 is of the part's
// memory after N VBLs on the Musashi oracle (prototypes/snyd90_re/m68run,
// whose run matches Hatari's RAM of the real part at VBL 193 to the byte but
// for the VBL flag and the stack). `oracle_expect.py f2` prints these: `mem`
// is $1000..$70000 without the music ($8836..$AF16, the SNDH's) and the VBL
// flag; `a`/`b` the two screens; `pal` the colour registers.
// Run through apps/zig/scene_tests.zig.
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const f2 = @import("f2.zig");
const palette = @import("palette.zig");
const oracle = @import("oracle_crc.zig");

const IMAGE = @embedFile("../../assets/screens/snyd_90/f2.raw");

var mem: [f2.TOP - f2.BASE]u8 = undefined;

const EXPECT = [_]oracle.Expect{
    .{ .vbl = 1, .mem = 0x3e9ddfd9, .a = 0x9d675e0e, .b = 0x5bd12871, .pal = 0x36e1963b },
    .{ .vbl = 2, .mem = 0x91e5cf55, .a = 0x9d675e0e, .b = 0x8a16c46b, .pal = 0x36e1963b },
    .{ .vbl = 3, .mem = 0x04377cfd, .a = 0x6ace3afc, .b = 0x8a16c46b, .pal = 0x36e1963b },
    .{ .vbl = 50, .mem = 0xe1e2eb42, .a = 0x21199648, .b = 0x624a22da, .pal = 0x36e1963b },
    .{ .vbl = 193, .mem = 0xd9448a53, .a = 0xb4d53c88, .b = 0x12f204d4, .pal = 0x36e1963b },
    .{ .vbl = 700, .mem = 0x04a3bb58, .a = 0x08c51628, .b = 0xc7270dab, .pal = 0x36e1963b },
    .{ .vbl = 1500, .mem = 0x1604f34f, .a = 0x9b8e7309, .b = 0x0fdef5f3, .pal = 0x36e1963b },
};

const HOLES = [_][2]u32{ .{ 0x1646, 0x1650 }, .{ 0x8836, 0xAF16 } };

test "F2 matches the original code's memory after 1..1500 VBLs" {
    @memcpy(&mem, IMAGE);
    const r = st.Ram{ .base = f2.BASE, .m = &mem };
    var pal = palette.at(&r, f2.PALETTE);
    var done: u32 = 0;
    for (EXPECT) |e| {
        while (done < e.vbl) : (done += 1) {
            _ = f2.top(&r, &pal);
            f2.bottom(&r);
        }
        try oracle.check(&r, e, &HOLES, pal);
    }
}
