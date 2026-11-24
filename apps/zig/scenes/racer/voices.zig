// --------------------------------------------------------------------------
// RACER: the effects' two FM voices (M4), written once when the cart takes its channels (audio.zig):
// FM 6 the engine note, FM 5 the impact. Register values as the YM2612 has them (zg.bard.fm.Patch).
// --------------------------------------------------------------------------
const fm = @import("zigos").bard.fm;

/// The engine: algorithm 4 (two pairs), a growl of feedback, held while keyed.
pub const ENGINE = fm.Patch{ .fb_alg = 5 << 3 | 4, .ops = .{
    .{ .dt_mul = 0x01, .tl = 30, .ks_ar = 31, .sl_rr = 0x0F },
    .{ .dt_mul = 0x01, .tl = 22, .ks_ar = 31, .sl_rr = 0x0F },
    .{ .dt_mul = 0x02, .tl = 28, .ks_ar = 31, .sl_rr = 0x0F },
    .{ .dt_mul = 0x01, .tl = 24, .ks_ar = 31, .sl_rr = 0x0F },
} };
/// The impact: a serial chain with full feedback, low, decaying in ~0.2 s.
pub const IMPACT = fm.Patch{ .fb_alg = 7 << 3 | 0, .ops = .{
    .{ .dt_mul = 0x03, .tl = 20, .ks_ar = 31, .am_dr = 14, .sl_rr = 0xFF },
    .{ .dt_mul = 0x01, .tl = 28, .ks_ar = 31, .am_dr = 12, .sl_rr = 0xFF },
    .{ .dt_mul = 0x05, .tl = 30, .ks_ar = 31, .am_dr = 12, .sl_rr = 0xFF },
    .{ .dt_mul = 0x01, .tl = 6, .ks_ar = 31, .am_dr = 16, .sl_rr = 0xFF },
} };
