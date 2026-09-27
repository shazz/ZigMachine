// --------------------------------------------------------------------------
// ZIG mode's craters fill in. An enemy fighter that hits the ground (316)
// may leave a hole where it fell (920: a bit of the sector's ghx9 byte, the
// crater image 73 on its screen) and its wreck (930: a slot of the sector's
// wreck table, sno9 / so9 / snox). In the original they stay for the rest
// of the game. In ZIG, after zig_settings.crater_life_vbls, the sector's
// ground is put back exactly as it was before that crash: the bits the crash
// set cleared, the wreck slots it added taken off.
//
// This one IS gameplay (a gun bit is what 1030 stamps and 945 counts), so it
// is a setting, 0 = never, and the harness's logic check runs with it off.
// It waits while the sector is on screen: the screen, its zones and its
// sprites were drawn from the hole, and line 1000 redraws them only when the
// plane arrives. Off screen, the ring slot redraws by itself (the gun bits
// are part of its signature, zig_ring.zig). Every crash is recorded in both
// modes; only ZIG fills them in.
// --------------------------------------------------------------------------
const scr = @import("scr.zig");
const ring = @import("zig_ring.zig");
const hooks = @import("zig_hooks.zig");
const set = @import("zig_settings.zig");
const V = @import("vars.zig");
const v = &V.v;

const MAX = set.crater_max;
const Hole = struct {
    s: i32 = -1,
    made: u32 = 0,
    ghx: [2]i32 = .{ 0, 0 },
    sno: [2]i32 = .{ 0, 0 },
    so: [4]i32 = .{ 0, 0, 0, 0 },
    snox: [4]i32 = .{ 0, 0, 0, 0 },
};

var holes: [MAX]Hole = [_]Hole{.{}} ** MAX;
var open: ?usize = null;
var now: u32 = 0;
/// For the harness: holes made, and filled in.
pub var made: u32 = 0;
pub var filled: u32 = 0;

pub fn reset() void {
    holes = [_]Hole{.{}} ** MAX;
    open = null;
    now = 0;
    made = 0;
    filled = 0;
}

/// 316: a crash is about to make its hole in sector s.
pub fn before(s: i32) void {
    open = null;
    if (s < 0 or s >= ring.SECTORS) return;
    const i = free() orelse return;
    var h = Hole{ .s = s, .made = now };
    h.ghx[0] = scr.peek(v.ghx9 + s);
    h.sno[0] = scr.peek(v.sno9 + s);
    for (0..4) |k| {
        h.so[k] = scr.peek(v.so9 + s * 4 + @as(i32, @intCast(k)));
        h.snox[k] = v.snox_a[@intCast(s)][k];
    }
    holes[i] = h;
    open = i;
}

/// 316: the hole is made (920, 930).
pub fn after() void {
    const i = open orelse return;
    open = null;
    const h = &holes[i];
    h.ghx[1] = scr.peek(v.ghx9 + h.s);
    h.sno[1] = scr.peek(v.sno9 + h.s);
    made +%= 1;
}

fn free() ?usize {
    for (&holes, 0..) |*h, i| if (h.s < 0) return i;
    return null;
}

/// Every VBL.
pub fn tick() void {
    now +%= 1;
    const life = set.crater_life_vbls;
    // Only in flight: the title (tscreen 2350) parks sector 0's gun bits.
    if (!hooks.zig or life == 0 or !hooks.flightView()) return;
    for (&holes, 0..) |*h, i| {
        if (h.s < 0 or open == i or now -% h.made < life) continue;
        if (h.s == v.sx or h.s == hooks.live_sx) continue;
        fill(h);
    }
}

/// The sector's ground as it was before the crash.
fn fill(h: *Hole) void {
    const s = h.s;
    const g = scr.peek(v.ghx9 + s);
    scr.poke(v.ghx9 + s, g & ~(h.ghx[1] & ~h.ghx[0]));
    if (scr.peek(v.sno9 + s) == h.sno[1] and h.sno[1] > h.sno[0]) {
        scr.poke(v.sno9 + s, h.sno[0]);
        var k: usize = @intCast(h.sno[0]);
        while (k < @min(4, @as(usize, @intCast(h.sno[1])))) : (k += 1) {
            scr.poke(v.so9 + s * 4 + @as(i32, @intCast(k)), h.so[k]);
            v.snox_a[@intCast(s)][k] = h.snox[k];
        }
    }
    h.* = .{};
    filled +%= 1;
}
