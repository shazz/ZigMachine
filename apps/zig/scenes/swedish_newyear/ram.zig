// Every large working buffer of the cart, taken ONCE per cart load from the
// machine's RAM arena (zg.mem, zeroed) and reached through one struct of
// pointers. As module-scope statics they were zero data segments (the cart
// imports its memory), 612 KB of cart binary and of the window before boot.
//   px     224,000 B  frame.zig: the picture, a gid per physical pixel (menu, OMEGA)
//   bank   142,800 B  frame.zig: each line's palette entries, as gids (menu, OMEGA)
//   part   PART_LEN   assets.zig: the part on screen's depacked pictures + scratch;
//                     for SYNC and TCB, the real part's own memory (st.zig)
//   chunky  64,000 B  st_show.zig: an ST part's frame, as palette indices
//   pal    2 x 17,920 B  st_show.zig: its 16 colours per physical line, shown / next
// Hot loops read these pointers into locals first: a store through one pointer
// would otherwise force a reload of `buf` on every pixel.
const zg = @import("zigos");
const frame = @import("frame.zig");
const assets = @import("assets.zig");

pub const Bank = [frame.PH][255]u16;
pub const LinePal = [frame.PH][16]u32;

pub const Buffers = struct {
    px: *[frame.PH][frame.PW]u16,
    bank: *Bank,
    part: *align(4) [assets.PART_LEN]u8,
    chunky: *[200][320]u8,
    pal: *LinePal,
    pal_next: *LinePal,
};

pub var buf: Buffers = undefined;

pub fn init() void {
    const words = zg.mem.mustAlloc(u32, (assets.PART_LEN + 3) / 4);
    const part: [*]align(4) u8 = @ptrCast(words.ptr);
    buf = .{
        .px = zg.mem.mustAlloc([frame.PW]u16, frame.PH)[0..frame.PH],
        .bank = zg.mem.mustAlloc([255]u16, frame.PH)[0..frame.PH],
        .part = part[0..assets.PART_LEN],
        .chunky = zg.mem.mustAlloc([320]u8, 200)[0..200],
        .pal = zg.mem.mustAlloc([16]u32, frame.PH)[0..frame.PH],
        .pal_next = zg.mem.mustAlloc([16]u32, frame.PH)[0..frame.PH],
    };
}
