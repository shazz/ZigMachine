// --------------------------------------------------------------------------
// The block container every BAD APPLE!! stream shares (spans "BASP", tiles "BATL", polygons "BAPO"):
// a 16-byte header <magic, w, h, fps, total frames, blocks, gop>, then per block <u32 packed, u32 raw,
// u16 frames> and the ZX0! container of the raw block. Pure Zig (native tests in decoder_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");

pub const WIDTH: u16 = 320;
pub const HEIGHT: u16 = 200;
pub const HEADER_SIZE: usize = 16;
pub const BLOCK_HDR_SIZE: usize = 10;

pub const Header = struct {
    width: u16,
    height: u16,
    fps: u16,
    total_frames: u16,
    block_count: u16,
    gop_frames: u16,
};

pub const BlockHeader = struct {
    packed_len: u32,
    raw_len: u32,
    frame_count: u16,
};

pub fn readU16Le(b: *const [2]u8) u16 {
    return @as(u16, b[0]) | (@as(u16, b[1]) << 8);
}

pub fn readU32Le(b: *const [4]u8) u32 {
    return @as(u32, b[0]) | (@as(u32, b[1]) << 8) | (@as(u32, b[2]) << 16) | (@as(u32, b[3]) << 24);
}

/// The header of a stream with this magic; null for another magic, a short header or not 320x200.
pub fn parseHeader(data: []const u8, magic: *const [4]u8) ?Header {
    if (data.len < HEADER_SIZE) return null;
    if (!std.mem.eql(u8, data[0..4], magic)) return null;
    const h: Header = .{
        .width = readU16Le(data[4..6]),
        .height = readU16Le(data[6..8]),
        .fps = readU16Le(data[8..10]),
        .total_frames = readU16Le(data[10..12]),
        .block_count = readU16Le(data[12..14]),
        .gop_frames = readU16Le(data[14..16]),
    };
    // The decoders are 320x200 only; a stream that says otherwise is refused, never painted skewed.
    if (h.width != WIDTH or h.height != HEIGHT or h.fps == 0 or h.gop_frames == 0) return null;
    return h;
}

pub fn parseBlockHeader(data: []const u8) ?BlockHeader {
    if (data.len < BLOCK_HDR_SIZE) return null;
    const b: BlockHeader = .{
        .packed_len = readU32Le(data[0..4]),
        .raw_len = readU32Le(data[4..8]),
        .frame_count = readU16Le(data[8..10]),
    };
    if (b.frame_count == 0) return null;
    return b;
}
