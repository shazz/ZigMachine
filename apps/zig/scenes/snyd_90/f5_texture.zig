// --------------------------------------------------------------------------
// F5's background: a 32x32 two-plane texture tile, written over the whole
// picture EVERY frame by the fullscreen routine itself, in the time between
// its border switches ($15A68..). Its set-up ($150B8) generated that code:
// placeholders patched into `move.l Rn,d16(a2)` stores, one per tile slot,
// eight registers (d2-d6/a4-a6: a 2-group x 4-line slice of the tile) loaded
// from the tile table with movem. Block 1 ($15B56..) runs 7 times, a2 4 lines
// further each time; block 2 ($169BE..) once more. The stores are read here
// from that patched code in the asset -- the original's own table of slots --
// and replayed. Per frame the tile moves ($1504E: two walkers pick one of 32
// preshifts and one of 32 rows of the table at $2837A) and every so often its
// colours change ($1500C: a list of (frames, colours 1-3)).
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");

pub const SHOWN: u32 = 0x18DBA; // the screen's start this frame (+ the scroll)
const TILE: u32 = 0x1A002; // the tile slice pointer
const BLOCK1: u32 = 0x15B56;
const BLOCK1_END: u32 = 0x16998; // adda.l #$398,a2
const BLOCK2: u32 = 0x169BE;
const BLOCK2_END: u32 = 0x176A0; // lea $14926(pc),a2
const MAX_STORES = 1024;

const Store = struct { reg: u8, disp: i16 };

var block1: [MAX_STORES]Store = undefined;
var block2: [MAX_STORES]Store = undefined;
var n1: usize = 0;
var n2: usize = 0;

/// Read the store slots out of the patched code (once per entry).
pub fn enter(r: *const st.Ram) void {
    n1 = scan(r, BLOCK1, BLOCK1_END, &block1);
    n2 = scan(r, BLOCK2, BLOCK2_END, &block2);
}

/// `move.l Dn,d16(a2)` = $2540+n (d2..d6; d0 = 0 and d1 = 2, the border
/// switch values, fill the slots past the tile), `move.l An,d16(a2)` =
/// $2548+n (a4..a6); everything else there is a nop or a border switch.
fn scan(r: *const st.Ram, from: u32, to: u32, out: *[MAX_STORES]Store) usize {
    var a = from;
    var n: usize = 0;
    while (a < to and n < MAX_STORES) {
        const op = r.w(a);
        const reg: ?u8 = switch (op) {
            0x2542...0x2546 => @intCast(op - 0x2542),
            0x254C...0x254E => @intCast(op - 0x254C + 5),
            0x2540, 0x2541 => @intCast(op - 0x2540 + 8),
            else => null,
        };
        if (reg) |k| {
            out[n] = .{ .reg = k, .disp = @bitCast(r.w(a + 2)) };
            n += 1;
            a += 4;
        } else a += 2;
    }
    return n;
}

/// The fullscreen routine's texture pass ($15A90..$176A0).
pub fn draw(r: *const st.Ram) void {
    var a2 = r.l(SHOWN) +% 0x8148;
    var a3 = r.l(TILE);
    for (0..8) |pass| {
        var regs = [10]u32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 2 };
        for (regs[0..8], 0..) |*v, k| v.* = r.l(a3 +% 4 * @as(u32, @intCast(k)));
        a3 +%= 32;
        const list = if (pass < 7) block1[0..n1] else block2[0..n2];
        for (list) |s| r.sl(st.add(a2, s.disp), regs[s.reg]);
        if (pass < 7) a2 +%= 0x398;
    }
}

/// $1504E: the tile's walkers -- a preshift (0..31, $200 bytes each) and a
/// row (0..31, 8 bytes each) of the table at $2837A.
pub fn move(r: *const st.Ram) void {
    const shift = walk(r, 0x19BFE, 6);
    const row = walk(r, 0x19BFA, 4);
    r.sl(TILE, 0x2837A + (@as(u32, row & 0x1F) << 3) + (@as(u32, shift & 0x1F) << 9));
}

fn walk(r: *const st.Ram, ptr: u32, step: u32) u16 {
    var a = r.l(ptr) +% step;
    if (a >= 0x1A002) a -= 0x400;
    r.sl(ptr, a);
    return r.w(a);
}

/// $1500C: colours 1..3 of the picture's palette ($195DC..), a new set
/// from the list $1A012..$1A2E2 when the count runs out.
pub fn colours(r: *const st.Ram) void {
    const count = r.w(0x1504C) -% 1;
    r.sw(0x1504C, count);
    if (count & 0x8000 == 0) return;
    var a = r.l(0x1A006) +% 8;
    if (a >= 0x1A2E2) a = 0x1A012;
    r.sl(0x1A006, a);
    r.sw(0x1504C, r.w(a));
    r.sl(0x195DC, r.l(a + 2));
    r.sw(0x195E0, r.w(a + 6));
}
