// --------------------------------------------------------------------------
// Beam: queue mid-line colour-0 writes for the line the global HBL is on
// (HW 1.6.0 BEAM). On an ST this is a run of cycle-counted move.w's to $FF8240
// while the beam crosses the line; here the handler lists them, and the machine
// paints the line in spans once the handler returns, then empties the list.
//
//     fn hbl(_: *zg.ZigOS, line: u16) void {
//         zg.beam.begin();
//         zg.beam.write(40, 0x700); // red from the visible window's left edge
//         zg.beam.write(360, 0x000); // black again at the right border
//     }
//
// x is in PHYSICAL low-res pixels (0 = the left edge of the left border,
// 0..399). The machine snaps it down to 4, keeps a write only if it is 8 px or
// more after the last one kept, and takes 64 a line; it counts every write it
// refuses in REG_BEAM_DROPPED (dropped()). Nothing here pre-filters, so a scene
// that breaks the 68000's limits is told, not quietly corrected.
//
// Generic over the register access so it has no ZigOS import and tests natively
// (beam_test.zig). zigos.zig instantiates it as `zg.beam`. No state of its own:
// the list lives in the machine's registers.
// --------------------------------------------------------------------------

pub const Layout = struct {
    count: usize, // REG_BEAM_COUNT (u16)
    dropped: usize, // REG_BEAM_DROPPED (u32)
    table: usize, // OFF_BEAM_TABLE (max x u32)
    max: usize, // BEAM_MAX
};

/// `HW` needs `r16`, `w16`, `r32`, `w32` (offset from the video region base).
pub fn Beam(comptime HW: type, comptime l: Layout) type {
    return struct {
        pub const MAX = l.max;

        /// Start this line's list afresh.
        pub fn begin() void {
            HW.w16(l.count, 0);
        }

        /// Colour 0 becomes ST/STE word `st` from physical pixel `x` on. Past
        /// MAX the write has no slot, but COUNT still grows, so the machine
        /// counts it as dropped.
        pub fn write(x: u16, st: u16) void {
            const n = HW.r16(l.count);
            if (n < l.max) HW.w32(l.table + @as(usize, n) * 4, (@as(u32, x) << 16) | st);
            HW.w16(l.count, n +| 1);
        }

        /// A row of equal cells: `colours[i]` from x0 + i * w.
        pub fn cells(x0: u16, w: u16, colours: []const u16) void {
            for (colours, 0..) |c, i| write(x0 +% @as(u16, @intCast(i)) *% w, c);
        }

        /// Writes queued for this line so far.
        pub fn queued() u16 {
            return HW.r16(l.count);
        }

        /// Writes the machine has refused since the last clearDropped().
        pub fn dropped() u32 {
            return HW.r32(l.dropped);
        }

        pub fn clearDropped() void {
            HW.w32(l.dropped, 0);
        }
    };
}
