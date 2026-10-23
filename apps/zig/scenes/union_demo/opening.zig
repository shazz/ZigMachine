// --------------------------------------------------------------------------
// The Union Demo's opening, inside the hub cart: on the demo's FIRST entry the
// intro splash (union_demo_intro.zig, screens/intro) plays until Space, then
// the street's own loader panel (loading.zig) depacks the menu and the street
// starts. One intro screen, one panel, no cart swap (Matt, 2026-10-23: the
// splash, demoLoader's credits panel and the menu loader's panel had been two
// carts and two panels; and the board's firmware swaps no cart).
//
// Coming back from a door's screen (a return note in the ROM's scratch, which
// only a door writes) skips the splash: the remake's MENU_LOADER goes straight
// to the street's loader too (main.js:347).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const Intro = @import("../union_demo_intro.zig").Demo;
const return_note = @import("return_note.zig");
const hub_note = @import("hub_note.zig");

pub const Opening = struct {
    intro: Intro = undefined,
    on: bool = false, // the splash owns the frame

    /// True when the splash plays first; false: start the street's loader now.
    pub fn start(self: *Opening, zigos: *zg.ZigOS) bool {
        self.on = false;
        if (hub_note.scratch()) |buf| if (return_note.peek(buf) != null) return false;
        self.intro.init(zigos);
        self.on = !self.intro.wants_quit; // graphics that cannot load: straight to the street
        return self.on;
    }

    /// Run the splash's frame. False once it is over (the caller starts the loader).
    pub fn update(self: *Opening, zigos: *zg.ZigOS, dt: f32) bool {
        if (!self.on) return false;
        self.intro.update(zigos, dt);
        if (self.intro.done or self.intro.wants_quit) self.on = false;
        return self.on;
    }

    pub fn render(self: *Opening, zigos: *zg.ZigOS, dt: f32) void {
        self.intro.render(zigos, dt);
    }

    pub fn input(self: *Opening, dir: u8) void {
        self.intro.input(dir);
    }

    pub fn key(self: *Opening, cp: u32) void {
        self.intro.key(cp);
    }
};
