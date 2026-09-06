// --------------------------------------------------------------------------
// Union main — DOORS host. Wraps the main screen and turns its doors into a
// launcher: as a door mapped to a real ST-demo screen scrolls in, its title
// fades in (credits font, in the sky above the door) and out as it nears the
// runner. Space enters the titled door; Back returns; ESC on the main screen
// bubbles wants_quit to the outer menu. Hold Left to slow the world (and the
// runner's ghost trail) so a door is easy to catch; release re-accelerates.
// Faithful hook: efmain.js's posDoors (18 door columns); runner col = pos + 13.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const MainScreen = @import("main.zig").Demo;
const cf = @import("creditfont.zig");
const maps = @import("../../assets/screens/union_main/union_maps.zig");

const RUNNER_TILE: f32 = 13.0; // sprite centre, in tiles into the window
const RUNNER_X: f32 = 216.0; // its physical x (main.zig CENTER_X)
const TW: f32 = 16.0; // tile size (px)
const TITLE_Y: i16 = 46; // title baseline in the sky, above the door
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

// Real screens reachable through doors (curated to fit the cart budget).
const Door = union(enum) {
    none,
    bladerunners: @import("../bladerunners.zig").Demo,
    deltaforce: @import("../deltaforce.zig").Demo,
    fallen_angels: @import("../fallen_angels.zig").Demo,
    ancool: @import("../ancool.zig").Demo,
    leonard: @import("../leonard.zig").Demo,
    empire: @import("../empire.zig").Demo,
};
const Tag = std.meta.Tag(Door);

// posDoors index (0..17) -> optional scene + title.
const Entry = struct { tag: ?Tag = null, name: []const u8 = "" };
const DOORS = [18]Entry{
    .{ .tag = .bladerunners, .name = "BLADE RUNNERS" }, .{ .tag = .deltaforce, .name = "DELTA FORCE" },
    .{}, .{},
    .{ .tag = .fallen_angels, .name = "FALLEN ANGELS" }, .{ .tag = .ancool, .name = "ANCOOL" },
    .{}, .{ .tag = .leonard, .name = "LEONARD" }, .{ .tag = .empire, .name = "EMPIRE" },
    .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{},
};

pub const Doors = struct {
    main: MainScreen = .{},
    child: Door = .none,
    running: bool = false,
    titled: i32 = -1, // door index whose title is currently on screen, or -1
    title_alpha: f32 = 0,
    title_cx: i16 = 0, // door centre on screen (px)
    slow: u32 = 0, // frames of "hold Left" slowdown remaining
    pending_launch: i32 = -1,
    pending_back: bool = false,
    wants_quit: bool = false,

    pub fn init(self: *Doors, zigos: *ZigOS) void {
        self.* = .{};
        self.main.init(zigos);
        setupOverlay(zigos);
        self.pickTitle(); // so an immediate Space (before the first update) still enters
    }

    pub fn update(self: *Doors, zigos: *ZigOS, dt: f32) void {
        if (self.pending_launch >= 0) {
            self.launch(zigos, @intCast(self.pending_launch));
            self.pending_launch = -1;
            return;
        }
        if (self.pending_back) return self.goBack(zigos);
        if (self.running) {
            switch (self.child) {
                .none => {},
                inline else => |*c| c.update(zigos, dt),
            }
            return;
        }
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
            if (DOORS[i].tag == null) continue;
            const d = @as(f32, @floatFromInt(p)) - self.main.pos - RUNNER_TILE;
            const a = titleAlpha(d);
            if (a <= 0) continue;
            self.titled = @intCast(i);
            self.title_alpha = a;
            self.title_cx = @intFromFloat(RUNNER_X + d * TW);
        }
    }

    pub fn render(self: *Doors, zigos: *ZigOS, dt: f32) void {
        if (self.running) {
            switch (self.child) {
                .none => {},
                inline else => |*c| c.render(zigos, dt),
            }
            return;
        }
        self.main.render(zigos, dt);
        if (self.titled >= 0 and self.title_alpha > 0) {
            const p1 = &zigos.lfbs[1];
            p1.setPaletteEntry(TITLE_IDX, Color{ .r = 255, .g = 255, .b = 255, .a = @intFromFloat(self.title_alpha * 255.0) });
            const name = DOORS[@intCast(self.titled)].name;
            cf.drawLine(p1, name, self.title_cx - @divTrunc(cf.width(name), 2), TITLE_Y, TITLE_IDX);
        }
    }

    // Host input: 0-3 dirs, 5 Fire (Space), 6 Back (see demo_main.zig Direction).
    pub fn input(self: *Doors, dir: u8) void {
        if (self.running) {
            if (dir == 6) {
                self.pending_back = true;
            } else switch (self.child) {
                .none => {},
                inline else => |*c| if (@hasDecl(@TypeOf(c.*), "input")) c.input(dir),
            }
            return;
        }
        if (dir == 2) self.slow = HOLD; // hold Left to slow down (auto-repeat re-arms)
        if (dir == 5 and self.titled >= 0) self.pending_launch = self.titled; // Space enters
        if (dir == 6) self.wants_quit = true; // ESC on the main screen -> outer menu
    }

    pub fn setShadeMode(self: *Doors, mode: u32) void {
        if (self.running) {
            switch (self.child) {
                .none => {},
                inline else => |*c| if (@hasDecl(@TypeOf(c.*), "setShadeMode")) c.setShadeMode(mode),
            }
        } else self.main.setShadeMode(mode);
    }

    pub fn pollSong(self: *Doors) u32 {
        if (self.running) return 0;
        return self.main.pollSong();
    }

    fn launch(self: *Doors, zigos: *ZigOS, idx: usize) void {
        zigos.resetForScene();
        switch (DOORS[idx].tag.?) {
            .none => return, // never mapped in DOORS
            inline else => |t| {
                self.child = @unionInit(Door, @tagName(t), .{});
                @field(self.child, @tagName(t)).init(zigos);
            },
        }
        self.running = true;
    }

    fn goBack(self: *Doors, zigos: *ZigOS) void {
        self.pending_back = false;
        zigos.resetForScene();
        self.child = .none;
        self.running = false;
        self.titled = -1;
        self.title_alpha = 0;
        self.slow = 0;
        self.main.speed = NORMAL;
        self.main.init(zigos);
        setupOverlay(zigos);
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
