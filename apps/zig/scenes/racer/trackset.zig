// --------------------------------------------------------------------------
// RACER: the cart's track set: the oval and the stress city, plus the three LOCAL Virtua Racing tracks with -Dracer_vr (vr.zig).
// Driving, the race and the minimap are bound to one track at a time (the oval, or the VR track on show): `bind` re-creates them
// when the track changes. On a VR track the player is flown by the AI's controller (`Game.pilot`), because the recorded button
// streams are the oval's, so the race benchmark (x) runs there too.
// --------------------------------------------------------------------------
const data = @import("data.zig");
const drive = @import("drive.zig");
const game = @import("game.zig");
const minimap = @import("minimap.zig");
const trk = @import("trk.zig");
const vr = @import("vr.zig");

// A VR build DROPS the city (755 KB of the cart's 2 MiB window; the three VR tracks are 1.29 MB, the base cart has 546 KB free):
// the tracks are then oval, VR1, VR2, VR3 and key t cycles them. Without the option: oval, city, as ever.
pub const NT = (if (vr.on) 1 else 2) + vr.blobs.len;
pub const BLOBS = (if (vr.on) [_][]align(4) const u8{data.oval} else [_][]align(4) const u8{ data.oval, data.city }) ++ vr.blobs;
pub const NAMES = (if (vr.on) [_][]const u8{"OVAL"} else [_][]const u8{ "OVAL", "CITY" }) ++ vr.names[0..vr.blobs.len].*;
const FIRST_VR: usize = if (vr.on) 1 else 2;

/// The ramp the ground beyond the draw distance takes: grass, plaza, and each VR track's own ground colour.
pub fn groundRamp(w: usize) usize {
    return switch (w) {
        0 => 1,
        else => if (isCity(w)) 8 else vr.GROUND_RAMP,
    };
}

pub fn isVr(w: usize) bool {
    return w >= FIRST_VR;
}

pub fn isCity(w: usize) bool {
    return !vr.on and w == 1;
}

/// Where a drive / race mode needs to be: not the city (no racing line); lap v1's button stream is the oval's.
pub fn needsOval(w: usize, lap_v1: bool) bool {
    return isCity(w) or (lap_v1 and isVr(w));
}

/// Parse every blob (a bad one panics at init, as before) and return the largest vertex and face counts the frame buffers must hold.
pub fn parseAll(tracks: *[NT]trk.Track) [2]usize {
    var nv: usize = 0;
    var nf: usize = 0;
    for (BLOBS, tracks) |b, *t| {
        t.* = trk.parse(b) catch |e| @panic(@errorName(e));
        nv = @max(nv, t.verts.len);
        nf = @max(nf, t.faces.len);
    }
    return .{ nv, nf };
}

/// Point driving, the race and the minimap at track `w` (a no-op for the city, and when they already are).
pub fn bind(d: anytype, w: usize, now: *const fn () u32) void {
    const t = &d.tracks[w];
    if (isCity(w) or d.game.t == t) return;
    d.drive = drive.Drive.init(t);
    d.drive.now = now;
    d.game = game.Game.init(t, now) catch |e| @panic(@errorName(e));
    d.game.pilot = isVr(w);
    d.map = minimap.Map.init(t);
}
