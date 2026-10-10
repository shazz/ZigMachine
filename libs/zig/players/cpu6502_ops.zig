// --------------------------------------------------------------------------
// The 6502's operations (cpu6502.zig), once cpu6502_exec.zig has the operand:
// read() for the operations that consume a value, modify() for the
// read-modify-write ones (memory or A), control() for the rest: transfers,
// flags, the stack, jumps and branches. The cycles of control() are here; the
// others' are by class, in cpu6502_exec.zig.
// --------------------------------------------------------------------------
const cpu = @import("cpu6502.zig");
const alu = @import("cpu6502_alu.zig");
const flow = @import("cpu6502_flow.zig");

fn setC(c: anytype, on: bool) void { // anytype: the Cpu(Bus) instance
    c.p = if (on) c.p | alu.C else c.p & ~alu.C;
}

pub fn read(comptime S: type, c: *S, op: cpu.Op, v: u8) void {
    switch (op) {
        .lda => c.a = v,
        .ldx => c.x = v,
        .ldy => c.y = v,
        .lax => {
            c.a = v;
            c.x = v;
        },
        .and_ => c.a &= v,
        .ora => c.a |= v,
        .eor => c.a ^= v,
        .adc, .sbc, .arr => {
            const r = switch (op) {
                .adc => alu.adc(c.a, v, c.p),
                .sbc => alu.sbc(c.a, v, c.p),
                else => alu.arr(c.a, v, c.p),
            };
            c.a = r.a;
            c.p = r.p;
            return;
        },
        .cmp, .cpx, .cpy => {
            c.p = alu.cmp(c.p, switch (op) {
                .cmp => c.a,
                .cpx => c.x,
                else => c.y,
            }, v);
            return;
        },
        .bit => {
            c.p = (c.p & ~(alu.N | alu.V | alu.Z)) | (v & (alu.N | alu.V)) | (if (c.a & v == 0) alu.Z else 0);
            return;
        },
        .anc => {
            c.a &= v;
            c.p = alu.nz(c.p, c.a);
            setC(c, c.a & 0x80 != 0);
            return;
        },
        .alr => {
            const t = c.a & v;
            setC(c, t & 1 != 0);
            c.a = t >> 1;
        },
        .sbx => {
            const t = c.a & c.x;
            c.p = alu.cmp(c.p, t, v);
            c.x = t -% v;
            c.p = alu.nz(c.p, c.x);
            return;
        },
        else => return, // NOP: the operand was read, nothing else
    }
    c.p = alu.nz(c.p, switch (op) {
        .ldx => c.x,
        .ldy => c.y,
        else => c.a,
    });
}

/// A shift or rotate of `v` through C, its N and Z set.
fn shift(comptime S: type, c: *S, op: cpu.Op, v: u8) u8 {
    const cin: u8 = c.p & alu.C;
    const r: u8 = switch (op) {
        .asl, .slo => v << 1,
        .lsr, .sre => v >> 1,
        .rol, .rla => (v << 1) | cin,
        else => (v >> 1) | (cin << 7), // ror, rra
    };
    setC(c, switch (op) {
        .asl, .slo, .rol, .rla => v & 0x80 != 0,
        else => v & 1 != 0,
    });
    c.p = alu.nz(c.p, r);
    return r;
}

pub fn modify(comptime S: type, c: *S, op: cpu.Op, v: u8) u8 {
    switch (op) {
        .inc, .dec, .dcp, .isc => {
            const r = if (op == .inc or op == .isc) v +% 1 else v -% 1;
            c.p = alu.nz(c.p, r);
            if (op == .dcp) c.p = alu.cmp(c.p, c.a, r);
            if (op == .isc) read(S, c, .sbc, r);
            return r;
        },
        else => {
            const r = shift(S, c, op, v);
            switch (op) {
                .slo => read(S, c, .ora, r),
                .rla => read(S, c, .and_, r),
                .sre => read(S, c, .eor, r),
                .rra => read(S, c, .adc, r),
                else => {},
            }
            return r;
        },
    }
}

fn branch(comptime S: type, c: *S, taken: bool) void {
    const off: i8 = @bitCast(c.fetch());
    c.cycles += 2;
    if (!taken) return;
    const to = c.pc +% @as(u16, @bitCast(@as(i16, off)));
    c.cycles += if ((to ^ c.pc) & 0xFF00 != 0) 2 else 1;
    c.pc = to;
}

pub fn control(comptime S: type, c: *S, e: cpu.Entry) void {
    const p = c.p;
    switch (e.op) {
        .bpl => return branch(S, c, p & alu.N == 0),
        .bmi => return branch(S, c, p & alu.N != 0),
        .bvc => return branch(S, c, p & alu.V == 0),
        .bvs => return branch(S, c, p & alu.V != 0),
        .bcc => return branch(S, c, p & alu.C == 0),
        .bcs => return branch(S, c, p & alu.C != 0),
        .bne => return branch(S, c, p & alu.Z == 0),
        .beq => return branch(S, c, p & alu.Z != 0),
        else => {},
    }
    c.cycles += 2;
    switch (e.op) {
        .tax, .tay, .txa, .tya, .tsx, .inx, .iny, .dex, .dey => {
            const r = switch (e.op) {
                .tax, .tay => c.a,
                .txa => c.x,
                .tya => c.y,
                .tsx => c.s,
                .inx => c.x +% 1,
                .iny => c.y +% 1,
                .dex => c.x -% 1,
                else => c.y -% 1,
            };
            switch (e.op) {
                .tax, .tsx, .inx, .dex => c.x = r,
                .tay, .iny, .dey => c.y = r,
                else => c.a = r,
            }
            c.p = alu.nz(c.p, r);
        },
        .txs => c.s = c.x,
        .clc, .sec, .cli, .sei, .cld, .sed, .clv => {
            const flag = switch (e.op) {
                .clc, .sec => alu.C,
                .cli, .sei => alu.I,
                .cld, .sed => alu.D,
                else => alu.V,
            };
            c.p = if (e.op == .sec or e.op == .sei or e.op == .sed) c.p | flag else c.p & ~flag;
        },
        else => flow.stack(S, c, e),
    }
}
