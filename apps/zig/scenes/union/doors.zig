// --------------------------------------------------------------------------
// Union main — the cracktro's street host. Wraps the main screen: the runner
// passes efmain.js's 18 doors (posDoors), which are DECORATIVE (Matt,
// 2026-10-23: this is the CODEF cracktro, not the Union Demo; the real demo's
// doors are the street hub's, union_demo). ESC (or Back) bubbles wants_quit to
// the outer menu. Hold Left to slow the world (and the runner's ghost trail);
// release re-accelerates.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const MainScreen = @import("main.zig").Demo;

// Hold Left to slow the world; release re-accelerates. One keydown holds the
// slow for HOLD frames (bridging the browser's key-repeat gap); speed ramps.
// Speeds in Q16 tiles a frame (main.zig Demo.speed); no float a frame.
const NORMAL: i32 = MainScreen.NORMAL_SPEED; // 0.3
const SLOW: i32 = 3277; // 0.05
const HOLD: u32 = 24;
const RAMP: i32 = 9830; // 0.15, Q16
const K_ESC: u32 = 0xE012; // host KEY_CODES.Escape

pub const Doors = struct {
    main: MainScreen = .{},
    slow: u32 = 0, // frames of "hold Left" slowdown remaining
    wants_quit: bool = false,

    pub fn init(self: *Doors, zigos: *ZigOS) void {
        self.* = .{};
        self.main.init(zigos);
    }

    pub fn update(self: *Doors, zigos: *ZigOS, dt: f32) void {
        // Hold-Left slowdown: ramp toward SLOW while armed, else back to NORMAL.
        const target: i32 = if (self.slow > 0) SLOW else NORMAL;
        // speed += (target - speed) * RAMP, landing on the target once a step rounds to 0
        const d = target - self.main.speed;
        const step = @divTrunc(d * RAMP, 1 << 16);
        self.main.speed += if (step == 0) d else step;
        if (self.slow > 0) self.slow -= 1;
        self.main.update(zigos, dt);
    }

    pub fn render(self: *Doors, zigos: *ZigOS, dt: f32) void {
        self.main.render(zigos, dt);
    }

    // Host input: 0-3 dirs, 5 Fire (Space), 6 Back (see demo_main.zig Direction).
    pub fn input(self: *Doors, dir: u8) void {
        if (dir == 2) self.slow = HOLD; // hold Left to slow down (auto-repeat re-arms)
        if (dir == 6) self.wants_quit = true; // Back on the main screen -> outer menu
    }

    // Owning key() means owning Escape: it still quits to the outer menu.
    pub fn key(self: *Doors, cp: u32) void {
        if (cp == K_ESC) self.wants_quit = true;
    }

    pub fn setShadeMode(self: *Doors, mode: u32) void {
        self.main.setShadeMode(mode);
    }

    pub fn pollSong(self: *Doors) u32 {
        return self.main.pollSong();
    }

    /// Cartridge swap (demo_main.pollCartRequest): -1 the menu; the doors launch nothing.
    pub fn pollCart(self: *Doors) i32 {
        return if (self.wants_quit) -1 else 0;
    }

    pub fn cartTag(self: *Doors) []const u8 {
        _ = self;
        return "";
    }
};
