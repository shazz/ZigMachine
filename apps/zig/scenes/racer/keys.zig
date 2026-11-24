// --------------------------------------------------------------------------
// RACER: the cart's keys (the list is at the head of racer.zig), as one switch over any Demo: the
// harness' --break switches X (poly.break_edge), Y (clip.break_drop) and Z (car.break_slip) are here too.
// --------------------------------------------------------------------------
const car = @import("car.zig");
const clip = @import("clip.zig");
const fx = @import("fx.zig");
const poly = @import("poly.zig");

pub fn handle(self: anytype, cp: u32) void {
    switch (cp) {
        0xE012 => self.wants_quit = true,
        '3'...'8' => self.r = cp - '0',
        'f' => self.p.cpu_fill = !self.p.cpu_fill,
        'm' => fx.use_zmx = !fx.use_zmx,
        'g' => fx.use_f32 = !fx.use_f32,
        'd' => self.decals = !self.decals,
        'o' => self.osd = !self.osd,
        'u' => self.uncapped = !self.uncapped,
        'c' => self.rep.crc_on = !self.rep.crc_on,
        't' => self.setTrack(1 - self.which),
        'p', ' ' => self.paused = !self.paused,
        'l' => self.setDrive(.off),
        'n' => self.setDrive(if (self.drive.mode == .drive) .off else .drive),
        'b' => self.setDrive(.bench),
        'v' => self.drive.nextPov(),
        'r', 13 => self.drive.reset(),
        'Z' => car.break_slip = !car.break_slip, // the harness' --break slip
        'X' => poly.break_edge = !poly.break_edge, // the harness' --break switches (see racer_headless.mjs)
        'Y' => clip.break_drop = !clip.break_drop,
        'A'...'H' => self.pose = cp - 'A',
        else => {},
    }
}

