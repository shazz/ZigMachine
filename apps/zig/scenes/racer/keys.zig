// --------------------------------------------------------------------------
// RACER: the cart's keys (the list is at the head of racer.zig), as one switch over any Demo: the
// harness' --break switches X (poly.break_edge), Y (clip.break_drop) and Z (car.break_slip) are here too.
// --------------------------------------------------------------------------
const car = @import("car.zig");
const clip = @import("clip.zig");
const crest = @import("crest.zig");
const zg = @import("zigos");
const fx = @import("fx.zig");
const audio = @import("audio.zig");
const npc = @import("npc.zig");
const project = @import("project.zig");
const poly = @import("poly.zig");
const ts = @import("trackset.zig");
const shadow = @import("shadow.zig");

pub fn handle(self: anytype, cp: u32) void {
    switch (cp) {
        0xE012 => self.wants_quit = true,
        '3'...'8' => {
            self.r = cp - '0';
            if (self.drive.mode != .bench and self.game.mode != .bench) self.play_r = self.r; // a bench lap's knob is its own
        },
        'f' => self.p.cpu_fill = !self.p.cpu_fill,
        'm' => fx.use_zmx = !fx.use_zmx,
        'g' => fx.use_f32 = !fx.use_f32,
        'd' => self.decals = !self.decals,
        'o' => self.osd = !self.osd,
        'u' => self.uncapped = !self.uncapped,
        'c' => self.rep.crc_on = !self.rep.crc_on,
        't' => self.setTrack(ts.next(self, self.which)),
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
        'i' => nextShade(self),
        'y' => {
            shadow.fake = !shadow.fake;
            zg.Console.log("racer,shadow,{s}", .{if (shadow.fake) "DITHER" else "REAL"});
        },
        'k' => {
            self.setGame(.race);
            crest.setup(&self.game);
        },
        'Z' => car.break_slip = !car.break_slip, // the harness' --break slip
        'W' => npc.break_pid = !npc.break_pid, // ... and --break pid (racer_race.mjs)
        'X' => poly.break_edge = !poly.break_edge, // the harness' --break switches (see racer_headless.mjs)
        'Y' => clip.break_drop = !clip.break_drop,
        'S' => shadow.break_two = !shadow.break_two, // racer_car.mjs --break two: the shadow two levels down
        'Q' => shadow.fake = true, // ... and --break dither: the checkerboard as if it were the default
        'A'...'H' => self.pose = cp - 'A',
        else => _ = audio.key(self, cp), // z, h, j: the music, the effects, the benchmark's audio
    }
}


/// Key i: the VR tracks' debug shading, FLAT (his stored colours, the default) / LIT (the converter's light, the old look) /
/// SOFT (a gentle light). The far ground follows (trackset.groundLevel). Our tracks store no alternates: nothing changes there.
fn nextShade(self: anytype) void {
    project.shade = (project.shade + 1) % @as(u8, project.SHADES.len);
    ts.look(self);
    zg.Console.log("racer,shade,{s}", .{project.SHADES[project.shade]});
}
