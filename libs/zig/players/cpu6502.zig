// --------------------------------------------------------------------------
// An NMOS 6502, written from public documentation only (the MOS programming
// manual, the 6502.org opcode and cycle tables, Bruce Clark's decimal-mode
// notes, "No More Secrets" for the stable unintended opcodes). No GPL emulator
// source was read. It runs the SAP players (sap_player.zig).
//
// Instruction-stepped, cycle-counted: step() runs one instruction and adds its
// cycles, page-cross and branch penalties included, which is what places a
// POKEY write inside the frame. Read-modify-write instructions write the old
// value, then the new one, as the chip does (a POKEY register sees both).
// Dummy reads are not made: no SAP-visible register has a read side effect.
//
// The stable unintended opcodes run (LAX SAX DCP ISC SLO RLA SRE RRA ANC ALR
// ARR SBX, the NOPs, $EB SBC). The unstable ones (XAA LXA AHX TAS SHX SHY LAS)
// and the twelve JAMs stop the CPU: `stop` says which, and the player reports
// it rather than guessing an answer.
//
// `Bus` is a type with `read(u16) u8` and `write(u16, u8)` (static dispatch).
// --------------------------------------------------------------------------
const alu = @import("cpu6502_alu.zig");
const exec = @import("cpu6502_exec.zig");
pub const TABLE = @import("cpu6502_table.zig").TABLE;

pub const Op = enum(u8) {
    adc, alr, anc, and_, arr, asl, bcc, bcs, beq, bit, bmi, bne, bpl, brk, bvc, bvs, clc, cld, cli, clv,
    cmp, cpx, cpy, dcp, dec, dex, dey, eor, inc, inx, iny, isc, jam, jmp, jsr, lax, lda, ldx, ldy, lsr,
    nop, ora, pha, php, pla, plp, rla, rol, ror, rra, rti, rts, sax, sbc, sbx, sec, sed, sei, slo, sre,
    sta, stx, sty, tax, tay, tsx, txa, txs, tya, unstable,
};
pub const Mode = enum(u8) { imp, acc, imm, zp, zpx, zpy, abs, abx, aby, izx, izy, ind, rel };
pub const Entry = struct { op: Op, mode: Mode };
pub const Stop = enum(u8) { none, jam, unstable };

pub fn Cpu(comptime Bus: type) type {
    return struct {
        const Self = @This();
        a: u8 = 0,
        x: u8 = 0,
        y: u8 = 0,
        s: u8 = 0xFD,
        p: u8 = alu.U | alu.I,
        pc: u16 = 0,
        cycles: u64 = 0,
        stop: Stop = .none,
        stop_op: u8 = 0, // the opcode that stopped it

        pub fn read(_: *Self, a: u16) u8 {
            return Bus.read(a);
        }
        pub fn write(_: *Self, a: u16, v: u8) void {
            Bus.write(a, v);
        }
        pub fn read16(self: *Self, a: u16) u16 {
            return @as(u16, self.read(a)) | (@as(u16, self.read(a +% 1)) << 8);
        }
        /// The high byte from the same page: the zero-page pointer wrap, and JMP ($xxFF).
        pub fn read16Page(self: *Self, a: u16) u16 {
            const hi = (a & 0xFF00) | ((a +% 1) & 0x00FF);
            return @as(u16, self.read(a)) | (@as(u16, self.read(hi)) << 8);
        }
        pub fn fetch(self: *Self) u8 {
            const v = self.read(self.pc);
            self.pc +%= 1;
            return v;
        }
        pub fn push(self: *Self, v: u8) void {
            self.write(0x0100 | @as(u16, self.s), v);
            self.s -%= 1;
        }
        pub fn pull(self: *Self) u8 {
            self.s +%= 1;
            return self.read(0x0100 | @as(u16, self.s));
        }

        /// One instruction. Nothing happens once stopped.
        pub fn step(self: *Self) void {
            if (self.stop != .none) return;
            const opcode = self.fetch();
            const e = TABLE[opcode];
            switch (e.op) {
                .jam, .unstable => {
                    self.stop = if (e.op == .jam) .jam else .unstable;
                    self.stop_op = opcode;
                    self.pc -%= 1;
                },
                else => exec.run(Self, self, e),
            }
        }

        /// An IRQ (if I is clear) or an NMI: push PC and P (B clear), vector.
        pub fn interrupt(self: *Self, nmi: bool) void {
            if (!nmi and self.p & alu.I != 0) return;
            self.push(@truncate(self.pc >> 8));
            self.push(@truncate(self.pc));
            self.push((self.p | alu.U) & ~alu.B);
            self.p |= alu.I;
            self.pc = self.read16(if (nmi) 0xFFFA else 0xFFFE);
            self.cycles += 7;
        }
    };
}
