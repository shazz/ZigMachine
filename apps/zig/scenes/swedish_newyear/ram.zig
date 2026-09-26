// Every large working buffer of the cart, reached through ONE struct of pointers
// set in init(), so they can move to run-time allocation (zg.mem) by changing only
// this file. Today they are module-scope statics, which with --import-memory the
// linker writes out as zero data segments:
//   px    224,000 B  frame.zig: the picture, a gid per physical pixel (every part)
//   bank  142,800 B  frame.zig: each line's palette entries, as gids (every part)
//   part  PART_LEN   assets.zig: the part on screen's depacked pictures + scratch
//                    (TCB #1's noise, TCB #2's orgcanvas); OMEGA's set is the largest
const frame = @import("frame.zig");
const assets = @import("assets.zig");

pub const Bank = [frame.PH][255]u16;

pub const Buffers = struct {
    px: *[frame.PH][frame.PW]u16,
    bank: *Bank,
    part: *align(4) [assets.PART_LEN]u8,
};

var px_store: [frame.PH][frame.PW]u16 = undefined;
var bank_store: Bank = undefined;
var part_store: [assets.PART_LEN]u8 align(4) = undefined;

pub var buf: Buffers = undefined;

pub fn init() void {
    buf = .{ .px = &px_store, .bank = &bank_store, .part = &part_store };
}
