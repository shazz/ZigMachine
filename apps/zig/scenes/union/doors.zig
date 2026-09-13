// --------------------------------------------------------------------------
// Union main — DOORS host. Wraps the main screen and turns its doors into a
// launcher: as a door scrolls in, its title fades in (credits font, in the sky
// above the door) and out as it nears the runner. Space enters the titled door;
// ESC bubbles wants_quit to the outer menu. Hold Left to slow the world (and the
// runner's ghost trail) so a door is easy to catch; release re-accelerates.
// Faithful hook: efmain.js's posDoors (18 door columns); runner col = pos + 13.
// This cracktro is the Union Demo's PREAMBLE: every door boots the Union Demo,
// which opens on its intro splash (Matt, 2026-09-13: "the demo opens on it";
// the remake's main.js:262-265), cart union_intro_screen.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const MainScreen = @import("main.zig").Demo;
const maps = @import("../../assets/screens/union_main/union_maps.zig");

const RUNNER_TILE: f32 = 13.0; // sprite centre, in tiles into the window
const RUNNER_X: f32 = 216.0; // its physical x (main.zig CENTER_X)
const TW: f32 = 16.0; // tile size (px)
const TITLE_IDX: u8 = 0x3A; // dedicated P1 slot for the door-title glyphs

// Title fade zones, in tiles the door is *ahead* of the runner (d = col-pos-13):
// appears at FAR, fades to full by HI, holds to LO, fades out to 0 as it nears.
const FAR: f32 = 12.0;
const HI: f32 = 8.0;
const LO: f32 = 4.0;

// Hold Left to slow the world; release re-accelerates. One keydown holds the
// slow for HOLD frames (bridging the browser's key-repeat gap); speed ramps.
const NORMAL: f32 = 0.3;
const SLOW: f32 = 0.05;
const HOLD: u32 = 24;
const RAMP: f32 = 0.15;
const K_ESC: u32 = 0xE012; // host KEY_CODES.Escape

/// The cart every door boots: the Union Demo, starting on its intro splash.
pub const DOOR_CART = "union_intro_screen";

// posDoors index (0..17) -> whether it is a door, and the title it had.
const Entry = struct { door: bool = true, name: []const u8 = "" };
const DOORS = [18]Entry{
    .{ .name = "BLADE RUNNERS" }, .{ .name = "DELTA FORCE" }, .{}, .{}, .{ .name = "FALLEN ANGELS" }, .{ .name = "ANCOOL" },
    .{}, .{ .name = "LEONARD" }, .{ .name = "EMPIRE" }, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{},
};

pub const Doors = struct {
    main: MainScreen = .{},
    titled: i32 = -1, // door index whose title is currently on screen, or -1
    title_alpha: f32 = 0,
    title_cx: i16 = 0, // door centre on screen (px)
    slow: u32 = 0, // frames of "hold Left" slowdown remaining
    launch_pending: bool = false, // a door was entered: ask the host for DOOR_CART
    wants_quit: bool = false,

    pub fn init(self: *Doors, zigos: *ZigOS) void {
        self.* = .{};
        self.main.init(zigos);
        setupOverlay(zigos);
        self.pickTitle(); // so an immediate Space (before the first update) still enters
    }

    pub fn update(self: *Doors, zigos: *ZigOS, dt: f32) void {
        if (self.launch_pending) return; // the host swaps the cart on its next poll
        // Hold-Left slowdown: ramp toward SLOW while armed, else back to NORMAL.
        const target: f32 = if (self.slow > 0) SLOW else NORMAL;
        self.main.speed += (target - self.main.speed) * RAMP;
        if (self.slow > 0) self.slow -= 1;
        self.main.update(zigos, dt);
        self.pickTitle();
    }

    // Find the mapped door in the fade window and set title state for this frame.
    fn pickTitle(self: *Doors) void {
        self.titled = -1;
        self.title_alpha = 0;
        for (maps.POS_DOORS, 0..) |p, i| {
            if (!DOORS[i].door) continue;
            const d = @as(f32, @floatFromInt(p)) - self.main.pos - RUNNER_TILE;
            const a = titleAlpha(d);
            if (a <= 0) continue;
            self.titled = @intCast(i);
            self.title_alpha = a;
            self.title_cx = @intFromFloat(RUNNER_X + d * TW);
        }
    }

    pub fn render(self: *Doors, zigos: *ZigOS, dt: f32) void {
        self.main.render(zigos, dt);
        // Door-name title removed (its fade wasn't well synced to the door). The
        // enterable door is still tracked by pickTitle -> self.titled (so Space
        // still enters the door in front); names will return as tiles below the
        // door. See notes/zigmachine-gem-pending-todo / next-session idea.
    }

    // Host input: 0-3 dirs, 5 Fire (Space), 6 Back (see demo_main.zig Direction).
    pub fn input(self: *Doors, dir: u8) void {
        if (dir == 2) self.slow = HOLD; // hold Left to slow down (auto-repeat re-arms)
        if (dir == 5 and self.titled >= 0) self.launch_pending = true; // Space enters
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

    /// Cartridge swap (demo_main.pollCartRequest): -1 the menu, 1 DOOR_CART.
    pub fn pollCart(self: *Doors) i32 {
        if (self.wants_quit) return -1;
        if (!self.launch_pending) return 0;
        self.launch_pending = false;
        return 1;
    }

    pub fn cartTag(self: *Doors) []const u8 {
        _ = self;
        return DOOR_CART;
    }
};

// Piecewise fade over the door's distance-ahead (tiles): 0 outside (0,FAR),
// ramp up FAR->HI, full HI->LO, ramp down LO->0.
fn titleAlpha(d: f32) f32 {
    if (d <= 0 or d >= FAR) return 0;
    if (d >= HI) return (FAR - d) / (FAR - HI);
    if (d >= LO) return 1;
    return d / LO;
}

fn setupOverlay(zigos: *ZigOS) void {
    zigos.lfbs[1].setPaletteEntry(TITLE_IDX, Color{ .r = 255, .g = 255, .b = 255, .a = 0 });
}
