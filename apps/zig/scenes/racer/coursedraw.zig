// --------------------------------------------------------------------------
// RACER: the course select's turning model on the plane (board batch, item 9): coursemesh.zig's polygons for the cursor's
// track pushed into the frame with their depth keys, sorted and filled by the race's painter (CPU spans or AFFINE). The
// model's ramps go on palette entries 16.. of the page drawn (no 3D track is drawn under a menu frame: those entries are
// free while the select shows; nav.pick and front.update put the track's look back when it goes).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const cm = @import("coursemesh.zig");
const palette = @import("palette.zig");
const project = @import("project.zig");
const types = @import("types.zig");
const menu = @import("menu.zig");

pub const TURN_STEP: u32 = 0x0010_0000; // a turn in 4,096 frames: ~68 s at 60 fps
pub var polys: []cm.Poly = &.{}; // carved at init (setup.zig): no zero-filled static
pub var break_still = false; // racer_batch.mjs --break turn (key *): the model never turns

/// The model's colours on the page about to be drawn.
fn install(fb: *zg.LogicalFB, m: *const cm.Mesh) void {
    for (m.ramps[0..m.nr], 0..) |rgb, k| {
        for (0..8) |l| fb.palette[16 + k * 8 + l] = zg.linepal.rgb(palette.lit(rgb[0], l), palette.lit(rgb[1], l), palette.lit(rgb[2], l));
    }
}

fn push(d: anytype, ps: []const cm.Poly) void {
    for (ps) |q| {
        var r: types.Rec = undefined;
        r.n = 4;
        r.c = q.colour;
        for (0..4) |i| {
            r.x[i] = q.x[i] * 16; // the painter's coordinates are Q4 (xform.zig)
            r.y[i] = q.y[i] * 16;
        }
        const key: u16 = @intCast(1023 - @min(@max((q.depth - 15000) >> 5, 0), 1023)); // depths 15,000..47,000: far to near
        _ = project.push(&d.f, r, key);
    }
}

/// Mesh `m` turned `frames` frames into the screen, drawn into `fb` (the select's background, before its panels).
pub fn draw(d: anytype, fb: *zg.LogicalFB, m: *const cm.Mesh, frames: u32) void {
    if (m.nr == 0 or polys.len < cm.MAXP) return;
    install(fb, m);
    d.f.list = &.{};
    d.f.stats = .{};
    const v = @import("cam.zig").view(.{ .pos = .{ 0, 0, 0 }, .yaw = 0, .pitch = 0 });
    d.f.collect(d.cur(), &v, false); // nothing collected (an empty list): the counts zeroed
    const turn = if (break_still) 0 else frames *% TURN_STEP;
    const cells = cm.polys(m, turn, polys[0..cm.MAXP]);
    push(d, cells);
    push(d, cm.ribbon(m, turn, menu.HILITE, polys[cells.len..]));
    d.f.sort();
    _ = d.p.fill(fb, &d.f);
}
