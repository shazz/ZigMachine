// --------------------------------------------------------------------------
// The live picture, composed with CHISEL in the chunky domain (the cart used
// to decode the whole 32000-byte planar screen into the plane every frame,
// 64,000 stores, plus a 4-plane read-modify-write per ribbon pixel). Per tick:
//
//   WORK <- BG                        expand(background), built once at init
//   ribbon rows -> WORK               one blit out of the 640-byte rings: the
//                                     ribbon writes all 4 planes, so its
//                                     chunky pixel IS its index 0..3
//   panel rows  -> WORK, twice        2 whole groups (32 px) at x 64 and 224,
//                                     out of expand(panel pattern)
//   meters                            meter.zig writes the plane-0 word 0 and
//                                     the plane-1 word ffff over cells
//                                     0..volume: index = (index & 12) | 2, so
//                                     an AND-12 fill then an OR-2 fill
//   sprite rows -> WORK               opaque runs of contiguous source rows
//   SHOWN <- WORK                     one copy: never a half-built frame
//
// = the Go's Step + meters + Pixels + ImageSlots, in that order (chunky_test
// proves it every tick against reference.zig). In-plane copies: 0.
// --------------------------------------------------------------------------
const std = @import("std");
const assets = @import("assets.zig");
const clockmod = @import("clock.zig");
const gpu = @import("../chonchon/gpu.zig");

const PANEL_ROWS: usize = 69;
/// expand(panel pattern): 69 rows of 320 indices.
pub var panel_chunky: [PANEL_ROWS * gpu.W]u8 align(4) = undefined;

pub fn initSurfaces(comptime G: type, g: *G) void {
    gpu.expandScreen(g.words(gpu.BG), assets.background);
    const out: [*]u32 = @ptrCast(&panel_chunky);
    for (0..PANEL_ROWS * 20) |grp| gpu.expandGroup(out + grp * 4, assets.panel_pattern[grp * 8 ..][0..8]);
}

pub fn render(comptime G: type, g: *G, c: *const clockmod.Live, regs: [14]u8) void {
    g.copy(gpu.WORK, gpu.BG);
    ribbon(G, g, c);
    panels(G, g, c.panel);
    for (0..3) |ch| {
        const cells: u16 = (regs[8 + ch] & 15) + 1;
        const y: u16 = @intCast(167 + ch * 9);
        g.fillMt(gpu.WORK, 16, y, cells * 16, 7, 12, gpu.MT_AND);
        g.fillMt(gpu.WORK, 16, y, cells * 16, 7, 2, gpu.MT_OR);
    }
    sprite(G, g, assets.sprite_a, assets.sprite_a_w, assets.sprite_a_h, c.poses[0], c.tick, false);
    sprite(G, g, assets.sprite_b, assets.sprite_b_w, assets.sprite_b_h, c.poses[1], c.tick, true);
    g.copy(gpu.SHOWN, gpu.WORK);
}

fn ribbon(comptime G: type, g: *G, c: *const clockmod.Live) void {
    const r0: i32 = @max(0, -c.scroll_y);
    const r1: i32 = @min(23, 200 - c.scroll_y);
    if (r0 >= r1) return;
    const rings = std.mem.asBytes(&c.ribbon);
    g.image(gpu.WORK, 0, @intCast(c.scroll_y + r0), rings, clockmod.RING_W, @intCast(c.head), @intCast(r0), gpu.W, @intCast(r1 - r0), null);
}

fn panels(comptime G: type, g: *G, p: clockmod.Panel) void {
    if (!p.on) return;
    const y0: i32 = @max(p.y, 0);
    const y1: i32 = @min(p.y + p.rows, PANEL_ROWS - 1);
    if (y0 > y1) return;
    const h: u16 = @intCast(y1 - y0 + 1);
    const sx: u16 = @intCast(p.shift * 32);
    const sy: u16 = @intCast(y0);
    g.image(gpu.WORK, 64, sy + 3, &panel_chunky, gpu.W, sx, sy, 32, h, null);
    g.image(gpu.WORK, 224, sy + 3, &panel_chunky, gpu.W, sx, sy, 32, h, null);
}

/// The Go's ImageSlots rows: sprite-b's rows 2..31 read source row
/// 2 + (tick + row - 2) % 192 (its wrapping ribbon), every other row its own.
/// Rows whose source and screen rows both run on become one blit.
fn sprite(comptime G: type, g: *G, image: []const u8, w: usize, h: usize, pose: clockmod.Pose, tick: u32, wrap: bool) void {
    if (pose.x < 0 or pose.x >= gpu.W) return;
    const cw: u16 = @intCast(@min(w, gpu.W - @as(usize, @intCast(pose.x))));
    var run_y: i32 = 0;
    var run_src: usize = 0;
    var run_len: u16 = 0;
    for (0..h) |row| {
        const src = if (wrap and row >= 2 and row < 32) 2 + (tick + @as(u32, @intCast(row)) - 2) % 192 else row;
        const y = pose.y + @as(i32, @intCast(row));
        if (y < 0 or y >= gpu.H) continue;
        if (run_len > 0 and src == run_src + run_len and y == run_y + run_len) {
            run_len += 1;
            continue;
        }
        if (run_len > 0) g.image(gpu.WORK, @intCast(pose.x), @intCast(run_y), image, @intCast(w), 0, @intCast(run_src), cw, run_len, null);
        run_y = y;
        run_src = src;
        run_len = 1;
    }
    if (run_len > 0) g.image(gpu.WORK, @intCast(pose.x), @intCast(run_y), image, @intCast(w), 0, @intCast(run_src), cw, run_len, null);
}
