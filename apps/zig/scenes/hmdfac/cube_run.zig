// --------------------------------------------------------------------------
// The cube phases' per-frame machine: $ba3e's wheel counters, the camera walk
// and the $210ac queue (stepped in update()), and one drawn frame — $fede's
// undo, the faces, the laser stripes re-laid where the art covered them.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");
const R = @import("rasters.zig");
const cube = @import("cube.zig");

const CX0: u32 = 0x1356; // the camera word at boot ($210a6)
const CX_HOLD: u32 = 0x79e; // phase 1's stop value
const CX_STEP: u32 = 0x28;
const WHEEL_MAX: u16 = 0x2ce; // counters wrap to 0 above this
const CNT_INIT: u16 = 0x80; // cc's boot value

// module level, so testapi.zig can read every word
pub var wheel: cube.Wheel = undefined;
pub var qi: u16 = 0; // the queue pair walk
var dirty: cube.Rows = .{}; // plate rows the last cube frame drew on

pub fn reset() void {
    wheel = .{ .ca = 0, .cb = 0, .cc = CNT_INIT, .camera = CX0, .qx = 0, .qy = 0 };
    qi = 0;
    dirty = .{};
    cube.reset();
}

fn adv(c: u16, by: u16) u16 {
    const v = c +% by;
    return if (v > WHEEL_MAX) 0 else v;
}

/// One frame's state step: phase 1 walks the camera down to $79e, phase 3
/// back up with no stop; the counters and the queue step every frame.
pub fn step(phase: u8) void {
    if (phase == 1) {
        if (wheel.camera != CX_HOLD) {
            const next = wheel.camera -% CX_STEP;
            wheel.camera = if (next <= CX_HOLD) CX_HOLD else next;
        }
    } else if (phase == 3) {
        wheel.camera += CX_STEP;
    }
    wheel.ca = adv(wheel.ca, 4);
    wheel.cb = adv(wheel.cb, 2);
    wheel.cc = adv(wheel.cc, 4);
    wheel.qx = A.queue[@as(usize, qi) * 2];
    wheel.qy = A.queue[@as(usize, qi) * 2 + 1];
    qi += 1;
    if (qi >= A.QUEUE_PAIRS) qi = 0;
}

/// The plate's static art (logo + band A) over plate rows [lo, hi], as
/// CHISEL copies from cart RAM.
pub fn restoreRows(plate: blit.Dst, lo: i32, hi: i32) void {
    if (lo > hi) return;
    const y0: usize = @intCast(lo);
    const part = blit.Rect{ .x = 0, .y = y0, .w = A.ART_W, .h = @intCast(hi - lo + 1) };
    blit.blit(plate, blit.Image.init(A.logo_data, A.ART_W), part, 0, lo, null, .copy);
    const a_lo = @max(lo, A.BAND_A_Y);
    const a_hi = @min(hi, A.BAND_A_Y + A.BAND_A_H - 1);
    if (a_lo > a_hi) return;
    const ap = blit.Rect{ .x = 0, .y = @intCast(a_lo - A.BAND_A_Y), .w = A.ART_W, .h = @intCast(a_hi - a_lo + 1) };
    blit.blit(plate, blit.Image.init(A.band_a_data, A.ART_W), ap, 0, a_lo, null, .copy);
}

fn touches(r: cube.Rows, row: i32) bool {
    return r.lo <= row and row <= r.hi;
}

/// One cube frame: undo the last frame's rows, draw, and re-lay the laser
/// stripes only where the art just overwrote them (plate rows 2, 3, 196).
pub fn frame(whole: blit.Dst, plate: blit.Dst) void {
    const was = dirty;
    restoreRows(plate, dirty.lo, dirty.hi);
    dirty = cube.drawFaces(plate, cube.project(wheel));
    for ([_]i32{ 2, 3, 196 }) |row| {
        if (touches(was, row) or touches(dirty, row)) return R.stamp(whole, 0, true);
    }
}
