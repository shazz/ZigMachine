// TCB #2's pixel layers, each sampled at the 640-space point (2X+0.5, 2Y+0.5)
// through the remake's transforms, nearest (see fx.zig).
const frame = @import("frame.zig");
const assets = @import("assets.zig");
const image = @import("image.zig");
const fx = @import("fx.zig");
const org = @import("tcb2_org.zig");

const ifloor = image.ifloor;
const NONE = image.NONE;

/// orgcanvas.draw(mycanvas2, 0, -200, 1, 0, 1.8, 1.8), mycanvas2 drawn at (34, top):
/// rows 0..231 of mycanvas2 hold the orgcanvas (rows 111..239), the rest is empty.
pub fn layer(top: f64) void {
    var y: i32 = 0;
    while (y < 225) : (y += 1) {
        const y2 = ifloor(@as(f64, @floatFromInt(2 * y)) + 0.5 - top);
        if (y2 < 0 or y2 >= 400) continue;
        const oy = ifloor((@as(f64, @floatFromInt(y2)) + 0.5 + 200) / 1.8);
        if (oy < org.TOP or oy >= org.H) continue;
        const row = org.row(@intCast(oy));
        var x: i32 = 17;
        while (x < 320) : (x += 1) {
            const ox = ifloor((@as(f64, @floatFromInt(2 * x - 34)) + 0.5) / 1.8);
            frame.put(x, y, row[@intCast(ox)]);
        }
    }
}

/// wizcoder.draw(mergecanvas, 320, 88, 1, 0, 1.5, 1.5), filled 'source-atop'
/// with the frame's clr[] grey, drawn from its top 150 rows.
pub fn wizcoder(grey: u16) void {
    var y: i32 = 0;
    while (y < 75) : (y += 1) {
        const v = ifloor((@as(f64, @floatFromInt(2 * y)) + 0.5 - 88) / 1.5 + 37);
        if (v < 0 or v >= 74) continue;
        var x: i32 = 60;
        while (x < 260) : (x += 1) {
            const u = ifloor((@as(f64, @floatFromInt(2 * x)) + 0.5 - 320) / 1.5 + 130);
            if (assets.wizcoder.at(u, v) != NONE) frame.put(x, y, grey);
        }
    }
}

/// tcb2.draw(distcanvas1, 320, 50, 1, 0, 1.5, 1.5); siny(0,0) into distcanvas2;
/// sinx(0,0) onto mycanvas (rows 0..239).
pub fn tcbLogo(fx_y: *fx.Fx(2), fx_x: *fx.Fx(2)) void {
    var q: [640]f64 = undefined;
    var p: [240]f64 = undefined;
    fx_y.run(&q);
    fx_x.run(&p);
    var y: i32 = 0;
    while (y < 120) : (y += 1) {
        const j: usize = @intCast(2 * y);
        var x: i32 = 0;
        while (x < 320) : (x += 1) {
            const c2 = ifloor(@as(f64, @floatFromInt(2 * x)) + 0.5 - p[j]);
            if (c2 < 0 or c2 >= 640) continue;
            const r1 = ifloor(@as(f64, @floatFromInt(j)) + 0.5 - q[@intCast(c2)]);
            if (r1 < 0 or r1 >= 240) continue;
            const u = ifloor((@as(f64, @floatFromInt(c2)) + 0.5 - 320) / 1.5 + 48);
            const v = ifloor((@as(f64, @floatFromInt(r1)) + 0.5 - 50) / 1.5 + 12);
            const g = assets.tcblogo.at(u, v);
            if (g != NONE) frame.put(x, y, g);
        }
    }
}

/// ancool.png drawn once at (130, 88) of distcanvas3; sinx(0,0) onto mycanvas.
pub fn ancool(fx_x: *fx.Fx(2)) void {
    var p: [240]f64 = undefined;
    fx_x.run(&p);
    var y: i32 = 44;
    while (y < 67) : (y += 1) {
        const j: usize = @intCast(2 * y);
        var x: i32 = 0;
        while (x < 320) : (x += 1) {
            const c = ifloor(@as(f64, @floatFromInt(2 * x)) + 0.5 - p[j]);
            const g = assets.ancool.at(c - 130, @as(i32, @intCast(j)) - 88);
            if (g != NONE) frame.put(x, y, g);
        }
    }
}
