// --------------------------------------------------------------------------
// The ProTracker .MOD header: parsed and CHECKED before a note is played.
//
// The player (mod.zig) sequences four channels. A 6CHN / 8CHN / 32CH file has
// the same header but 6-32 cells a row, so read as four it plays garbage in
// time -- a silent wrong tune, the worst kind of failure. So only the
// four-channel 31-sample tags load: "M.K.", "M!K!", "4CHN", "FLT4". Anything
// else is REFUSED with a reason (the host reports it and counts it).
//
// Pure: no chip, no allocation. Tested natively (mod_format_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");

pub const NUM_CH: usize = 4;
pub const TAG_OFFSET: usize = 1080;
/// Header, 31 sample headers, the order list and the tag.
pub const HEADER_LEN: usize = 1084;
pub const PATTERN_BYTES: u32 = 64 * NUM_CH * 4;
pub const TAGS = [_]*const [4]u8{ "M.K.", "M!K!", "4CHN", "FLT4" };

pub const Error = error{
    /// Shorter than the 1084-byte header.
    TooShort,
    /// The tag at 1080 is not one of TAGS (6CHN, 8CHN, CD81, a 15-sample file...).
    NotFourChannel,
    /// The song length byte is 0 or over 128 (the order list's size).
    BadSongLength,
};

/// The host's numbering of the reasons (audioModError): 0 = loaded.
pub fn code(e: Error) u32 {
    return switch (e) {
        error.TooShort => 1,
        error.NotFourChannel => 2,
        error.BadSongLength => 3,
    };
}

pub const SampleHdr = struct {
    start: u32 = 0, // byte offset into the MOD image of the PCM data
    len: u32 = 0, // in bytes
    loop_start: u32 = 0, // in bytes
    loop_len: u32 = 0, // in bytes
    volume: u8 = 0, // 0..64
    finetune: i8 = 0,
};

pub const Header = struct {
    samples: [32]SampleHdr = [_]SampleHdr{.{}} ** 32, // 1-based; [0] unused
    song_len: u8 = 0,
    order: [128]u8 = [_]u8{0} ** 128,
    pattern_data: u32 = HEADER_LEN, // byte offset where patterns start
    num_patterns: u16 = 0,
};

fn rd16(data: []const u8, off: usize) u16 {
    return (@as(u16, data[off]) << 8) | data[off + 1];
}

pub fn isFourChannel(data: []const u8) bool {
    if (data.len < HEADER_LEN) return false;
    const tag = data[TAG_OFFSET..][0..4];
    for (TAGS) |t| if (std.mem.eql(u8, tag, t)) return true;
    return false;
}

pub fn parse(data: []const u8) Error!Header {
    if (data.len < HEADER_LEN) return error.TooShort;
    if (!isFourChannel(data)) return error.NotFourChannel;
    var h: Header = .{};
    h.song_len = data[950];
    if (h.song_len == 0 or h.song_len > 128) return error.BadSongLength;
    for (1..32) |i| {
        const base = 20 + (i - 1) * 30;
        const s = &h.samples[i];
        s.len = @as(u32, rd16(data, base + 22)) * 2;
        const ft: u4 = @truncate(data[base + 24] & 0x0F);
        s.finetune = @as(i4, @bitCast(ft));
        s.volume = data[base + 25];
        s.loop_start = @as(u32, rd16(data, base + 26)) * 2;
        s.loop_len = @as(u32, rd16(data, base + 28)) * 2;
    }
    var max_pat: u16 = 0;
    for (0..128) |i| {
        h.order[i] = data[952 + i];
        max_pat = @max(max_pat, h.order[i]);
    }
    h.num_patterns = max_pat + 1;
    // PCM data follows the patterns: each sample's start in turn.
    var pcm: u32 = h.pattern_data + @as(u32, h.num_patterns) * PATTERN_BYTES;
    for (1..32) |i| {
        h.samples[i].start = pcm;
        pcm += h.samples[i].len;
    }
    return h;
}

/// The channel that plays the fewest notes over the song (each order entry
/// counted as often as it is played; the lowest channel wins a tie). A sound
/// effect borrows it (sfx_voice.zig): the tune misses the least there.
pub fn quietChannel(h: *const Header, data: []const u8) u8 {
    var notes = [_]u32{0} ** NUM_CH;
    for (h.order[0..h.song_len]) |pat| {
        const base = h.pattern_data + @as(u32, pat) * PATTERN_BYTES;
        for (0..64 * NUM_CH) |cell| {
            const o = base + @as(u32, @intCast(cell)) * 4;
            if (o + 1 >= data.len) break;
            if ((@as(u16, data[o] & 0x0F) << 8 | data[o + 1]) != 0) notes[cell % NUM_CH] += 1;
        }
    }
    var best: u8 = 0;
    for (notes, 0..) |n, c| {
        if (n < notes[best]) best = @intCast(c);
    }
    return best;
}
