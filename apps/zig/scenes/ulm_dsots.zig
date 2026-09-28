// --------------------------------------------------------------------------
// ULM -- THE DARK SIDE OF THE SPOON (Atari ST, 1991), the MAIN MENU, ported
// from shazz's unreleased melonJS 0.9.2 + CODEF "Dark Side of the Spoon Demo -
// HTML5 Remake" 0.9.8 (main.js PlayScreen, entities.js MainEntity/DoorEntity/
// OverlayObject, data/DSOTS.tmx). Artwork and the demo are ULM's and its
// guests' (the map's plaques: The Lost Boys, Respectables, Chris of TGE,
// Hawkmoon, The Fate, Tyrem, Unlimited Matricks); the remake is shazz's.
//
// A walk-around menu: a winged griffin walks and flies over a 700x40 map of
// 32x32 tiles; the view follows it; Space in front of a door enters a screen.
// The TMX holds ONE DoorEntity ("demo1", the arched door of the temple with the
// ULM plaque); the map's other doors are scenery in the remake too. Its
// target, jsApp.ScreenID.INTRO, is not registered (main.js:81), so in the
// remake the door saves the griffin's position and changes to nothing. Here it
// launches the one ported Dark Side of the Spoon screen, ULM's Parallax
// Distorter (cart ulm_spoon_distorter). Esc (and Back) leave the cart.
//
// Skipped, as a loader rather than the demo: main.js's "PLEASE WAIT" and the
// empty DSOTSLoader (screens.js). demos.js's DemoIntro is the Union Demo's
// intro copied in and never registered: not part of this menu.
//
// Per 60 Hz step, in melonJS 0.9.2's order: the griffin updates and collides
// (me.game.collide: the door), then the viewport follows; the draw then steps
// the parallax. Geometry and halving: ulm_dsots/draw.zig.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const A = @import("ulm_dsots/assets.zig");
const griffin_mod = @import("ulm_dsots/griffin.zig");
const view_mod = @import("ulm_dsots/view.zig");
const level = @import("ulm_dsots/level.zig");
const draw = @import("ulm_dsots/draw.zig");
const Controls = @import("ulm_dsots/controls.zig").Controls;
const testapi = @import("ulm_dsots/testapi.zig");

// The remake names no tune (its YMPlayer line loads "Cuddly - main menu.ym",
// commented out: a leftover of the Union remake it was built from). The SNDH
// archive's The_Fate/Shaolin_Remix.sndh is TITL "Shaolin Remix (DSOTS 512k
// Main menu)", The Fate 1991, FLAG ~y: the demo's own menu tune, and the only
// SNDH tagged as a DSOTS menu (sndh_index.py "Dark Side of the Spoon", "ULM",
// "Cuddly", "main menu").
const MUSIC = "shaolin_remix.sndh";

/// DoorEntity demo_name -> the cart it launches.
const Route = struct { demo_name: []const u8, tag: []const u8 };
const ROUTES = [_]Route{.{ .demo_name = "demo1", .tag = "ulm_spoon_distorter" }};

/// DOOR_TAGS[i] is the cart the TMX's door i launches, joined at comptime: a
/// door with no route is a build error, not a door that silently does nothing.
const DOOR_TAGS: [A.map.DOORS.len][]const u8 = blk: {
    var out: [A.map.DOORS.len][]const u8 = undefined;
    for (A.map.DOORS, 0..) |d, i| {
        out[i] = for (ROUTES) |r| {
            if (std.mem.eql(u8, r.demo_name, d.demo_name)) break r.tag;
        } else @compileError("no route for door " ++ d.demo_name);
    }
    break :blk out;
};

const STEP_MS: f32 = 1000.0 / 60.0; // me.sys.fps; setInterval, not the display
const STEP_DUE_MS: f32 = 10;
const STEP_DEBT_MS: f32 = 4;
const MAX_STEPS = 4;
const K_ESC: u32 = 0xE012;
const BACK: u8 = 6;

comptime {
    if (@import("../cart.zig").Cart == Demo) @export(&testapi.val, .{ .name = "dsotsVal" });
}

