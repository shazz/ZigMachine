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
/// ZX0 is ZigMachine's own cart-asset format rather than an ST one; its packer
/// is tools/zx0pack.
pub const zx0 = @import("zx0.zig");
/// What the screen does while a ZX0 asset unpacks: `depack_fx.Runner(@import("zigos"))`.
pub const depack_fx = @import("depack_fx.zig");
/// The TEX loader panel on its own (draw at a tween clock), for a screen that
/// shows one without a depack behind it (the Union Demo's demoloader.js page).
pub const tex_loader = @import("tex_loader.zig");

/// Is this ANY packed image we know how to open?
pub fn isPacked(src: []const u8) bool {
    return ice.isPacked(src) or zx0.isPacked(src);
}

/// What the image will depack to, or null if we do not recognise it.
pub fn depackedLen(src: []const u8) ?u32 {
    return ice.depackedLen(src) orelse zx0.depackedLen(src);
}

/// Depack with whichever depacker claims the image. Null when none does, the
/// destination is too small, or the stream is corrupt.
pub fn depack(src: []const u8, dst: []u8) ?u32 {
    if (ice.isPacked(src)) return ice.depack(src, dst);
    if (zx0.isPacked(src)) return zx0.depack(src, dst);
    return null;
}
