// --------------------------------------------------------------------------
// MPEG audio Layer III frame headers, for the MP3 player (mp3.zig): pvmp3
// wants exactly one whole frame a call, so the player frames its input ring
// itself. Also skips an ID3v2 tag. Pure: tested natively (mp3_frame_test.zig).
// --------------------------------------------------------------------------

pub const Header = struct {
    len: u32, // the frame's bytes, header included
    rate: u32, // Hz
    channels: u32, // 1 or 2
};

const KBPS = [2][15]u16{
    .{ 0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320 }, // MPEG-1
    .{ 0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160 }, // MPEG-2 / 2.5
};
const RATES = [3]u32{ 44100, 48000, 32000 };

/// The longest frame: MPEG-1 320 kbps at 32 kHz, padded.
pub const MAX_LEN: u32 = 144 * 320_000 / 32_000 + 1;

/// The Layer III header at h[0..4], or null (not a sync, another layer, a free or bad bitrate,
/// a reserved rate). One divide a frame.
pub fn parse(h: [4]u8) ?Header {
    if (h[0] != 0xFF or (h[1] & 0xE6) != 0xE2) return null; // sync, Layer III
    const ver: u32 = (h[1] >> 3) & 3; // 3 MPEG-1, 2 MPEG-2, 0 MPEG-2.5
    const bi: u32 = h[2] >> 4;
    const si: u32 = (h[2] >> 2) & 3;
    if (ver == 1 or bi == 0 or bi == 15 or si == 3) return null;
    const lsf: u32 = @intFromBool(ver != 3);
    const rate = RATES[si] >> @intCast(if (ver == 3) 0 else if (ver == 2) @as(u32, 1) else 2);
    const pad: u32 = (h[2] >> 1) & 1;
    const per: u32 = if (lsf == 1) 72_000 else 144_000;
    return .{
        .len = per * KBPS[lsf][bi] / rate + pad,
        .rate = rate,
        .channels = if ((h[3] >> 6) == 3) 1 else 2,
    };
}

/// The bytes of an ID3v2 tag at the start of `b` (header + size, footer included), else 0.
pub fn id3Len(b: []const u8) u32 {
    if (b.len < 10 or b[0] != 'I' or b[1] != 'D' or b[2] != '3') return 0;
    const size: u32 = (@as(u32, b[6] & 0x7F) << 21) | (@as(u32, b[7] & 0x7F) << 14) |
        (@as(u32, b[8] & 0x7F) << 7) | (b[9] & 0x7F);
    return 10 + size + (if (b[5] & 0x10 != 0) @as(u32, 10) else 0);
}
