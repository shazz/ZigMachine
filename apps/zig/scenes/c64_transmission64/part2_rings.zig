// --------------------------------------------------------------------------
// Part 2's screen writers: the radio rings ($4700, from the IRQ) and the arc's colour copy
// ($4251 / $42E3, from the main loop), each store timed on the 6510's clock.
// --------------------------------------------------------------------------
const le = @import("data.zig");
const vic = @import("vic.zig");
const Clock = @import("clock.zig").Clock;

/// $4500-$4518 (low nibbles) and $4600-$4618 (high): the rings' colours, index 0 the centre.
pub const Colours = struct {
    lo: [25]u8 = .{0x04} ** 25,
    hi: [25]u8 = .{0x40} ** 25,

    /// $4391: every colour one ring out (x = 21..1), then the colour past the last ring takes
    /// the fade of the one before it. Only once: its loop's BNE jumps into the fade
    /// subroutine's middle ($43C1) and returns from there, so x = 4 is the only pass.
    pub fn shift(self: *Colours) void {
        var x: usize = 0x15;
        while (x > 0) : (x -= 1) {
            self.lo[x] = self.lo[x - 1];
            self.hi[x] = self.hi[x - 1];
        }
        self.lo[0x18] = fade(self.lo[0x17]);
        self.hi[0x18] = fade(self.hi[0x17]);
    }

    fn get(self: *const Colours, addr: u16) u8 {
        return switch (addr) {
            0x4500...0x4518 => self.lo[addr - 0x4500],
            0x4600...0x4618 => self.hi[addr - 0x4600],
            else => @panic("$4700 reads only $4500/$4600"), // the rip checks it
        };
    }
};

/// $43BA: white, yellow, cyan, light blue, purple; the same in the high nibble.
fn fade(c: u8) u8 {
    return switch (c) {
        0x0E => 0x04,
        0x03 => 0x0E,
        0x07 => 0x03,
        0x01 => 0x07,
        0xE0 => 0x40,
        0x30 => 0xE0,
        0x70 => 0x30,
        0x10 => 0x70,
        else => c,
    };
}

/// $4700, the generated ring painter: LDA/ORA/AND #/LDX abs and STA/STX abs, walked as the
/// ripped (opcode, lo, hi) list.
pub fn paint(col: *const Colours, start: Clock, st: *vic.Stores, prog: []const u8) void {
    var c = start;
    const n = le.le16(prog);
    var a: u8 = 0;
    var x: u8 = 0;
    for (0..n) |i| {
        const op = prog[2 + 3 * i ..][0..3];
        const addr = @as(u16, op[1]) | (@as(u16, op[2]) << 8);
        switch (op[0]) {
            0xAD => a = col.get(addr),
            0x0D => a |= col.get(addr),
            0xAE => x = col.get(addr),
            0x29 => a &= op[1],
            0x8D, 0x8E => {
                st.put(c.storeAbs(), addr, if (op[0] == 0x8D) a else x, addr >= 0xD800);
                continue;
            },
            else => @panic("$4700: an opcode the rip did not allow"),
        }
        c.rd(if (op[0] == 0x29) 2 else 4);
    }
}

/// $4251 (or $42E3): rows 10..19 of screen and colour RAM from the cycle's 256 colours `m`
/// through the maps ($7000 / $7200, 400 cells each). Returns the clock after the second loop.
/// The main loop runs it: the frame's IRQ can come at any instruction (Clock.inst).
pub fn copy(start: Clock, m: *const [256]u8, maps: []const u8, st: *vic.Stores, variant: u8) Clock {
    // $42AD's second loop branches from page $43 back to $42FC: its BNE takes a cycle more
    const back: u8 = if (variant == 1) 4 else 3;
    var c = start;
    instr(&c, 2); // LDX #0
    for (0..256) |x| { // LDY $7000,X ; LDA $7800,Y ; STA $0590,X ; LDY $7200,X ; ...
        const cell: u16 = @intCast(x);
        st.put(lookupStore(&c, 4), 0x0590 + cell, m[maps[x]], false);
        st.put(lookupStore(&c, 4), 0xD990 + cell, m[maps[0x200 + x]], true);
        instr(&c, 2); // INX
        instr(&c, if (x == 255) 2 else 3); // BNE
    }
    instr(&c, 2); // LDX #$90
    var x: usize = 0x90;
    while (x > 0) : (x -= 1) { // LDY $70FF,X crosses a page: 5 cycles
        const cell: u16 = @intCast(0x28F + x);
        st.put(lookupStore(&c, 5), 0x0400 + cell, m[maps[0xFF + x]], false);
        st.put(lookupStore(&c, 5), 0xD800 + cell, m[maps[0x2FF + x]], true);
        instr(&c, 2); // DEX
        instr(&c, if (x == 1) 2 else back); // BNE
    }
    return c;
}

/// An instruction of `n` read cycles.
fn instr(c: *Clock, n: u8) void {
    c.inst();
    c.rd(n);
}

/// LDY map,X (`ldy` cycles) ; LDA $7800,Y ; STA abs,X: returns the store's time.
fn lookupStore(c: *Clock, ldy: u8) u32 {
    instr(c, ldy);
    instr(c, 4); // LDA
    instr(c, 4); // STA abs,X: four cycles, then the write
    return c.wr();
}
