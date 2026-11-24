// --------------------------------------------------------------------------
// RACER: the race's state machine, table driven: grid (the cars on their slots, waiting for the
// start), countdown (3, 2, 1: 90 ticks, every car held), race (the clock runs, the rules judge the
// player), finish (the player is done, the AI cars run on until they all finish or the cap),
// results (the standings), and back to the grid. An event that is not in the table is refused and
// the state does not change. `restart` is legal from every state but the grid (it is the abort
// key, and the results' "again"). No ZigOS import.
// --------------------------------------------------------------------------
pub const State = enum(u8) { grid, countdown, race, finish, results };
pub const Event = enum(u8) { start, go, finish, done, restart };
pub const NSTATE = 5;
pub const NEVENT = 5;
pub const Error = error{IllegalTransition};

/// TABLE[state][event]: the next state, or null when the event is illegal in that state.
pub const TABLE = [NSTATE][NEVENT]?State{
    //            start        go           finish     done      restart
    .{ .countdown, null, null, null, null }, // grid
    .{ null, .race, null, null, .grid }, // countdown
    .{ null, null, .finish, null, .grid }, // race
    .{ null, null, null, .results, .grid }, // finish
    .{ null, null, null, null, .grid }, // results
};

pub const Fsm = struct {
    state: State = .grid,
    ticks: u32 = 0, // ticks spent in the state

    pub fn next(self: *const Fsm, ev: Event) ?State {
        return TABLE[@intFromEnum(self.state)][@intFromEnum(ev)];
    }

    pub fn fire(self: *Fsm, ev: Event) Error!void {
        const to = self.next(ev) orelse return error.IllegalTransition;
        self.state = to;
        self.ticks = 0;
    }

    /// Count one tick in the current state.
    pub fn tick(self: *Fsm) void {
        self.ticks += 1;
    }

    pub fn name(s: State) []const u8 {
        return @tagName(s);
    }
};
