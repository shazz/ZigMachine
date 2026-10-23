// --------------------------------------------------------------------------
// The decode table of F4's unrolled runs (f4_blit.zig): one entry per 68000
// word of the code they lie in, filled the first time a run reaches it.
// --------------------------------------------------------------------------
const std = @import("std");
const st = @import("../swedish_newyear/st.zig");

/// Where every run lies: the logo's draws and clears from $8AD0, the
/// scroller's generated code up to $160C8 (measured over 2,000 VBLs).
pub const CODE_LO: u32 = 0x8AD0;
pub const CODE_HI: u32 = 0x16200;
pub const SLOTS: usize = (CODE_HI - CODE_LO) / 2;

const RTS: u16 = 0x4E75;
const CMPI_L: u16 = 0x0CB9;

pub const Kind = enum(u8) { none, stop, move_b, ld_a1, ld_a1_d, ld_a0_d, or_l, and_l, st_l };

/// One decoded instruction: `n` the data register, d1/d2 the displacements,
/// `len` its bytes.
pub const Op = extern struct { kind: Kind = .none, n: u8 = 0, len: u8 = 0, pad: u8 = 0, d1: i16 = 0, d2: i16 = 0 };

/// The instruction at `pc`, decoded on first use; null off the code (with
/// safety on, a panic: a run that leaves the code is a misread).
pub fn at(r: *const st.Ram, table: []Op, pc: u32) ?Op {
    const k = (pc -% CODE_LO) / 2;
    if (pc < CODE_LO or k >= table.len) {
        if (std.debug.runtime_safety) std.debug.panic("f4_ops: a run reaches ${X}, outside the code", .{pc});
        return null;
    }
    if (table[k].kind == .none) table[k] = decode(r, pc);
    return table[k];
}

fn decode(r: *const st.Ram, pc: u32) Op {
    const op = r.w(pc);
    if (op == RTS or op == CMPI_L) return .{ .kind = .stop };
    const ext: i16 = @bitCast(r.w(pc + 2));
    if (op == 0x1368) return .{ .kind = .move_b, .len = 6, .d1 = ext, .d2 = @bitCast(r.w(pc + 4)) };
    const n: u8 = @truncate(op >> 9 & 7);
    const kind: Kind = switch (op & 0xF1FF) {
        0x2011 => return .{ .kind = .ld_a1, .n = n, .len = 2 },
        0x2029 => .ld_a1_d,
        0x2028 => .ld_a0_d,
        0x81AA => .or_l,
        0xC1AA => .and_l,
        else => switch (op) {
            0x2540...0x2547 => return .{ .kind = .st_l, .n = @truncate(op & 7), .len = 4, .d1 = ext },
            else => {
                if (std.debug.runtime_safety) std.debug.panic("f4_ops: ${X} at ${X}", .{ op, pc });
                return .{ .kind = .stop };
            },
        },
    };
    return .{ .kind = kind, .n = n, .len = 4, .d1 = ext };
}

test "an entry decodes once and keeps its operands" {
    var mem = [_]u8{0} ** 16;
    const r = st.Ram{ .base = CODE_LO, .m = &mem };
    mem[0] = 0x25;
    mem[1] = 0x43; // move.l d3,$FFFE(a2)
    mem[2] = 0xFF;
    mem[3] = 0xFE;
    var table = [_]Op{.{}} ** 8;
    const o = at(&r, &table, CODE_LO).?;
    try std.testing.expectEqual(Kind.st_l, o.kind);
    try std.testing.expectEqual(@as(u8, 3), o.n);
    try std.testing.expectEqual(@as(i16, -2), o.d1);
    mem[0] = 0x4E; // the table, not the memory, answers from now on
    try std.testing.expectEqual(Kind.st_l, at(&r, &table, CODE_LO).?.kind);
}