pub const Demo = struct {
    griffin: griffin_mod.Griffin,
    view: view_mod.View,
    parallax: view_mod.Parallax,
    controls: Controls,
    clock: f32,
    steps: u32, // 60 Hz steps run (the harness's frame count)
    ready: bool, // zg.mem gave the built views
    wants_quit: bool,
    launch_pending: bool,
    launch: []const u8,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.view.init(level.WIDTH, level.HEIGHT);
        self.parallax.init(self.view.x); // created while the view is still at 0
        self.griffin.init(A.map.SPAWN_X, A.map.SPAWN_Y, level.TILE);
        self.view.follow(self.griffin.x, self.griffin.y); // viewport.follow's forced update
        self.controls.init();
        self.clock = 0;
        self.steps = 0;
        self.launch_pending = false;
        self.launch = "";
        self.ready = A.prepare();
        self.wants_quit = !self.ready; // no RAM for the views: back to the menu, not a dead screen
        testapi.bind(self);

        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.openBorders(.all); // the 384-wide canvas needs the side borders too
        fb.setPalette(A.palette);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        fb.clearFrameBuffer(A.BLACK);
        zg.requestSong(MUSIC);
    }

    /// The remake steps on setInterval at 60 Hz whatever the display: run the
    /// steps that are due, at most MAX_STEPS a frame. As union_demo.zig, a step
    /// is due at STEP_DUE_MS so a 60 Hz display's jittered frames get exactly one
    /// each, the early time carried as debt clamped to STEP_DEBT_MS. The clamp
    /// only applies to frames that long: on a faster display (144 Hz) it would
    /// discard real debt and run ~62 steps a second, so there the debt is kept.
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        if (!self.ready) return;
        const t = if (std.math.isNan(dt) or dt < 0) STEP_MS else @min(dt, MAX_STEPS * STEP_MS);
        const max_debt = if (t >= STEP_DUE_MS) STEP_DEBT_MS else STEP_MS;
        self.clock += t;
        var n: u8 = 0;
        while (self.clock >= STEP_DUE_MS and n < MAX_STEPS) : (n += 1) {
            self.step();
            self.clock = @max(self.clock - STEP_MS, -max_debt);
        }
    }

    fn step(self: *Demo) void {
        self.griffin.update(self.controls.state(), &A.level);
        if (self.touchingDoor()) |d| {
            if (self.controls.takeEnter()) self.enter(d);
        }
        self.view.follow(self.griffin.x, self.griffin.y);
        self.parallax.step(self.view.x);
        self.controls.tick(STEP_MS);
        self.steps += 1;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (!self.ready) return;
        const fb = &zigos.lfbs[0];
        draw.background(fb, self.parallax.offset);
        draw.foreground(fb, &self.view);
        draw.griffin(fb, &self.griffin, &self.view);
        draw.bars(fb);
    }

    pub fn input(self: *Demo, dir: u8) void {
        if (dir == BACK) self.wants_quit = true else self.controls.input(dir);
    }

    pub fn inputRelease(self: *Demo, dir: u8) void {
        self.controls.release(dir);
    }

    /// The cart owns its keys: Escape ("exit") leaves.
    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) self.wants_quit = true;
    }

    /// -1 the menu disk, 1 the door's cart (read by cartTag in the same poll).
    pub fn pollCart(self: *Demo) i32 {
        if (self.wants_quit) return -1;
        if (!self.launch_pending) return 0;
        self.launch_pending = false;
        return 1;
    }

    pub fn cartTag(self: *Demo) []const u8 {
        return self.launch;
    }

    /// me.game.collide: the door whose box overlaps the griffin's (strict edges).
    fn touchingDoor(self: *const Demo) ?usize {
        const b = self.griffin.box();
        for (A.map.DOORS, 0..) |d, i| {
            if (d.x < b.right and b.left < d.x + d.w and d.y < b.bottom and b.top < d.y + d.h) return i;
        }
        return null;
    }

    // DoorEntity.onCollision with "enter" pressed: jsApp.entityPos is saved and
    // the state changes to the screen. The cart swap replaces this cart, so
    // there is no position to come back to.
    fn enter(self: *Demo, d: usize) void {
        self.launch = DOOR_TAGS[d];
        self.launch_pending = true;
    }
};
