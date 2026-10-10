// --------------------------------------------------------------------------
// The 6502's stack and jump instructions (cpu6502_ops.zig control() hands them
// over, having counted 2 of their cycles): PHA PHP PLA PLP JSR RTS RTI BRK JMP.
// --------------------------------------------------------------------------
const cpu = @import("cpu6502.zig");
const alu = @import("cpu6502_alu.zig");
const exec = @import("cpu6502_exec.zig");

/// The stack and the jumps; control() has counted 2 of their cycles.
pub fn stack(comptime S: type, c: *S, e: cpu.Entry) void {
    switch (e.op) {
        .pha, .php => {
            c.push(if (e.op == .pha) c.a else c.p | alu.B | alu.U);
            c.cycles += 1;
        },
        .pla => {
            c.a = c.pull();
            c.p = alu.nz(c.p, c.a);
            c.cycles += 2;
        },
        .plp => {
            c.p = (c.pull() & ~alu.B) | alu.U;
            c.cycles += 2;
        },
        .jsr => {
            const lo = c.fetch();
            c.push(@truncate(c.pc >> 8)); // the address of JSR's last byte
            c.push(@truncate(c.pc));
            c.pc = (@as(u16, c.read(c.pc)) << 8) | lo;
            c.cycles += 4;
        },
        .rts => {
            const lo = c.pull();
            c.pc = ((@as(u16, c.pull()) << 8) | lo) +% 1;
            c.cycles += 4;
        },
        .rti => {
            c.p = (c.pull() & ~alu.B) | alu.U;
            const lo = c.pull();
            c.pc = (@as(u16, c.pull()) << 8) | lo;
            c.cycles += 4;
        },
        .brk => {
            c.pc +%= 1; // BRK's padding byte
            c.push(@truncate(c.pc >> 8));
            c.push(@truncate(c.pc));
            c.push(c.p | alu.B | alu.U);
            c.p |= alu.I;
            c.pc = c.read16(0xFFFE);
            c.cycles += 5;
        },
        .jmp => {
            const at = exec.ea(S, c, .abs).a;
            c.pc = if (e.mode == .ind) c.read16Page(at) else at;
            c.cycles += if (e.mode == .ind) 3 else 1;
        },
        else => unreachable, // the table holds no other operation
    }
}
