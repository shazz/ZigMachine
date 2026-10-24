// --------------------------------------------------------------------------
// Newschool colour grading: a part's 256-entry palette as 16 texel levels
// (its ramp) x 16 light levels, plus the two accents every part shares:
//   - the CUT: each part opens on a white flash fading out over FLASH ticks
//     and closes by burning to white over the last BURN ticks, so parts are
//     joined by a flash on the timeline;
//   - the BEAT: app.zig's YM probe (a channel volume jumping) lifts the light
//     for a few frames. It is 0 headless: an accent, never the structure.
// --------------------------------------------------------------------------
pub const FLASH: u32 = 24;
pub const BURN: u32 = 12;

/// 0..3, from app.zig's pulse().
pub var beat: u8 = 0;

/// White amount 0..16 at local tick lt of a part `len` ticks long.
pub fn flash(lt: u32, len: u32) u32 {
    if (lt < FLASH) return (FLASH - lt) * 16 / FLASH;
    if (lt + BURN >= len) return @min(16, (lt + BURN - len + 1) * 16 / BURN);
    return 0;
}

/// Extra forward motion on the beat (0 headless).
pub fn surge(lt: u32) u32 {
    return @as(u32, beat) * (lt & 3);
}

/// One STE colour lit by (light+1)/16 plus the beat, mixed toward white by white/16.
pub fn lit(rgb: *const [3]u8, light: u32, white: u32) u32 {
    var c: u32 = 0xFF00_0000;
    for (0..3) |g| {
        const base: u32 = @as(u32, rgb[g]) * 17 * (light + 1 + @as(u32, beat) * 2) / 16;
        const v: u32 = @min(base, 255);
        c |= (v + (255 - v) * white / 16) << @intCast(8 * g);
    }
    return c;
}

/// pal[light << 4 | level] = ramp[level] lit by (light+1)/16, lifted by the
/// beat, then mixed toward white by white/16.
pub fn build(pal: [*]u32, ramp: *const [16][3]u8, white: u32) void {
    const lift: u32 = @as(u32, beat) * 2;
    for (0..16) |light| for (0..16) |level| {
        var c: u32 = 0xFF00_0000;
        for (0..3) |g| {
            const base: u32 = @as(u32, ramp[level][g]) * 17 * (@as(u32, @intCast(light)) + 1 + lift) / 16;
            const clip: u32 = @min(base, 255);
            const v = clip + (255 - clip) * white / 16;
            c |= v << @intCast(8 * g);
        }
        pal[light << 4 | level] = c;
    };
}
