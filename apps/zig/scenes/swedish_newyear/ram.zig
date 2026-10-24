// Every large working buffer of the cart, taken ONCE per cart load from the
// machine's RAM arena (zg.mem, zeroed) and reached through one struct of
// pointers. As module-scope statics they were zero data segments (the cart
// imports its memory), 612 KB of cart binary and of the window before boot.
//   px     224,000 B  frame.zig: the picture, a gid per physical pixel (the menu);
//                     while TCB #1 runs, its noise mirror (tcbMirror): the menu
//                     redraws px whole when it comes back (menu_cached false)
//   bank   142,800 B  frame.zig: each line's palette entries, as gids (the menu)
//   part   PART_LEN   assets.zig: the part on screen's depacked pictures + scratch;
//                     for SYNC, TCB and OMEGA, the real part's own memory (st.zig)
//   src    62,720 B   st_show.zig: the source bytes each plane row was last converted from
//   pal    2 x 17,920 B  st_show.zig: its 16 colours per physical line, shown / next
//   plane  112,000 B  st_show.zig: an overscan frame (TCB #1, OMEGA), the whole 400x280
// Hot loops read these pointers into locals first: a store through one pointer
// would otherwise force a reload of `buf` on every pixel.
const std = @import("std");
const zg = @import("zigos");
const frame = @import("frame.zig");
const assets = @import("assets.zig");

pub const SRC_ROW = 224; // 26 groups of 8 bytes: the most one 400-px row reads
pub const Bank = [frame.PH][255]u16;
pub const LinePal = [frame.PH][16]u32;

pub const Buffers = struct {
    px: *[frame.PH][frame.PW]u16,
    bank: *Bank,
    part: *align(4) [assets.PART_LEN]u8,
    pal: *LinePal,
    pal_next: *LinePal,
    same: *[frame.PH]bool, // st_show.zig: pal's line is the line above's, not stored (same_next: pal_next's)
    same_next: *[frame.PH]bool,
    plane: *[frame.PH][frame.PW]u8,
    src: *[frame.PH][SRC_ROW]u8, // st_show.zig: the source bytes each plane row was last converted from
};

pub var buf: Buffers = undefined;

const PX_WORDS = frame.PH * frame.PW / 2;
var px_words: []u32 = &.{};

pub fn init() void {
    const words = zg.mem.mustAlloc(u32, (assets.PART_LEN + 3) / 4);
    const part: [*]align(4) u8 = @ptrCast(words.ptr);
    px_words = zg.mem.mustAlloc(u32, PX_WORDS);
    buf = .{
        .px = @ptrCast(px_words.ptr),
        .bank = zg.mem.mustAlloc([255]u16, frame.PH)[0..frame.PH],
        .part = part[0..assets.PART_LEN],
        .pal = zg.mem.mustAlloc([16]u32, frame.PH)[0..frame.PH],
        .pal_next = zg.mem.mustAlloc([16]u32, frame.PH)[0..frame.PH],
        .same = zg.mem.mustAlloc(bool, frame.PH)[0..frame.PH],
        .same_next = zg.mem.mustAlloc(bool, frame.PH)[0..frame.PH],
        .plane = zg.mem.mustAlloc([frame.PW]u8, frame.PH)[0..frame.PH],
        .src = @ptrCast(zg.mem.mustAlloc(u32, frame.PH * SRC_ROW / 4).ptr), // 4-aligned: st_convert compares it a word at a time
    };
}

/// px's memory as TCB #1's mirror (tcb1_mirror.zig). Only while a disk part is on
/// screen: the menu's next frame redraws and re-presents px whole.
pub fn tcbMirror() []align(4) u8 {
    const m = @import("tcb1_mirror.zig");
    comptime std.debug.assert(m.NEED <= 4 * PX_WORDS);
    const bytes: [*]align(4) u8 = @ptrCast(px_words.ptr);
    return bytes[0..m.NEED];
}
