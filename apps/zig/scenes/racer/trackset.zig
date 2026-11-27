// --------------------------------------------------------------------------
// RACER: the track on show (M5 step 2). `tracks[0]` is the built-in oval; `tracks[1]` views the ONE
// track buffer (library.zig), which holds whichever file track was chosen last. Key t walks the library
// (oval, then the disk's files in its FAT order, then C:\RACER\'s), loading each into the buffer; a file
// the loader refuses is marked bad, named on the console and skipped, and the oval is the fallback.
// Driving, the race and the minimap are bound to one track at a time: a load first moves them to the
// oval (the buffer is about to change under them), then rebinds them. What a track looks like beyond its
// faces (far ground, sky, backdrop) and whether it can be raced is its file's mood block (trk.Mood).
// On every track but the oval the player is flown by the AI's controller (`Game.pilot`): the recorded
// button streams are the oval's.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const backdrop = @import("backdrop.zig");
const palette = @import("palette.zig");
const drive = @import("drive.zig");
const game = @import("game.zig");
const haze = @import("haze.zig");
const minimap = @import("minimap.zig");
const project = @import("project.zig");
const trk = @import("trk.zig");

pub fn slotOf(w: usize) usize {
    return if (w == 0) 0 else 1;
}

/// The track on show's look on both pages: its palette and mood (far ground, sky rows, backdrop colours, M6 the haze), its
/// backdrop strip.
pub fn look(d: anytype) void {
    for (0..2) |p| palette.install(&d.os.lfbs[p], d.cur(), groundLevel(d.cur()));
    const h = haze.build(d.os.lfbs[0].palette, d.cur(), project.shade);
    for (0..2) |p| haze.paint(d.os.lfbs[p].palette);
    if (h != .none) zg.Console.log("racer,haze,{s},{},{}", .{ @tagName(h), haze.used, 256 - haze.pool_lo });
    backdrop.select(d.cur().mood.backdrop);
}

/// The draw distance in force for the player (drive, race, the flyby): the player's, capped by the track's mood (a track
/// too heavy at R 8 on the board, M5 finish). The bench laps pin their own.
pub fn playR(d: anytype) u32 {
    const cap = d.cur().mood.draw_r;
    return if (cap != 0) @min(d.play_r, cap) else d.play_r;
}

/// The light of the far ground (palette index 4): the mood's, unless the debug shading (key i) lights the faces again.
pub fn groundLevel(t: *const trk.Track) u32 {
    return if (project.shade != 0) 4 else t.mood.ground_level;
}

/// Where a drive / race mode needs to be: not a benchmark-only track (the city), and lap v1's button stream is the oval's.
pub fn needsOval(t: *const trk.Track, w: usize, lap_v1: bool) bool {
    return t.mood.flags & trk.BENCH_ONLY != 0 or (lap_v1 and w != 0);
}

/// Library entry `w` on show: loaded (a file) and bound. Returns the entry actually shown: `w`, or the oval when `w` is refused.
pub fn show(d: anytype, w: usize, now: *const fn () u32) usize {
    if (w == 0) return bindTo(d, 0, now);
    toOval(d, now); // the buffer is about to change under driving, the race and the minimap
    const e = &d.lib.list[w];
    const t0 = now();
    d.tracks[1] = d.lib.load(w) catch |err| return refused(d, w, @errorName(err), now);
    zg.Console.log("racer,load,{s},{},{},{},{}", .{ e.label(), e.stored, e.raw, d.lib.blocks, now() -% t0 });
    if (d.tracks[1].mood.flags & trk.BENCH_ONLY != 0) return w; // nothing races here: driving stays on the oval
    return bindTo(d, w, now);
}

/// Library entry `w` on show (the Demo's setTrack): loaded, bound, its look installed, the lap script and the frame's caches reset.
pub fn setTrack(d: anytype, w: usize, now: *const fn () u32) void {
    d.which = show(d, w, now); // w, or the oval when the file is refused
    d.script = 0;
    d.f.seen_stamp = 0;
    @memset(d.f.seen, 0);
    for (d.f.cache.e) |*e| e.stamp = 0;
    cars(d);
    look(d);
    d.r = playR(d);
}

/// The cars for the track on show: its `<TRACK>.KCR`, the disk's `CAR.KCR`, or the built-in GT (cars.zig; the palette follows).
pub fn cars(d: anytype) void {
    d.lib.cars.forTrack(d.lib.list[d.which].label(), &d.lib.rej);
}

/// The next library entry after `w` that is not marked bad (the oval at the end of the list).
pub fn next(d: anytype, w: usize) usize {
    var i = w;
    for (0..d.lib.n) |_| {
        i = (i + 1) % d.lib.n;
        if (!d.lib.list[i].bad) return i;
    }
    return 0;
}

fn refused(d: anytype, w: usize, why: []const u8, now: *const fn () u32) usize {
    d.lib.list[w].bad = true;
    d.lib.list[w].why = why;
    zg.Console.log("racer,track,refused,{s},{s}", .{ d.lib.list[w].label(), why });
    return bindTo(d, 0, now);
}

fn toOval(d: anytype, now: *const fn () u32) void {
    _ = bindTo(d, 0, now);
}

fn bindTo(d: anytype, w: usize, now: *const fn () u32) usize {
    const t = &d.tracks[slotOf(w)];
    if (w == 0 and d.game.t == t) return 0; // already there: the race and the drive keep their state
    const g = game.Game.init(t, now) catch |err| return if (w == 0) @panic(@errorName(err)) else refused(d, w, @errorName(err), now);
    d.drive = drive.Drive.init(t);
    d.drive.now = now;
    const keep = d.game.s.fsm;
    d.game = g;
    d.game.pilot = w != 0; // the recorded button streams are the oval's
    if (keep.front()) d.game.s.fsm = keep; // a load from the title or the select keeps the screen (front.zig)
    d.game.s.records = d.recs[w]; // the session's records on this track
    d.map = minimap.Map.init(t);
    d.pmap = @import("hudpic.zig").fitMap(t);
    return w;
}
