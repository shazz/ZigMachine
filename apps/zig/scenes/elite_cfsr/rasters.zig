// --------------------------------------------------------------------------
// The colour bars, as REAL rasters: three palette registers rewritten per
// scanline, never pixels. The original does it from a Timer B chain
// (BEAM_TIMER_B_1/2 and TIMER_B_1/2/3, TEXT $252/$44e/$618/$670/$698); here the
// same tables drive a copper, which is that chain's whole visible effect.
//
// THE TABLES ARE THE ORIGINAL'S, word for word (DATA $5e, $68, $72):
//   BEAM_RASTERS1  $100 $411 $732 $765 $000   colour 0, five lines under the logo
//   BEAM_RASTERS2  $765 $732 $411 $100 $000   colour 0, five lines under the band
//   RASTERS        60 words = 20 groups of three, colours 1 AND 8 together
//
// THE CADENCE. TIMER_B_1 reloads Timer B with 6, TIMER_B_2 with 1 and TIMER_B_3
// leaves it at 1, so a group is 8 scanlines and its three words land on the
// group's lines 0, 6 and 7. In every group the first and third word are equal,
// so what you see is seven lines of a base colour and ONE brighter (or, past the
// middle, darker) line — a 1-in-8 dither that carries the ramp from $011 up to
// $777 and back down, with a $700 accent in the last group.
//
// WHERE THEY SIT. The band bitmap starts at line 44 ($1b86 / 160), the 20 groups
// run 44..203 with it, and the two colour-0 bars bracket them: 39..43 above, and
// 201..205 below — which is PAST the 200-line screen and therefore lands in the
// BOTTOM BORDER, where colour 0 is all there is. That is why the borders are
// open here: on hardware the bar runs edge to edge and down into the border, and
// the demo's own screenshot shows it doing exactly that. The line at which the
// beam-synced bar starts is the one number the binary would not give up exactly
// (it depends on Timer B / HBL latency in cycles); 39 is the value that makes
// the top bar sit against the band and the bottom one fall where the screenshot
// has it.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");

const BEAM_RASTERS1 = [5]u16{ 0x100, 0x411, 0x732, 0x765, 0x000 };
const BEAM_RASTERS2 = [5]u16{ 0x765, 0x732, 0x411, 0x100, 0x000 };
const RASTERS = [60]u16{
    0x011, 0x122, 0x011, 0x122, 0x233, 0x122, 0x233, 0x344, 0x233,
    0x344, 0x455, 0x344, 0x455, 0x566, 0x455, 0x566, 0x677, 0x566,
    0x677, 0x777, 0x677, 0x777, 0x777, 0x777, 0x777, 0x777, 0x777,
    0x777, 0x777, 0x777, 0x777, 0x777, 0x777, 0x777, 0x777, 0x777,
    0x777, 0x677, 0x777, 0x677, 0x566, 0x677, 0x566, 0x455, 0x566,
    0x455, 0x344, 0x455, 0x344, 0x233, 0x344, 0x233, 0x122, 0x233,
    0x122, 0x011, 0x122, 0x011, 0x700, 0x011,
};

const GROUPS: usize = RASTERS.len / 3;
const GROUP_LINES: usize = 8;
// The five bar lines end where TIMER_B_1 takes the chain over (line 44), and the
// closing bar starts five lines past the last group's first line: Timer B is
// reloaded with 4 there and the handler then waits one HBL to sync.
const BAR1_TOP: usize = A.BAND_TOP - BEAM_RASTERS1.len; // 39
const BAR2_TOP: usize = A.BAND_TOP + (GROUPS - 1) * GROUP_LINES + 5; // 201

/// Slot 0 drives palette entry 0, slot 1 entry 1, slot 2 entry 8.
pub const SLOTS = [_]u8{ 0, A.INK_LO, A.INK_HI };

/// The three tables, one colour per PHYSICAL row. Scene-owned, as copper asks.
pub var tables: [SLOTS.len]zg.copper.Table = undefined;

/// Fill them once: nothing in this screen's rasters moves.
pub fn build(fb: *zg.LogicalFB) void {
    const bg = zg.copper.table(fb, 0);
    const lo = zg.copper.table(fb, 1);
    const hi = zg.copper.table(fb, 2);
    const black = A.stColor(0);
    // Above the band the VBL's movem of LOGO_PALETTE is all that has been
    // written, so 1 and 8 keep their OWN logo colours; from line 44 on TIMER_B_1
    // writes the same word to $ffff8242 and $ffff8250, and they move together.
    var lo_ink = fb.palette[A.INK_LO];
    var hi_ink = fb.palette[A.INK_HI];
    for (0..zg.PHYSICAL_HEIGHT) |row| {
        const line = @as(isize, @intCast(row)) - @as(isize, A.CONTENT_Y);
        bg[row] = barColor(line, black);
        if (line >= A.BAND_TOP) {
            lo_ink = groupColor(@intCast(line - A.BAND_TOP), lo_ink);
            hi_ink = lo_ink;
        }
        lo[row] = lo_ink;
        hi[row] = hi_ink;
    }
}

/// Colour 0: black except under the logo and under the band.
fn barColor(line: isize, black: u32) u32 {
    if (line >= BAR1_TOP and line < BAR1_TOP + BEAM_RASTERS1.len)
        return A.stColor(BEAM_RASTERS1[@intCast(line - BAR1_TOP)]);
    if (line >= BAR2_TOP and line < BAR2_TOP + BEAM_RASTERS2.len)
        return A.stColor(BEAM_RASTERS2[@intCast(line - BAR2_TOP)]);
    return black;
}

/// Colours 1 and 8 inside the band: base, base, base, base, base, base, accent,
/// base. Past the last group the register simply keeps what it was given.
fn groupColor(offset: usize, current: u32) u32 {
    const g = offset / GROUP_LINES;
    if (g >= GROUPS) return current;
    const rel = offset % GROUP_LINES;
    const i = 3 * g + switch (rel) {
        6 => @as(usize, 1),
        7 => 2,
        else => 0,
    };
    return A.stColor(RASTERS[i]);
}
