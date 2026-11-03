// --------------------------------------------------------------------------
// The gallery: the pictures, their three modes, the packed blobs and the
// converter's colour counts, and the sizes every switch reuses (the depack
// buffer, the copper lists' VRAM table), taken once at init.
// --------------------------------------------------------------------------
const std = @import("std");
const blob = @import("blob.zig");

const DIR = "../../assets/screens/mpp_truecolor/";

pub const Mode = struct { kind: blob.Kind, title: []const u8 };
pub const MODES = [_]Mode{
    .{ .kind = .indexed, .title = "1 GLOBAL: ONE 256-COLOUR PALETTE" },
    .{ .kind = .indexed, .title = "2 PER-LINE: 256 COLOURS EACH LINE" },
    // Until HW 1.15.0: 4 planes of 255 per-line colours (lossless, four FRESCO passes a line).
    .{ .kind = .rgb565, .title = "3 TRUE COLOUR: ONE RGB565 PLANE" },
};

// In the converter's PICTURES order; the packed blobs are [picture][mode].
pub const NAMES = [_][]const u8{ "SPHERES", "PARROT", "SUNSET", "HALO", "HILLS" };
pub const PACKED: [NAMES.len][MODES.len][]const u8 = @import("packed_assets").mpp_truecolor;

// p<P>_counts.bin: source, mode 1, mode 2, mode 3 distinct colours in the image area
// (then the source's hash, which only the headless harness reads).
const COUNTS = blk: {
    var c: [NAMES.len][]const u8 = undefined;
    for (&c, 0..) |*f, p| f.* = @embedFile(DIR ++ std.fmt.comptimePrint("p{d}_counts.bin", .{p}));
    break :blk c;
};
pub fn count(picture: usize, i: usize) u32 {
    return std.mem.readInt(u32, COUNTS[picture][i * 4 ..][0..4], .little);
}

/// The largest blob once depacked and widened: the one buffer every switch reuses.
pub fn workLen() ?usize {
    var most: usize = 0;
    for (PACKED) |modes| for (modes, MODES) |image, m| {
        most = @max(most, blob.need(image, m.kind) orelse return null);
    };
    return most;
}

/// The largest palette of any blob: the VRAM table every switch reuses.
pub fn mostColours() ?usize {
    var most: usize = 0;
    for (PACKED) |modes| for (modes, MODES) |image, m| {
        most = @max(most, blob.paletteWords(image, m.kind) orelse return null);
    };
    return most;
}
