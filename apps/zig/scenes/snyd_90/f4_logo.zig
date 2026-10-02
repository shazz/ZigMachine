// --------------------------------------------------------------------------
// F4's TCB letters: three red block letters (planes 2-3) drifting on two
// sums of sines each ($88BE: four walkers, tables $176DC / $17ADC, the
// positions at $8960). Each is drawn by its own unrolled run (f4_blit.zig)
// from 16 preshifts ($1AEDC + shift * 8) at its pixel address; the second
// and third first cut their outline with a mask ($9E48, $925C: the 16-pixel
// edge mask in d0/d1), the first just overwrites its box. The clears
// ($AAFE) wipe each letter's box of two frames ago ($8AB8 / $8ABC / $8AC0).
// --------------------------------------------------------------------------
const st = @import("../swedish_newyear/st.zig");
const blit = @import("f4_blit.zig");

pub const SHOWN: u32 = 0xF3E6; // the screen drawn now, shown next VBL
const POS: u32 = 0x8960;
/// Per letter: the box address of two frames ago, of last frame, the mask
/// run (0: none) and the draw run.
const Letter = struct { old: u32, last: u32, mask: u32, draw: u32 };
const LETTERS = [3]Letter{
    .{ .old = 0x8AB8, .last = 0x8AC4, .mask = 0, .draw = 0xA0EA },
    .{ .old = 0x8ABC, .last = 0x8AC8, .mask = 0x9E48, .draw = 0x94FE },
    .{ .old = 0x8AC0, .last = 0x8ACC, .mask = 0x925C, .draw = 0x8AD0 },
};
/// $AAFE's three sections (each `movea.l old,a2` then stores of d0 = 0).
const CLEARS = [3]struct { box: u32, run: u32 }{
    .{ .box = 0x8AC0, .run = 0xAB14 },
    .{ .box = 0x8ABC, .run = 0xB208 },
    .{ .box = 0x8AB8, .run = 0xBA9C },
};

pub fn clear(r: *const st.Ram) void {
    for (CLEARS) |c| {
        if (r.l(c.box) == 0) continue;
        var regs = blit.Regs{ .a2 = r.l(c.box) };
        blit.run(r, c.run, &regs);
    }
}

/// $88BE: the letters' positions.
pub fn move(r: *const st.Ram) void {
    const steps = [4]u16{ 10, 4, 8, 0xFFF4 };
    const apart = [4]u16{ 0x8C, 0x78, 0xFFB0, 0xFF4C };
    var w: [4]u32 = undefined;
    for (&w, steps, 0..) |*v, s, k| {
        const a = 0x88B6 + 2 * @as(u32, @intCast(k));
        v.* = (r.w(a) +% s) & 0x3FE;
        r.sw(a, @intCast(v.*));
    }
    for (0..3) |i| {
        for (&w, apart) |*v, s| v.* = (v.* +% s) & 0x3FE;
        const x = (r.w(0x176DC + w[0]) +% r.w(0x176DC + w[1])) >> 1;
        const y = (r.w(0x17ADC + w[2]) +% r.w(0x17ADC + w[3])) >> 1;
        r.sw(POS + 4 * @as(u32, @intCast(i)), x);
        r.sw(POS + 4 * @as(u32, @intCast(i)) + 2, y);
    }
}

/// $896C: the three letters at their positions, planes 2-3 of the screen.
pub fn draw(r: *const st.Ram) void {
    for (LETTERS, 0..) |l, i| {
        const x: u32 = r.w(POS + 4 * @as(u32, @intCast(i)));
        const y: u32 = r.w(POS + 4 * @as(u32, @intCast(i)) + 2);
        const shift: u5 = @intCast(15 - (x & 15));
        const at = ((x >> 4) << 3) + r.l(SHOWN) + 4 + y * st.LINE;
        r.sl(l.old, r.l(l.last));
        r.sl(l.last, at);
        const edge: u32 = (@as(u32, 0xFFFF) << shift) & 0xFFFF;
        var regs = blit.Regs{ .a0 = 0x1AEDC + 8 * @as(u32, shift), .a1 = 0x17FB4, .a2 = at };
        regs.d[0] = edge << 16 | edge;
        regs.d[1] = ~regs.d[0];
        regs.d[3] = shift;
        if (l.mask != 0) blit.run(r, l.mask, &regs);
        blit.run(r, l.draw, &regs);
    }
}
