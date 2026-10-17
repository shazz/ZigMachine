// --------------------------------------------------------------------------
// codef_fx's sum-of-sines, without an f64 sin in the frame. Every term is
// walked as a Q30 unit vector turned by a constant angle per column (four
// multiplies), the way an ST coder steps a sine through a table. Float is
// used when a term is prepared (init, or when the travel key changes) and for
// nothing else.
// --------------------------------------------------------------------------
const std = @import("std");

fn q30(v: f64) i32 {
    return @intFromFloat(@round(v * 1073741824.0));
}

pub const Step = struct {
    c: i32 = 0,
    s: i32 = 0,

    fn of(angle: f64) Step {
        return .{ .c = q30(@cos(angle)), .s = q30(@sin(angle)) };
    }
};

pub const Rotor = struct {
    c: i32 = 0,
    s: i32 = 0,

    pub fn turn(self: *Rotor, st: Step) void {
        const c: i64 = self.c;
        const s: i64 = self.s;
        const half: i64 = 1 << 29;
        self.c = @intCast((c * st.c - s * st.s + half) >> 30);
        self.s = @intCast((s * st.c + c * st.s + half) >> 30);
    }
};

/// codef_fx's `params` entry (value, amp, inc, offset) plus its integer state.
pub const Param = struct {
    value: f64, // starting phase
    amp: f64,
    inc: f64, // radians per column
    offset: f64, // radians per frame
    amp8: i32 = 0, // amp in Q8
    rot: Rotor = .{}, // the live phase
    col: Step = .{}, // one column
    letter: Step = .{}, // one letter (TILE columns)
    frame: Step = .{}, // offset - travel * inc
    frame_travel: f64 = std.math.nan(f64), // the travel `frame` was made for
};

pub const MAX_TERMS = 4;
pub const Walk = [MAX_TERMS]Rotor;

pub fn prepare(params: []Param, tile: f64) void {
    for (params) |*p| {
        p.amp8 = @intFromFloat(@round(p.amp * 256.0));
        p.rot = .{ .c = q30(@cos(p.value)), .s = q30(@sin(p.value)) };
        p.col = Step.of(p.inc);
        p.letter = Step.of(p.inc * tile);
        p.frame_travel = std.math.nan(f64);
    }
}

pub fn begin(params: []const Param) Walk {
    var w: Walk = undefined;
    for (params, 0..) |p, j| w[j] = p.rot;
    return w;
}

pub fn step(params: []const Param, w: *Walk, letter: bool) void {
    for (params, 0..) |p, j| w[j].turn(if (letter) p.letter else p.col);
}

/// Sum of amp * sin(value) in Q38.
pub fn sumQ38(params: []const Param, w: *const Walk) i64 {
    var acc: i64 = 0;
    for (params, 0..) |p, j| acc += @as(i64, w[j].s) * p.amp8;
    return acc;
}

/// round(sum): floor(x + 0.5), the rounding the lab's filters need.
pub fn roundQ38(acc: i64) i32 {
    return @intCast((acc + (1 << 37)) >> 38);
}

/// codef_fx's bookkeeping after the walk: value = old + offset - travel * inc.
/// The per-frame angle only changes when the travel does, so its sin/cos is
/// cached and the float runs on a key press, not in the frame.
pub fn advance(params: []Param, travel: f64) void {
    for (params) |*p| {
        if (p.frame_travel != travel) {
            p.frame = Step.of(p.offset - travel * p.inc);
            p.frame_travel = travel;
        }
        p.rot.turn(p.frame);
    }
}
