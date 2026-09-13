// --------------------------------------------------------------------------
// Palette: scale colours from a BASE palette by a factor.
//
// CODEF fades an image by drawing it with a canvas alpha. On a paletted plane
// over black the same composite is the palette's RGB scaled by that alpha, so
// half a dozen ports hand-wrote the loop below, each with its own rounding and
// its own rule for the alpha byte. The two things that matter:
//   - scale from the BASE colours every frame, never from what is already in
//     the palette, or the fade compounds;
//   - rounding is part of the look: CODEF ports truncate (`@intFromFloat`),
//     cuddly_starwars rounds. It is an option, not a choice made here.
//
// Pure functions over `anytype` planes (anything with `setPaletteEntry(u8, C)`)
// and colours (anything with u8 `r g b a`), so it has no ZigOS import and tests
// natively (palette_test.zig). The float type of `k` is the scene's: f32 and f64
// round differently at .5 boundaries.
// --------------------------------------------------------------------------

pub const Rounding = enum { trunc, round };

pub const Alpha = union(enum) {
    /// Keep the base colour's alpha.
    keep,
    /// Write this alpha on every scaled entry (255: fully opaque).
    set: u8,
};

pub const Options = struct {
    rounding: Rounding = .trunc,
    alpha: Alpha = .keep,
};

/// `c` with its RGB scaled by `k`, clamped to [0, 1].
pub fn scale(c: anytype, k: anytype, opts: Options) @TypeOf(c) {
    const F = @TypeOf(k);
    if (@typeInfo(F) != .float) @compileError("palette: k must be a runtime f32 or f64 (write @as(f32, 0.5)); the float type is part of the look");
    // @min/@max drop a NaN operand, so a NaN k clamps to 1 and never reaches @intFromFloat.
    const kk: F = @max(0, @min(1, k));
    var out = c;
    out.r = channel(F, c.r, kk, opts.rounding);
    out.g = channel(F, c.g, kk, opts.rounding);
    out.b = channel(F, c.b, kk, opts.rounding);
    out.a = switch (opts.alpha) {
        .keep => c.a,
        .set => |a| a,
    };
    return out;
}

/// Write entries `lo..=hi` of `fb` as `base[i]` scaled by `k`. `base` needs at
/// least `hi + 1` entries (not bounds-checked in ReleaseSmall). `lo > hi` writes nothing.
pub fn scaleRange(fb: anytype, base: anytype, lo: u8, hi: u8, k: anytype, opts: Options) void {
    var i: usize = lo;
    while (i <= hi) : (i += 1) {
        fb.setPaletteEntry(@intCast(i), scale(base[i], k, opts));
    }
}

/// Write each entry named in `entries` as `base[entry]` scaled by `k`, for
/// palettes whose faded colours are not one contiguous range.
pub fn scaleEntries(fb: anytype, base: anytype, entries: []const u8, k: anytype, opts: Options) void {
    for (entries) |e| fb.setPaletteEntry(e, scale(base[e], k, opts));
}

fn channel(comptime F: type, v: u8, k: F, rounding: Rounding) u8 {
    const x = @as(F, @floatFromInt(v)) * k;
    return @intFromFloat(switch (rounding) {
        .trunc => x,
        .round => @round(x),
    });
}
