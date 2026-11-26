// --------------------------------------------------------------------------
// RACER: the front end's moves between screens (front.zig has the keys and the screens): the FSM
// event each move fires, what the game does around it, the options screen's rows, the select's
// cursor and pick. Works on the same Demo as front.zig.
// --------------------------------------------------------------------------
const fsm = @import("fsm.zig");
const options = @import("options.zig");

pub fn fire(d: anytype, ev: fsm.Event) bool {
    d.game.s.fsm.fire(ev) catch return false; // WHY: an event the table refuses leaves the screen as it is
    return true;
}

/// Results / grid / title -> the select: the game leaves its race (its session keeps the FSM's new state).
pub fn toSelect(d: anytype, ev: fsm.Event) bool {
    if (!fire(d, ev)) return false;
    d.game.toFront();
    d.front.cursor = d.which;
    d.front.msg = "";
    return true;
}

pub fn toTitle(d: anytype) bool {
    if (!fire(d, .back)) return false;
    d.game.toFront();
    return true;
}

pub fn toOptions(d: anytype, from_title: bool) bool {
    if (!fire(d, .options)) return false;
    d.front.opt_from_title = from_title;
    d.front.row = .laps;
    return true;
}

/// BACK: the screen the options were opened from (options -back-> title, options -enter-> select).
pub fn leaveOptions(d: anytype) bool {
    return fire(d, if (d.front.opt_from_title) .back else .enter);
}

pub fn optFire(d: anytype) bool {
    if (d.front.row == .back) return leaveOptions(d);
    options.change(d, d.front.row, 1);
    return true;
}

pub fn optInput(d: anytype, dir: u8) void {
    const f = &d.front;
    const n: u8 = options.ROWS;
    switch (dir) {
        0 => f.row = @enumFromInt((@intFromEnum(f.row) + n - 1) % n),
        1 => f.row = @enumFromInt((@intFromEnum(f.row) + 1) % n),
        2 => options.change(d, f.row, -1),
        3 => options.change(d, f.row, 1),
        5 => _ = optFire(d),
        else => {},
    }
}

/// The cursor `step` entries on (mod the list). Nothing is loaded: the select shows the scan's preview (preview.zig).
pub fn move(d: anytype, step: usize) void {
    d.front.cursor = (d.front.cursor + step) % d.lib.n;
    d.front.msg = "";
}

/// Fire on the select: the cursor's track loaded (only now) and raced, or the reason it cannot be.
pub fn pick(d: anytype) bool {
    const f = &d.front;
    if (d.lib.list[f.cursor].bad) return refuse(f, "REFUSED FILE");
    if (d.lib.preview(f.cursor).bench_only) return refuse(f, "NO RACE HERE");
    if (f.cursor != d.which) d.setTrack(f.cursor); // a refusal here (a file that passed the scan) marks it bad
    if (f.cursor != d.which) return refuse(f, "REFUSED FILE");
    if (!fire(d, .pick)) return false;
    d.setGame(.race); // a fresh session on the grid: the state pick leads to
    return true;
}

pub fn refuse(f: anytype, why: []const u8) bool {
    f.msg = why;
    return true;
}
