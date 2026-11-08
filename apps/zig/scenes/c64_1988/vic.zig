// --------------------------------------------------------------------------
// The VIC-II's sprite unit, line by line: what the C64 shows for a list of register writes.
//
// "1988" is only sprites: every pixel on screen is one of the eight hardware sprites, reused
// down the frame by raster IRQs that rewrite their registers (multiplexing). So the port keeps
// the C64's model: each part's IRQ chain (logo.zig, wipe.zig, grid.zig) emits the writes the
// original makes, at the raster line and cycle it makes them, and this unit replays them
// against the rules of C. Bauer's "The MOS 6567/6569 video controller" (3.8, 3.9), cycle
// numbers as VICE's monitor prints them:
//   c15/16  a sprite whose Y-expansion flip-flop is set takes MCBASE <- MC; MCBASE 63 ends it
//   c55     a sprite with MxYE set inverts its flip-flop; then, enabled + DMA off + Y = line:
//           DMA on, MCBASE 0, flip-flop cleared if MxYE
//   c58     MC <- MCBASE; a sprite with DMA on fetches row MC/3, shown on the NEXT line
//   the flip-flop is held set while MxYE is 0: writing $D017 0 then a mask every line makes
//   the masked sprites repeat a row (part 3's bounce), the others advance.
// Borders (3.9): the vertical flip-flop is set on line 251 (RSEL 1) or 247 (RSEL 0) and reset
// on line 51/55 only while DEN is set; a line's right border stays open when the $D016 DEC
// lands between the X=335 and X=344 compares (cycles 55..56), and the next line's left border
// with it. Checked against VICE 3.9 x64sc: 194 of 196 captured frames pixel-exact
// (tools/c64/vicmodel.py, the same rules in Python; prototypes/1988_re/ANALYSIS.md).
// --------------------------------------------------------------------------
const draw = @import("vic_draw.zig");

pub const LINES = 312; // PAL
pub const Out = draw.Out;
pub const Mem = draw.Mem;
pub const cache = draw.cache;
pub const ROWS = draw.ROWS; // physical rows (raster lines 11..290)
pub const PTR0: u8 = 0x30; // a write to PTR0 + i is sprite i's pointer (screen + $3F8 + i)
pub const BANK: u8 = 0x38; // a write here is $DD00: bits 0-1 select the VIC bank (3 - value)
pub const NREG = 0x2F;
const queue = @import("queue.zig");
pub const Write = queue.Write;
pub const Queue = queue.Queue;
const Carry = queue.Carry;

