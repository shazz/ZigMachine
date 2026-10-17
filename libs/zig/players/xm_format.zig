// --------------------------------------------------------------------------
// The FastTracker 2 .XM header: parsed and CHECKED before a note is played.
//
// Only the header and the layout arithmetic live here; the patterns
// (xm_pattern.zig) and the instruments + samples (xm_instr.zig) are read
// from the offsets this header gives. The refusals are the ones that would
// otherwise play a silent wrong tune: a channel count the mixer cannot hold,
// a version this layout does not describe, a file cut short. Pure: no chip,
// no allocation. Tested natively (xm_format_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");

/// The twelve voices: xm_chip.zig mixes them onto the four Paula channels, two to a
/// channel up to 8 channels and three to a channel above that.
pub const MAX_CH: usize = 12;
pub const MAX_PATTERNS: usize = 256;
pub const MAX_INSTRUMENTS: usize = 128;
pub const MAX_SAMPLES: usize = 256;
pub const MAX_ROWS: u16 = 256;
pub const MAGIC = "Extended Module: ";
const HDR_BASE: usize = 60; // the header-size field's own offset; hdr_size counts from here
const ORDER_OFF: usize = 80;

pub const Error = error{
    /// Shorter than the fixed part of the header.
    TooShort,
    /// The "Extended Module: " signature and the 0x1A are not there.
    NotXm,
    /// A version before 1.02: its layout is not the one read here.
    BadVersion,
    /// The header size is out of the file, or too small to hold the order table.
    BadHeaderSize,
    /// 0 or more than MAX_CH channels: more voices than the mixer has.
    TooManyChannels,
    /// 0 or more songs than the order table holds.
    BadSongLength,
    /// A speed of 0 ticks a row, or a BPM under 32: not a tempo the sequencer can keep.
    BadTempo,
    /// More patterns than MAX_PATTERNS.
    TooManyPatterns,
    /// More instruments than MAX_INSTRUMENTS.
    TooManyInstruments,
    /// More samples than MAX_SAMPLES, over all the instruments.
    TooManySamples,
    /// A pattern header that is not packing type 0, or has 0 or too many rows.
    BadPattern,
    /// A pattern, instrument or sample runs past the end of the file.
    Truncated,
    /// An instrument header that is too small for what it declares, a field out of
    /// range (a note map entry, a loop outside its sample, over 12 envelope points).
    BadInstrument,
    /// The song's order list names a pattern the file does not hold.
    BadOrder,
    /// Too big for the song RAM beside the mixer's buffers (xm_chip.BUF_OFFSET).
    TooLarge,
};

/// The host's numbering of the reasons (audioXmError): 0 = loaded.
pub fn code(e: Error) u32 {
    return switch (e) {
        error.TooShort => 1,
        error.NotXm => 2,
        error.BadVersion => 3,
        error.BadHeaderSize => 4,
        error.TooManyChannels => 5,
        error.BadSongLength => 6,
        error.TooManyPatterns => 7,
        error.TooManyInstruments => 8,
        error.TooManySamples => 9,
        error.BadPattern => 10,
        error.Truncated => 11,
        error.BadTempo => 12,
        error.BadInstrument => 13,
        error.BadOrder => 14,
        error.TooLarge => 15,
    };
}

pub const Header = struct {
    version: u16 = 0,
    song_len: u16 = 0,
    restart: u16 = 0,
    channels: u8 = 0,
    num_patterns: u16 = 0,
    num_instruments: u16 = 0,
    /// Flags bit 0: the linear frequency table (else Amiga).
    linear: bool = false,
    speed: u8 = 6, // ticks per row
    bpm: u8 = 125,
    orders: [256]u8 = undefined, // filled by parse() (all 256; only song_len are used)
    /// Byte offset of the first pattern: the header size counted from byte 60.
    pattern_data: u32 = 0,
};

pub fn rd16(data: []const u8, off: usize) u16 {
    return @as(u16, data[off]) | (@as(u16, data[off + 1]) << 8);
}

pub fn rd32(data: []const u8, off: usize) u32 {
    return @as(u32, rd16(data, off)) | (@as(u32, rd16(data, off + 2)) << 16);
}

pub fn parse(data: []const u8) Error!Header {
    if (data.len < ORDER_OFF + 256) return error.TooShort;
    if (!std.mem.eql(u8, data[0..MAGIC.len], MAGIC) or data[37] != 0x1A) return error.NotXm;
    var h: Header = .{};
    h.version = rd16(data, 58);
    if (h.version < 0x0102) return error.BadVersion;
    const hdr_size = rd32(data, HDR_BASE);
    if (hdr_size < 20 or hdr_size > 0x1000) return error.BadHeaderSize;
    h.pattern_data = @as(u32, HDR_BASE) + hdr_size;
    h.song_len = rd16(data, 64);
    h.restart = rd16(data, 66);
    h.channels = @intCast(rd16(data, 68));
    h.num_patterns = rd16(data, 70);
    h.num_instruments = rd16(data, 72);
    h.linear = rd16(data, 74) & 1 != 0;
    h.speed = @intCast(rd16(data, 76));
    h.bpm = @intCast(rd16(data, 78));
    if (h.channels == 0 or h.channels > MAX_CH) return error.TooManyChannels;
    if (h.song_len == 0 or h.song_len > 256) return error.BadSongLength;
    if (h.num_patterns > MAX_PATTERNS) return error.TooManyPatterns;
    if (h.num_instruments > MAX_INSTRUMENTS) return error.TooManyInstruments;
    if (h.speed == 0 or h.bpm < 32) return error.BadTempo;
    @memcpy(h.orders[0..], data[ORDER_OFF..][0..256]);
    for (h.orders[0..h.song_len]) |o| if (o >= h.num_patterns) return error.BadOrder;
    return h;
}
