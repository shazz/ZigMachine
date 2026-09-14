// --------------------------------------------------------------------------
// Pathchain: sprites strung along ONE ripped path, each a fixed number of
// steps behind the one before it.
//
// The CurveRipper idiom of the Union Demo remake (screens/beatdis/screen2.js:
// 162-166) and many ST intros: two coordinate tables, a step counter t, and
// sprite i drawn at table[(t - i*lag) % len]. In JS a sprite whose index is
// still negative reads `undefined`, and drawImage at NaN draws nothing, so the
// chain enters one sprite at a time: sprite i appears on step i*lag. `at`
// keeps that, answering null until then.
//
// No ZigOS import: it tests natively (pathchain_test.zig).
// --------------------------------------------------------------------------

pub fn Point(comptime T: type) type {
    return struct { x: T, y: T };
}

/// Sprite `i`'s position at step `t`, `lag` steps a sprite behind: the path's
/// point (t - i*lag) mod its length, or null while that is still negative (or
/// the path is empty). `ys` must be at least as long as `xs`, whose length is
/// the path's (the JS takes both indices modulo spritePosX.length).
pub fn at(comptime T: type, xs: []const T, ys: []const T, t: u32, i: u32, lag: u32) ?Point(T) {
    const n = index(t, i, lag, xs.len) orelse return null;
    if (n >= ys.len) return null;
    return .{ .x = xs[n], .y = ys[n] };
}

/// The table index behind `at`.
pub fn index(t: u32, i: u32, lag: u32, len: usize) ?usize {
    const behind = @as(u64, i) * lag;
    if (len == 0 or t < behind) return null;
    return @intCast((t - behind) % len);
}
