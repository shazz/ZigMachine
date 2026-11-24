// --------------------------------------------------------------------------
// RACER: best lap and best race of this session, in RAM only (ticks, 0 = none yet). The original
// keeps a track record with `dset`; whether a cart may write a file is the open question Q6, so
// nothing here touches storage: when Q6 is answered, `load` / `save` bind to a file here and the
// rest of the cart does not change. No ZigOS import.
// --------------------------------------------------------------------------
pub const Records = struct {
    best_lap: u32 = 0,
    best_race: u32 = 0,

    /// True when `t` is a new best lap.
    pub fn offerLap(self: *Records, t: u32) bool {
        return offer(&self.best_lap, t);
    }

    /// True when `t` is a new best race (total time).
    pub fn offerRace(self: *Records, t: u32) bool {
        return offer(&self.best_race, t);
    }
};

fn offer(best: *u32, t: u32) bool {
    if (t == 0 or (best.* != 0 and t >= best.*)) return false;
    best.* = t;
    return true;
}
