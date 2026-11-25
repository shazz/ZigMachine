// --------------------------------------------------------------------------
// AURORA BOOT: the star plane's playback. The baker computed every frame: each star's pixel and level
// (flight, swirl, twinkle), the falcon's projected vertices (Q4 pixels) and three scalars. A record is
// REC i16: sx[N] sy[N] lv[N] vx[NV] vy[NV] line word fade, stored as the DIFFERENCE from the previous
// record, so the cart keeps one running record and adds the next delta. A 60 Hz frame between two records
// shows the midpoint (the running record + half of the next delta). No 3D, no float, no trig here.
// --------------------------------------------------------------------------
const meta = @import("aurora_art").meta;
const plot = @import("plot.zig");
const look = @import("look.zig");

const N = meta.N_STARS;
const NV = meta.NV;
pub const LINE_AT = 3 * N + 2 * NV; // index of the scalars in a record

pub const Player = struct {
    deltas: []const i16, // STAR_FRAMES x REC
    cur: [meta.REC]i16 = [_]i16{0} ** meta.REC,
    applied: i32 = -1, // the record `cur` holds

    /// Bring `cur` to record `rec` (advancing one record at a time; a replay re-starts from -1).
    pub fn seek(self: *Player, rec: u32) void {
        while (self.applied < @as(i32, @intCast(rec))) {
            self.applied += 1;
            const d = self.deltas[@as(usize, @intCast(self.applied)) * meta.REC ..][0..meta.REC];
            for (&self.cur, d) |*c, v| c.* +%= v;
        }
    }

    pub fn restart(self: *Player) void {
        self.cur = [_]i16{0} ** meta.REC;
        self.applied = -1;
    }

    /// Element k at this frame: the record, plus half of the next delta on an odd 60 Hz frame.
    fn at(self: *const Player, k: usize, odd: bool) i32 {
        const base: i32 = self.cur[k];
        if (!odd) return base;
        const next: usize = @intCast(self.applied + 1);
        if (next >= meta.STAR_FRAMES) return base;
        return base + (@as(i32, self.deltas[next * meta.REC + k]) >> 1);
    }

    pub fn scalar(self: *const Player, k: usize) u32 {
        return @intCast(self.cur[LINE_AT + k]);
    }

    /// Draw the falcon's wire, the stars and the glints into the cleared star plane.
    pub fn draw(self: *const Player, plane: [*]u8, odd: bool) void {
        if (self.scalar(0) > 0) self.wire(plane, odd);
        for (0..N) |k| {
            if (self.cur[2 * N + k] & 16 == 0) continue;
            plot.cross(plane, self.at(k, odd), self.at(N + k, odd), look.GLINT);
        }
        for (0..N) |k| {
            const lv: u8 = @intCast(self.cur[2 * N + k] & 15);
            if (lv != 0) plot.put(plane, self.at(k, odd), self.at(N + k, odd), lv);
        }
    }

    fn wire(self: *const Player, plane: [*]u8, odd: bool) void {
        for (meta.EDGES) |e| {
            const a: usize = 3 * N + e[0];
            const b: usize = 3 * N + e[1];
            plot.line(plane, self.at(a, odd), self.at(a + NV, odd), self.at(b, odd), self.at(b + NV, odd), look.LINE);
        }
    }
};
