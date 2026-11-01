// ZM-X v1 as ROM imports: the header half of rom/zmx_exports.zig (change both in one
// commit). Each is one custom-0 instruction in a board cart image built with ZM_ZMX
// (fpga/cycles/zmx_hw.h) and libs/zig/zmx.zig's twin everywhere else, so the result is
// the same integer on every host. Call the comptime wrappers in libs/zig/zmx.zig from
// ordinary code; these are for a cart that wants the instruction itself on the board.
// dims = zmx.texDims(logW, logH).
pub extern fn zmMulsh16(a: i32, b: i32) i32;
pub extern fn zmMulsh15(a: i32, b: i32) i32;
pub extern fn zmTex2d(u: u32, v: u32, dims: u32) u32;
pub extern fn zmFunnel1(lo: u32, hi: u32) u32;
pub extern fn zmFunnel2(lo: u32, hi: u32) u32;
pub extern fn zmFunnel3(lo: u32, hi: u32) u32;
pub extern fn zmAdd8s(a: u32, b: u32) u32;
pub extern fn zmSub8s(a: u32, b: u32) u32;
pub extern fn zmAvg8(a: u32, b: u32) u32;
pub extern fn zmAdd8(a: u32, b: u32) u32;
