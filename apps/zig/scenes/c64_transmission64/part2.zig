// --------------------------------------------------------------------------
// Part 2 ($4000; IRQ $4175 on line 248): the Transmission64 logo, a multicolour bitmap, its
// radio rings and its rainbow arc coloured by rewriting screen and colour RAM.
//
// The logo is drawn all in purple ($44 everywhere): what makes it appear is colour.
//   IRQ, every frame: the music; a frame counter ($8240); the generated routine $4700 (561
//     stores) paints the radio rings around the antenna from 25 colours ($4500, low nibble,
//     and $4600, high) in the cells each ring covers; every 6th frame $434F shifts those
//     colours one ring out ($4391; the outermost one fades 1-7-3-E-4 instead) and, when the
//     tune's $0C1E reads $B2 or $A0 (the second time, then every other time), feeds the
//     centre 8 flash colours ($43F2) instead of purple; $41FE sets the antenna sprite's
//     shared colours from the tune's $0C22. From frame $076A the IRQ only shifts; from $0838
//     it stops.
//   Main loop: 16 times, $421B / $42AD build 256 colours from a 16-byte window of $7900 and
//     write them through the maps $7000/$7200 into rows 10..19's screen and colour RAM: the
//     arc's bands appear, then (from $7980) fade. The copy loops run ~200 lines, through the
//     frame's IRQ, racing the beam.
// What depends on the tune or the drive is measured in VICE (data.zig: the IRQ times, the
// music flags, the frames the main loop gets to its copies); the rest is the code's logic.
// --------------------------------------------------------------------------
const vic = @import("vic.zig");
const Clock = @import("clock.zig").Clock;
const data = @import("data.zig");
const rings = @import("part2_rings.zig");

pub const LATE = 0x076A; // $8240: from here the IRQ only shifts the ring colours
pub const STOP = 0x0838; // ...and from here not even that
pub const SPRITE_Y = 0x89; // the antenna sprite, set up when the logo is drawn

pub const Part2 = struct {
    col: rings.Colours = .{},
    cnt: u16 = 0, // $8240/$8241
    d7: u8 = 6, // $41D7: frames to the next shift
    flash: u8 = 0, // $4350: 2 while the centre flashes
    trig: u8 = 1, // $4362: tune triggers to the next flash
    step: u8 = 0, // $436E: the flash's step
    next_cycle: usize = 0,
    off: [2]u8 = .{ 0x00, 0x80 }, // $4220 / $42B2: each variant's window into $7900

    pub fn init(d: data.Part2) Part2 {
        var p = Part2{};
        const a = d.arrays();
        @memcpy(&p.col.lo, a[0..25]);
        @memcpy(&p.col.hi, a[25..50]);
        return p;
    }

    /// $4175 for frame `n` (no IRQ when the drive command held them off).
    pub fn irq(self: *Part2, n: u32, q: *vic.Queue, st: *vic.Stores, d: data.Part2) void {
        const i = d.irq(n) orelse return;
        self.cnt +%= 1;
        rings.paint(&self.col, Clock.atTime(i.prog, false), st, d.program());
        if (self.cnt < STOP) {
            self.d7 -= 1;
            if (self.d7 == 0) {
                self.d7 = 6;
                if (self.cnt < LATE) self.flashStep(i.flags & 1 != 0, d.arrays()[50..58]);
                self.col.shift();
            }
        }
        if (self.cnt >= LATE) return;
        const music = i.flags & 2 != 0; // $41FE: the antenna's colours follow the tune
        q.at(0, i.rti - 40, 0x25, if (music) 0x07 else 0x01);
        q.at(0, i.rti - 34, 0x26, if (music) 0x0E else 0x03);
    }

    // $434F: a flash runs 8 shifts long; one starts on the tune's second trigger, then every other.
    fn flashStep(self: *Part2, trigger: bool, table: []const u8) void {
        if (self.flash == 0) {
            if (!trigger) return;
            self.trig -= 1;
            if (self.trig != 0) return;
            self.flash = 2;
            self.trig = 2;
        }
        self.col.lo[0] = table[self.step] & 0x0F;
        self.col.hi[0] = table[self.step] & 0xF0;
        self.step += 1;
        if (self.step == 8) {
            self.step = 0;
            self.flash = 0;
        }
    }

    /// The main loop's colour cycle due in frame `n`, if any: its copy loops, timed.
    pub fn mainLoop(self: *Part2, n: u32, q: *vic.Queue, st: *vic.Stores, d: data.Part2) void {
        const c = d.cycle(self.next_cycle) orelse return;
        if (c.frame != n) return;
        self.next_cycle += 1;
        var m: [256]u8 = undefined;
        const tbl = d.cycleTable()[self.off[c.variant]..][0..16];
        for (0..256) |x| m[x] = (tbl[x & 15] & 0x0F) | (tbl[x >> 4] << 4);
        self.off[c.variant] +%= 0x10;
        var clk = Clock.atTime(c.start, true);
        clk.spr_first = SPRITE_Y; // the antenna (sprite 0, Y $89) fetches on lines $89..$9D
        clk.spr_last = SPRITE_Y + 20;
        if (d.irq(n)) |i| {
            clk.irq_at = i.entry - 7;
            clk.irq_end = i.rti;
        }
        clk = rings.copy(clk, &m, d.maps(), st, c.variant);
        if (c.variant == 0) return;
        clk.inst();
        clk.rd(4); // LDY #7 ; LDA $7800,Y
        clk.rd(2);
        q.at(0, clk.storeAbs(), 0x25, m[7]);
        clk.inst();
        clk.rd(6);
        q.at(0, clk.storeAbs(), 0x26, m[0x0E]);
    }
};
