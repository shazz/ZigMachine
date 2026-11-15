//! zigdemo palfx: a demo's global palette effect driven by a TRACK. A step track of (row, id) keys
//! picks an effect id when its value CHANGES (a `rearm` value selects nothing: it only lets the same
//! id be selected again); the id indexes the demo's table of `Def`s; the effect then steps once a VBL
//! (`vbl_hz`, the original machine's rate) from the row it was selected at:
//!   fade_in   from black / white to the palette, +amount a VBL (level 0 .. 256), then plain
//!   fade_out  from the palette to black / white, -amount a VBL, then holds
//!   flash     additive, amount - decay * n, then plain (the add is that value's LOW byte, as an
//!             8-bit add does it: a flash of 256 starts at 0)
//!   add       +amount, constant until the next selection
//! It is a FUNCTION of the song time (at), not a state stepped a frame, so a seek lands on the right
//! level at once. The cart applies the effect to its palettes (apply: free on KESTREL's palette
//! registers) or, over a part that owns its palettes, as ONE alpha plane of one colour (veil: exact for
//! the fades, a flash approximated as a white veil). Integers only; no imports.

pub const Mode = enum { plain, black, white, add };

/// The effect now: black/white at level (256 = the palette, 0 = all black / white), or add.
pub const Effect = struct {
    mode: Mode = .plain,
    level: u16 = 256,
    add: u8 = 0,

    pub fn eql(a: Effect, b: Effect) bool {
        return a.mode == b.mode and a.level == b.level and a.add == b.add;
    }
};

pub const Kind = enum { none, fade_in, fade_out, flash, add };

/// One entry of the demo's id table. `toward` is .black or .white (fades only).
pub const Def = struct { kind: Kind = .none, toward: Mode = .black, amount: u16 = 0 };

pub const Config = struct {
    rows_per_s: u32, // the track's row rate (e.g. a Rocket track at 18 rows/s)
    vbl_hz: u32 = 50, // the rate the effect steps at
    decay: u32 = 4, // a flash's fall a VBL
    rearm: i32 = -1, // a key value that selects nothing
    first: i32 = 0, // the id in effect before any selection
    max_vbl: u32 = 100_000, // steps are capped (every effect has settled long before)
};

/// The effect at song ms `t`: the last selection at or before t, stepped by the VBLs since.
pub fn at(comptime cfg: Config, keys: []const [2]i32, defs: []const Def, t: u32) Effect {
    var last: i32 = cfg.rearm;
    var id: i32 = cfg.first;
    var row0: u32 = 0;
    for (keys) |k| {
        const r: u32 = @intCast(k[0]);
        if (@as(u64, r) * 1000 > @as(u64, t) * cfg.rows_per_s) break; // t * rows_per_s / 1000 < r
        if (k[1] != last) {
            last = k[1];
            if (k[1] != cfg.rearm) {
                id = k[1];
                row0 = r;
            }
        }
    }
    // the VBLs since the selection: the frame that crossed row0 is VBL 0
    const t0: u64 = (@as(u64, row0) * 1000 + cfg.rows_per_s - 1) / cfg.rows_per_s;
    const n: u32 = @intCast(@min(cfg.max_vbl, (@as(u64, t) -| t0) * cfg.vbl_hz / 1000));
    if (id < 0 or id >= defs.len) return .{};
    return effect(cfg, defs[@intCast(id)], n);
}

/// Effect `d` n VBLs after its selection.
pub fn effect(comptime cfg: Config, d: Def, n: u32) Effect {
    return switch (d.kind) {
        .none => .{},
        .fade_in => fadeIn(d.toward, d.amount, n),
        .fade_out => fadeOut(d.toward, d.amount, n),
        .flash => flash(d.amount, cfg.decay, n),
        .add => .{ .mode = .add, .add = @truncate(d.amount) },
    };
}

fn fadeIn(m: Mode, step: u32, n: u32) Effect {
    const l = step * n;
    if (l >= 256) return .{};
    return .{ .mode = m, .level = @intCast(l) };
}
fn fadeOut(m: Mode, step: u32, n: u32) Effect {
    return .{ .mode = m, .level = @intCast(256 -| @min(256, step * n)) };
}
fn flash(a0: u32, decay: u32, n: u32) Effect {
    if (decay * n > a0) return .{};
    return .{ .mode = .add, .add = @truncate(a0 - decay * n) };
}

/// One channel through the effect.
pub fn apply(e: Effect, c: u8) u8 {
    const cv: u32 = c;
    return switch (e.mode) {
        .plain => c,
        .black => @intCast(cv * e.level >> 8),
        .white => @intCast((cv * e.level >> 8) + (255 * (256 - @as(u32, e.level)) >> 8)),
        .add => @intCast(@min(255, cv + e.add)),
    };
}

/// The overlay plane's one colour for a part that owns its palettes: (r, g, b, alpha).
pub fn veil(e: Effect) [4]u8 {
    return switch (e.mode) {
        .plain => .{ 0, 0, 0, 0 },
        .black => .{ 0, 0, 0, @intCast(255 - (@as(u32, e.level) * 255 >> 8)) },
        .white => .{ 255, 255, 255, @intCast(255 - (@as(u32, e.level) * 255 >> 8)) },
        .add => .{ 255, 255, 255, e.add },
    };
}