pub const Vic = struct {
    reg: [NREG]u8,
    ptr: [8]u8 = .{0} ** 8,
    bank3: bool = false, // $DD00 low bits 0 -> bank 3 ($C000), 3 -> bank 0
    dma: u8 = 0,
    ff: u8 = 0xFF, // Y-expansion flip-flops
    mcbase: [8]u8 = .{63} ** 8,
    mc: [8]u8 = .{63} ** 8,
    row: [8][3]u8 = undefined, // fetched at c58, shown on the next line
    addr: [8]u16 = .{0} ** 8, // where each row was fetched from (the run's source: vic_runs.zig)
    abank: u8 = 0, // bit n: sprite n's row was fetched from bank 3
    shown: u8 = 0, // which sprites have a row to show on the next line
    vb: bool = true, // vertical border flip-flop (set = border)
    right_open: bool = false, // the previous line's right border stayed open
    split_cyc: u8 = 0, // cycle of this line's first border colour change (0 = none)
    carry: [2]Carry = .{ .{}, .{} }, // writes past line 311, for the next frame (double-buffered)
    cur: u1 = 0,

    pub fn init(regs: [NREG]u8) Vic {
        return .{ .reg = regs };
    }

    /// Run one PAL frame (lines 0..311) of `q`'s writes into `out`. The parts emit in line
    /// order; the last frame's carried writes (lines 0..~21) run before this frame's on a line.
    pub fn frame(self: *Vic, q: *const Queue, mem: draw.Mem, out: *Out) void {
        const prev = &self.carry[self.cur];
        self.cur ^= 1;
        const next = &self.carry[self.cur];
        next.n = 0;
        const ws = q.items();
        out.begin();
        var k: usize = 0;
        var c: usize = 0;
        for (0..LINES) |l| {
            const line: u16 = @intCast(l);
            const start = k;
            while (k < ws.len and ws[k].line == line) k += 1;
            const cs = c;
            while (c < prev.n and prev.buf[c].line == line) c += 1;
            if (c == cs) {
                self.runLine(line, ws[start..k], mem, out);
            } else { // rare: a carried handler's tail shares a line with this frame's writes
                var mix: [Carry.MAX + 64]Write = undefined;
                const n = (c - cs) + (k - start);
                @memcpy(mix[0 .. c - cs], prev.buf[cs..c]);
                @memcpy(mix[c - cs .. n], ws[start..k]);
                self.runLine(line, mix[0..n], mem, out);
            }
        }
        out.end(mem);
        while (k < ws.len) : (k += 1) {
            if (ws[k].line < LINES) @panic("vic: write out of line order"); // a part's bug, never drop it
            next.w(ws[k].line - LINES, ws[k].cyc, ws[k].reg, ws[k].val);
        }
    }

    // The line's events in Bauer's order. The row shown on this line (fetched last line) is
    // drawn at c58 with the registers as they are then, before this line's own fetch.
    fn runLine(self: *Vic, line: u16, ws: []const Write, mem: draw.Mem, out: *Out) void {
        self.verticalBorder(line);
        const left_open = self.right_open;
        const border_start = self.reg[0x20];
        self.split_cyc = 0;
        var right_open = false;
        var i: usize = 0;
        i = self.apply(ws, i, 14, &right_open);
        self.c16();
        i = self.apply(ws, i, 54, &right_open);
        self.c55(line);
        i = self.apply(ws, i, 57, &right_open);
        var li = draw.LineInfo{ .reg = &self.reg, .shown = self.shown, .data = &self.row, .addr = &self.addr, .abank = self.abank, .vb = self.vb, .left_open = left_open, .right_open = right_open, .border = border_start, .border_end = 0, .split_cyc = 0 };
        if (li.shown != 0) out.sprites(line, &li);
        self.fetchAll(mem);
        _ = self.apply(ws, i, 255, &right_open);
        self.right_open = right_open;
        li.right_open = right_open;
        li.border_end = self.reg[0x20];
        li.split_cyc = self.split_cyc;
        out.edges(line, &li);
    }

    fn apply(self: *Vic, ws: []const Write, from: usize, upto: u8, right_open: *bool) usize {
        var i = from;
        while (i < ws.len and ws[i].cyc <= upto) : (i += 1) self.write(ws[i], right_open);
        return i;
    }

    fn write(self: *Vic, wr: Write, right_open: *bool) void {
        switch (wr.reg) {
            0x16 => right_open.* = right_open.* or (wr.cyc >= 55 and wr.cyc <= 56), // the DEC; the INC restores
            0x17 => {
                self.reg[0x17] = wr.val;
                self.ff |= ~wr.val; // held set while MxYE is 0
            },
            0x20 => {
                if (wr.val & 15 != self.reg[0x20] & 15 and self.split_cyc == 0) self.split_cyc = wr.cyc;
                self.reg[0x20] = wr.val;
            },
            PTR0...PTR0 + 7 => self.ptr[wr.reg - PTR0] = wr.val,
            BANK => self.bank3 = (wr.val & 3) == 0,
            else => if (wr.reg < NREG) {
                self.reg[wr.reg] = wr.val;
            },
        }
    }

    fn verticalBorder(self: *Vic, line: u16) void {
        const rsel = self.reg[0x11] & 0x08 != 0;
        if (line == @as(u16, if (rsel) 251 else 247)) self.vb = true;
        if (line == @as(u16, if (rsel) 51 else 55) and self.reg[0x11] & 0x10 != 0) self.vb = false;
    }

    // The loops below visit only the sprites they can change. A sprite with DMA off always
    // has MC == MCBASE (c58 copies one into the other, and only DMA advances MC), so c16 and
    // c58 leave it as it is: skipping it changes nothing.
    fn c16(self: *Vic) void {
        var m = self.ff & self.dma;
        while (m != 0) : (m &= m - 1) {
            const s: usize = @ctz(m);
            self.mcbase[s] = self.mc[s];
            if (self.mcbase[s] >= 63) self.dma &= ~bit(s);
        }
    }

    fn c55(self: *Vic, line: u16) void {
        self.ff ^= self.reg[0x17];
        var m = self.reg[0x15] & ~self.dma;
        while (m != 0) : (m &= m - 1) {
            const s: usize = @ctz(m);
            const b = bit(s);
            if (self.reg[1 + 2 * s] != @as(u8, @truncate(line))) continue;
            self.dma |= b;
            self.mcbase[s] = 0;
            if (self.reg[0x17] & b != 0) self.ff &= ~b;
        }
    }

    fn fetchAll(self: *Vic, mem: draw.Mem) void {
        self.shown = self.dma;
        self.abank = if (self.bank3) self.dma else 0;
        var m = self.dma;
        while (m != 0) : (m &= m - 1) {
            const s: usize = @ctz(m);
            self.mc[s] = self.mcbase[s];
            const base = @as(u16, self.ptr[s]) * 64 + self.mc[s];
            self.addr[s] = base;
            self.row[s] = mem.row(self.bank3, base, !self.vb);
            self.mc[s] += 3;
        }
    }
};

fn bit(s: usize) u8 {
    return @as(u8, 1) << @intCast(s);
}
