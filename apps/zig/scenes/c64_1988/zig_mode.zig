// --------------------------------------------------------------------------
// 1988's ZIG mode (Z toggles it; default off): the same intro, the way KESTREL would show it.
//
//   60 Hz motion  The C64 runs at 50 Hz, so the default shows C64 frame floor(5m/6) on machine
//                 frame m: every sixth frame repeats one and the motion judders. ZIG keeps the
//                 VIC model one C64 frame ahead and draws every machine frame between two C64
//                 frames: each sprite run (vic_runs.zig) of frame n+1 is moved back toward where
//                 the same sprite showed the same block in frame n by (6 - k)/6 of the way, k the
//                 sixths of a C64 frame machine frame m is past n. On k = 0 the picture is
//                 the C64's frame n exactly (apps/c64_1988_zig.mjs checks it against the default).
//   copper only   The border colour is the plane's colour 0 on EVERY line, borders opened by a
//                 FLICK on all 280 lines of its copper list: no HBL handler runs at all, global
//                 or plane (the default keeps the global one for the closed borders' colour and
//                 part 2's mid-line BEAM switch: ZIG draws that line in its starting colour).
//   CHISEL        every run of 128+ pixels a keyed blit from the expanded blocks in cart RAM.
// The VIC model runs in both modes (its writes, its state, its border colours), so Z back
// shows the default's frame, pixel for pixel, from the first C64 frame boundary on.
// --------------------------------------------------------------------------
const vic = @import("vic.zig");
const runs_mod = @import("vic_runs.zig");
const paint = @import("vic_paint.zig");
const groups_mod = @import("groups.zig");

const Run = runs_mod.Run;
const PAL_X = 504;

/// The cart's ZIG state, for the harness's reads (zig_api.zig).
pub var current: ?*const Zig = null;

/// One C64 frame's runs, with their sprites' runs found by sprite number.
pub const Frame = struct {
    buf: [runs_mod.MAX]Run = undefined, // by sprite number (counting sort), line order within
    n: usize = 0,
    start: [9]u16 = .{0} ** 9, // sprite s's runs are buf[start[s]..start[s + 1]]

    pub fn take(self: *Frame, r: *const runs_mod.Runs) void {
        var at = [_]u16{0} ** 9;
        for (r.buf[0..r.n]) |run| at[run.s + 1] += 1;
        for (1..9) |s| at[s] += at[s - 1];
        self.start = at;
        for (r.buf[0..r.n]) |run| {
            self.buf[at[run.s]] = run;
            at[run.s] += 1;
        }
        self.n = r.n;
    }

    pub fn runs(self: *const Frame) []const Run {
        return self.buf[0..self.n];
    }

    pub fn of(self: *const Frame, s: u8) []const Run {
        return self.buf[self.start[s]..self.start[s + 1]];
    }
};

pub const Zig = struct {
    on: bool = false,
    leaving: bool = false, // Z pressed again: back at the next C64 frame boundary
    a: Frame = .{}, // C64 frame show.frames - 1
    b: Frame = .{}, // C64 frame show.frames (the model's latest)
    spans: paint.Spans = .{}, // what ZIG drew last frame, to erase
    groups: groups_mod.Groups = .{}, // the colour groups it drew with
    ops: u32 = 0, // CHISEL ops last frame
    k: u8 = 0, // sixths of a C64 frame past `a` the last picture showed

    pub fn reset(self: *Zig) void {
        self.on = false;
        self.leaving = false;
        self.a.n = 0;
        self.b.n = 0;
        self.spans = .{};
        self.groups = .{};
        self.ops = 0;
        self.k = 0;
    }

    /// Take the model's runs of the C64 frame it just ran.
    pub fn stepped(self: *Zig, out: *const vic.Out) void {
        self.a = self.b;
        self.b.take(&out.runs);
    }

    /// Machine frame m's picture: C64 frame n exactly (k = 0, `which` says if that is a or b),
    /// or a moved k/6 of the way from frame a to frame b.
    pub fn draw(self: *Zig, base: paint.Pen, k: u8, exact_b: bool) void {
        var pen = base;
        pen.spans = &self.spans;
        pen.groups = &self.groups;
        self.groups.reset();
        self.spans.erase(pen.pix);
        self.k = k;
        self.ops = 0;
        if (k == 0) {
            self.ops = paint.all(pen, if (exact_b) self.b.runs() else self.a.runs());
            return;
        }
        var s: u8 = 8;
        while (s > 0) {
            s -= 1;
            for (self.b.of(s)) |*run| {
                const d = self.motion(run);
                self.ops += paint.one(pen, run, -share(d[0], k), -share(d[1], k));
            }
        }
    }

    // Where frame a showed this run's block (same sprite, same block, its top nearest):
    // (rows, columns) from there to here, 0 if frame a did not show it.
    fn motion(self: *const Zig, run: *const Run) [2]i32 {
        const top = blockTop(run);
        var best: ?[2]i32 = null;
        var cost: i32 = 64;
        for (self.a.of(run.s)) |*p| {
            if (p.block() != run.block() or p.bit(25) != run.bit(25)) continue;
            const dr = top - blockTop(p);
            var dc = @as(i32, run.col()) - @as(i32, p.col());
            if (dc > PAL_X / 2) dc -= PAL_X else if (dc < -PAL_X / 2) dc += PAL_X;
            const cst = abs(dr) + abs(dc);
            if (abs(dr) <= 24 and abs(dc) <= 32 and cst < cost) {
                cost = cst;
                best = .{ dr, dc };
            }
        }
        return best orelse .{ 0, 0 };
    }
};

// The plane row of the run's block's row 0: where the block would start.
fn blockTop(run: *const Run) i32 {
    return @as(i32, run.r0) - @as(i32, run.row0());
}

// What is left of a move `d` (frame a to frame b) at k sixths of the way: d * (6 - k) / 6, rounded.
fn share(d: i32, k: u8) i32 {
    const v = d * (6 - @as(i32, k));
    return if (v >= 0) @divTrunc(v + 3, 6) else -@divTrunc(-v + 3, 6);
}

fn abs(v: i32) i32 {
    return if (v < 0) -v else v;
}
