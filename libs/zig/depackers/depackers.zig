// Aggregator for the ZigOS depackers — the root of the `depackers` module.
//
// ST files arrive crunched more often than not, and depacking one is the
// machine's own job (it is what a real ST does at load time), so these are a
// runtime library rather than a build-time tool. Each depacker is pure: it
// takes the packed bytes and a destination, and answers null rather than
// half-doing the job.
//
// Adding one: match the shape of ice.zig — `isPacked`, `depackedLen`, `depack`
// — and list it here.
pub const ice = @import("ice.zig");

/// Is this ANY packed image we know how to open?
pub fn isPacked(src: []const u8) bool {
    return ice.isPacked(src);
}

/// What the image will depack to, or null if we do not recognise it.
pub fn depackedLen(src: []const u8) ?u32 {
    return ice.depackedLen(src);
}

/// Depack with whichever depacker claims the image. Null when none does, the
/// destination is too small, or the stream is corrupt.
pub fn depack(src: []const u8, dst: []u8) ?u32 {
    if (ice.isPacked(src)) return ice.depack(src, dst);
    return null;
}
