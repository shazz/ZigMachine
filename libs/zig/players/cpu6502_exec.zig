// --------------------------------------------------------------------------
// The 6502's instructions (cpu6502.zig): addressing, then the operation, then
// its cycles. Cycles follow from the operation's class and the mode, as in the
// 6502.org tables: a READ pays a page cross on abs,X / abs,Y / (zp),Y, a WRITE
// and a READ-MODIFY-WRITE always take the long form.
// --------------------------------------------------------------------------
const cpu = @import("cpu6502.zig");
const alu = @import("cpu6502_alu.zig");
const ops = @import("cpu6502_ops.zig");
const Mode = cpu.Mode;

pub const Addr = struct { a: u16, crossed: bool = false };

fn indexed(base: u16, by: u8) Addr {
    const a = base +% by;
    return .{ .a = a, .crossed = (a ^ base) & 0xFF00 != 0 };
}

pub fn ea(comptime S: type, c: *S, mode: Mode) Addr {
    return switch (mode) {
        .imm => blk: {
            const a = c.pc;
            c.pc +%= 1;
            break :blk .{ .a = a };
        },
        .zp => .{ .a = c.fetch() },
        .zpx => .{ .a = c.fetch() +% c.x },
        .zpy => .{ .a = c.fetch() +% c.y },
        .abs, .ind => blk: {
            const a = c.read16(c.pc);
            c.pc +%= 2;
            break :blk .{ .a = a };
        },
        .abx, .aby => blk: {
            const base = c.read16(c.pc);
            c.pc +%= 2;
            break :blk indexed(base, if (mode == .abx) c.x else c.y);
        },
        .izx => .{ .a = c.read16Page(c.fetch() +% c.x) },
        .izy => indexed(c.read16Page(c.fetch()), c.y),
        .imp, .acc, .rel => .{ .a = 0 },
    };
}

fn readCycles(mode: Mode, crossed: bool) u64 {
    const x: u64 = @intFromBool(crossed);
    return switch (mode) {
        .imp, .imm => 2,
        .zp => 3,
        .zpx, .zpy, .abs => 4,
        .abx, .aby => 4 + x,
        .izx => 6,
        .izy => 5 + x,
        else => 2,
    };
}

fn writeCycles(mode: Mode) u64 {
    return switch (mode) {
        .zp => 3,
        .zpx, .zpy, .abs => 4,
        .abx, .aby => 5,
        else => 6, // (zp,X), (zp),Y
    };
}

fn rmwCycles(mode: Mode) u64 {
    return switch (mode) {
        .acc => 2,
        .zp => 5,
        .zpx, .abs => 6,
        .abx, .aby => 7,
        else => 8, // (zp,X), (zp),Y: the unintended RMWs only
    };
}

pub fn run(comptime S: type, c: *S, e: cpu.Entry) void {
    switch (e.op) {
        .lda, .ldx, .ldy, .lax, .adc, .sbc, .and_, .ora, .eor, .cmp, .cpx, .cpy, .bit, .nop, .anc, .alr, .arr, .sbx => {
            if (e.mode == .imp) {
                c.cycles += 2; // NOP
                return;
            }
            const at = ea(S, c, e.mode);
            ops.read(S, c, e.op, c.read(at.a));
            c.cycles += readCycles(e.mode, at.crossed);
        },
        .sta, .stx, .sty, .sax => {
            const at = ea(S, c, e.mode);
            c.write(at.a, switch (e.op) {
                .sta => c.a,
                .stx => c.x,
                .sty => c.y,
                else => c.a & c.x,
            });
            c.cycles += writeCycles(e.mode);
        },
        .asl, .lsr, .rol, .ror, .inc, .dec, .slo, .rla, .sre, .rra, .dcp, .isc => {
            if (e.mode == .acc) {
                c.a = ops.modify(S, c, e.op, c.a);
            } else {
                const at = ea(S, c, e.mode);
                const old = c.read(at.a);
                c.write(at.a, old); // the NMOS chip writes the old value first
                c.write(at.a, ops.modify(S, c, e.op, old));
            }
            c.cycles += rmwCycles(e.mode);
        },
        else => ops.control(S, c, e),
    }
}
