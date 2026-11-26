// --------------------------------------------------------------------------
// RACER: best lap and best race of this session, in RAM only (ticks, 0 = none yet). The original
// keeps a track record with `dset`; whether a cart may write a file is the open question Q6, so
// nothing here touches storage: when Q6 is answered, `load` / `save` bind to a file here and the
// rest of the cart does not change. A race's total is only comparable at the same length, so the
// best race is kept per lap count (M5 finish: the options screen's 1, 3 or 5). No ZigOS import.
// --------------------------------------------------------------------------
pub const MAX_LAPS = 5; // rules.MAX_LAPS

pub const Records = struct {
    best_lap: u32 = 0,
    best_races: [MAX_LAPS + 1]u32 = .{0} ** (MAX_LAPS + 1), // by lap count

    /// True when `t` is a new best lap.
    pub fn offerLap(self: *Records, t: u32) bool {
        return offer(&self.best_lap, t);
    }

    /// True when `t` is a new best race (total time) over `laps` laps.
    pub fn offerRace(self: *Records, t: u32, laps: u32) bool {
        return offer(&self.best_races[@min(laps, MAX_LAPS)], t);
    }

    pub fn bestRace(self: *const Records, laps: u32) u32 {
        return self.best_races[@min(laps, MAX_LAPS)];
    }
};

fn offer(best: *u32, t: u32) bool {
    if (t == 0 or (best.* != 0 and t >= best.*)) return false;
    best.* = t;
    return true;
}
