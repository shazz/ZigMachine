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
const front = @import("front.zig");
const clock = @import("clock.zig");
const seldraw = @import("seldraw.zig");
const options = @import("options.zig");
const press = @import("press.zig");
const haze = @import("haze.zig");
const arcade = @import("arcade.zig");

pub fn handle(self: anytype, cp: u32) void {
    if (front.key(self, cp)) return; // the title, the select, the results (M5 step 4)
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
        'i' => options.setShade(self, (project.shade + 1) % @as(u8, project.SHADES.len)), // the VR tracks' debug shading (M5_VR.md)
        'y' => options.setShadow(!shadow.fake),
        'q' => options.setHaze(self, !haze.on), // M6: the horizon haze on / off (a track whose mood has one)
        'T' => options.setPhysics(if (arcade.model == .arcade) .classic else .arcade), // R82 32X feel: the PHYSICS option
        'M' => options.change(self, .class, 1), // ... the CAR CLASS option
        'L' => self.game.apilot = !self.game.apilot, // ... the AI pilot in the option's physics (the arcade harness' driver)
        '9' => options.setHeadroom(!project.headroom), // ... the 32X import's shadow headroom (FEEL.md)
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
        'J' => seldraw.break_refuse = true, // racer_front.mjs --break refuse: the scan's refusals not listed
        'U' => clock.break_flat = true, // ... --break clock: every computed clock freds72's 75 s + 10 s
        'V' => front.break_results = true, // ... --break fsm: fire on the results goes to the title
        'R' => press.break_repeat = true, // ... --break repeat: a held key's repeats count as presses
        'I' => arcade.break_feel = true, // racer_feel.mjs --break feel: the arcade's drag doubled
        'K' => @import("zone.zig").break_zone = true, // racer_zone.mjs --break zone: no camera zone anywhere
        'N' => options.breakHaze(self, &haze.break_absent), // racer_haze.mjs --break absent: the haze built, never applied
        'P' => options.breakHaze(self, &haze.break_near), // ... --break near: every band one nearer (near faces hazed)
        'O' => @import("under.zig").break_under = true, // racer_bugpass.mjs --break under: a car keyed by its centre's face only
        '+' => @import("frame.zig").ring = (@import("frame.zig").ring + 2) % 6, // the far ring: off, 2, 4 tiles past R
        '0' => @import("hudpic.zig").on = !@import("hudpic.zig").on, // the race HUD over the picture / the two bands
        '1' => @import("smoke.zig").hidden = !@import("smoke.zig").hidden, // the tyre smoke not drawn (racer_drive.mjs' A/B)
        '2' => @import("oracle.zig").all_tiles = !@import("oracle.zig").all_tiles, // the visibility oracle (oracle.zig: racer,pvs lines)
        '@' => @import("pvs.zig").break_thin = true, // racer_bugpass.mjs --break pvs: the PVS list thinned (the oracle must see losses)
        '!' => @import("pushes.zig").break_push = true, // ... --break push: ARCADE back to freds72's player-only contacts
        'A'...'H' => self.pose = cp - 'A',
        else => _ = audio.key(self, cp), // z, h, j: the music, the effects, the benchmark's audio
    }
}
