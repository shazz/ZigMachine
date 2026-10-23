// --------------------------------------------------------------------------
// The REFERENCE picture, as the cart drew it before the chunky compositor:
// the 4-plane decode of the planar Clock's screen (the Go's Pixels) and the
// two opaque 80-wide sprite rectangles over it (ImageSlots), verbatim, with
// the meters applied first as present() did. chunky_test.zig runs it beside
// the live path; testapi.zig steps a planar Clock beside the live one so the
// harness keeps comparing the Go's 32000-byte screen with its model.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");
const clockmod = @import("clock.zig");
const metermod = @import("meter.zig");

const W: usize = 320;
const H: usize = 200;

pub fn present(clock: *clockmod.Clock, regs: [14]u8, px: *[W * H]u8) void {
    metermod.apply(clock.screen[0..], regs);
    const scr = clock.screen[0..];
    var group: usize = 0;
    while (group < 4000) : (group += 1) {
        const at = group * 8;
        const p0 = assets.beWord(scr, at);
        const p1 = assets.beWord(scr, at + 2);
        const p2 = assets.beWord(scr, at + 4);
        const p3 = assets.beWord(scr, at + 6);
        var x: usize = 0;
        while (x < 16) : (x += 1) {
            const shift: u4 = @intCast(15 - x);
            const v: u8 = @intCast(((p0 >> shift) & 1) |
                (((p1 >> shift) & 1) << 1) |
                (((p2 >> shift) & 1) << 2) |
                (((p3 >> shift) & 1) << 3));
            px[group * 16 + x] = v;
        }
    }
    drawSprite(px, assets.sprite_a, assets.sprite_a_w, assets.sprite_a_h, clock.poses[0], clock.tick, false);
    drawSprite(px, assets.sprite_b, assets.sprite_b_w, assets.sprite_b_h, clock.poses[1], clock.tick, true);
}

fn drawSprite(px: []u8, image: []const u8, w: usize, h: usize, pose: clockmod.Pose, tick: u32, wrap: bool) void {
    var row: usize = 0;
    while (row < h) : (row += 1) {
        const source_y = if (wrap and row >= 2 and row < 32)
            2 + (tick + @as(u32, @intCast(row)) - 2) % 192
        else
            row;
        const y = pose.y + @as(i32, @intCast(row));
        if (y < 0 or y >= H) continue;
        var dx: usize = 0;
        while (dx < w) : (dx += 1) {
            const x = pose.x + @as(i32, @intCast(dx));
            if (x < 0 or x >= W) continue;
            px[@as(usize, @intCast(y)) * W + @as(usize, @intCast(x))] = image[source_y * w + dx];
        }
    }
}

/// Step the planar Clock `shadow` (initialised when `fresh`) to the live
/// clock's tick -- deterministic: the motion reads no input -- for the
/// harness's screen exports. testapi.zig owns the storage (zg.mem, at the
/// first call), so it costs the cart nothing outside the harness.
pub fn shadowScreen(shadow: *clockmod.Clock, fresh: bool, tick: u32, regs: [14]u8) *const [32000]u8 {
    if (fresh or shadow.tick > tick) shadow.* = clockmod.Clock.init();
    while (shadow.tick < tick) shadow.step();
    if (tick > 0) metermod.apply(shadow.screen[0..], regs);
    return &shadow.screen;
}
