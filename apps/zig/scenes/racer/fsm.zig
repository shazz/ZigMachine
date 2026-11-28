// --------------------------------------------------------------------------
// RACER: the race's state machine, table driven: grid (the cars on their slots, waiting for the
// start), countdown (3, 2, 1: 90 ticks, every car held), race (the clock runs, the rules judge the
// player), finish (the player is done, the AI cars run on until they all finish or the cap),
// results (the standings), and back to the grid. M5 step 4 adds the front end: title (the attract
// flyby under the logo) and select (the track list), and the edges in and out of a race:
// title -enter-> select -pick-> grid; results -enter-> select (another track); results -back->
// title; select -back-> title; grid -back-> select. The M5 finish adds the options screen, reached
// from the title or the select (-options->) and left for either: options -back-> title, options
// -enter-> select (front.zig fires the one it came from). An event that is not in the table is
// refused and the state does not change. The board batch adds the car select, `garage`: select -car-> garage
// -pick-> grid, garage -back-> select (the track is loaded on the way in, the car chosen there). `restart` is legal from every race state but the grid (it
// is the abort key, and the results' "again"). New states and events are appended, so the old ones
// keep their numbers. No ZigOS import.
// --------------------------------------------------------------------------
pub const State = enum(u8) { grid, countdown, race, finish, results, title, select, options, garage };
pub const Event = enum(u8) { start, go, finish, done, restart, enter, pick, back, options, car };
pub const NSTATE = 9;
pub const NEVENT = 10;
pub const Error = error{IllegalTransition};

/// TABLE[state][event]: the next state, or null when the event is illegal in that state.
pub const TABLE = [NSTATE][NEVENT]?State{
    //   start       go     finish   done      restart enter    pick   back    options   car
    .{ .countdown, null, null, null, null, null, null, .select, null, null }, // grid
    .{ null, .race, null, null, .grid, null, null, null, null, null }, // countdown
    .{ null, null, .finish, null, .grid, null, null, null, null, null }, // race
    .{ null, null, null, .results, .grid, null, null, null, null, null }, // finish
    .{ null, null, null, null, .grid, .select, null, .title, null, null }, // results
    .{ null, null, null, null, null, .select, null, null, .options, null }, // title
    .{ null, null, null, null, null, null, .grid, .title, .options, .garage }, // select
    .{ null, null, null, null, null, .select, null, .title, null, null }, // options
    .{ null, null, null, null, null, null, .grid, .select, null, null }, // garage (board batch: the car select)
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

    /// The front end's states: no race runs in them.
    pub fn front(self: *const Fsm) bool {
        return self.state == .title or self.state == .select or self.state == .options or self.state == .garage;
    }

    pub fn name(s: State) []const u8 {
        return @tagName(s);
    }
};
