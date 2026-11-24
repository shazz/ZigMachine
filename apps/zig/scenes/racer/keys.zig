// --------------------------------------------------------------------------
// RACER: the cart's keys (the list is at the head of racer.zig), as one switch over any Demo: the
// harness' --break switches X (poly.break_edge), Y (clip.break_drop) and Z (car.break_slip) are here too.
// --------------------------------------------------------------------------
const car = @import("car.zig");
const clip = @import("clip.zig");
const crest = @import("crest.zig");
const fx = @import("fx.zig");
const audio = @import("audio.zig");
const npc = @import("npc.zig");
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
        'v' => if (self.game.mode != .off) self.game.nextPov() else self.drive.nextPov(),
        'r', 13 => if (self.game.mode != .off) self.game.again() else self.drive.reset(),
        'e' => self.setGame(if (self.game.mode == .race) .off else .race),
        'x' => self.setGame(.bench),
        's' => self.game.go(),
        'a' => self.game.toggleAuto(),
        'w' => self.game.toggleWarp(),
        'k' => {
            self.setGame(.race);
            crest.setup(&self.game);
        },
        'Z' => car.break_slip = !car.break_slip, // the harness' --break slip
        'W' => npc.break_pid = !npc.break_pid, // ... and --break pid (racer_race.mjs)
        'X' => poly.break_edge = !poly.break_edge, // the harness' --break switches (see racer_headless.mjs)
        'Y' => clip.break_drop = !clip.break_drop,
        'A'...'H' => self.pose = cp - 'A',
        else => _ = audio.key(self, cp), // z, h, j: the music, the effects, the benchmark's audio
    }
}

