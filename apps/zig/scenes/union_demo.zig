// --------------------------------------------------------------------------
// The Union Demo (1989) MAIN MENU, ported from shazz's melonJS "Union Demo
// HTML5 Remake" 0.9.8 (main.js PlayScreen, entities.js). Artwork, music and
// scrolltext belong to The Union; Charly and the street are TEX's.
//
// Charly walks a 175x25 street of 32x16 tiles (data/union3.tmx); the view
// follows him horizontally; fire in front of one of the eleven doors enters a
// demo screen. Under the playfield runs the TEX scroller.
//
// Geometry: the remake's canvas is 640x480 but everything it draws sits in the
// top 400 rows (map 25x16, HUD down to 395) — an ST 320x200 doubled. Halved
// onto one normal 320x200 plane; no border is used.
//
// Per frame, in melonJS's order: layers update (rasters, banner parallax, one
// frame behind the camera), Charly moves and collides, the door check, the
// viewport follows, the HUD scrolls. Then draw, lowest z first.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;

const A = @import("union_demo/assets.zig");
const Charly = @import("union_demo/charly.zig").Charly;
const Controls = @import("union_demo/controls.zig").Controls;
const Hud = @import("union_demo/hud.zig").Hud;
const world = @import("union_demo/world.zig");
const doors = @import("union_demo/doors.zig");

// "Union Demo MENU" is Mad Max's Alloy Run: U_MENU.BIN, the YM5! register dump
// the remake plays (header "Union Demo MENU / Mad Max (Alloyrun/MON)"), shipped
// depacked as .ymraw because that is the extension the host's YM player is
// wired to.
// KEPT as .ymraw (checked 2026-09-13, per "prefer SNDH over YM"): no SNDH
// matches this recording. Registers 0-5/8-10 over 800 frames, offsets -50..+400:
// Mad_Max C64-Conversions tune 1 best at 1.8%, tune 2 and Dubmood 0%. The
// archive's Mad_Max/Demos/Union_Demo/SID/Alloy_Run.sndh plays SILENT in our
// player (MFP timers never start, peak 0), so it cannot be compared yet.
const MUSIC = "union_demo_menu.ymraw";

const VIEW_W: i32 = 640; // me.video.init('jsapp', 640, 400) (main.js:240)
const CAM_LIMIT: i32 = @as(i32, @intCast(A.map.COLS * A.map.TILE_W)) - VIEW_W;
const BANNER_RATIO: f32 = 0.5; // plx_banner "ratio" property (union3.tmx)
const BANNER_W: f32 = 640; // banner4.png
const MESSAGE_FRAMES: u16 = 120;
const K_ESC: u32 = 0xE012;

pub const Demo = struct {
    charly: Charly,
    controls: Controls,
    hud: Hud,
    cam: i32, // viewport pos.x, 640 space
    banner: zg.tilemap.RatioScroll,
    rasters_y: u32, // ScrollingBackgroundLayer pos.y
    message: ?usize, // door whose COMING SOON is showing
    message_frames: u16,
    wants_quit: bool,
    launch: ?[]const u8, // the cart a door asked for (read by cartTag)
    launch_pending: bool, // reported to the host once, as menu.zig does

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.charly.init(A.map.START_X, A.map.START_Y);
        self.controls.init();
        self.hud.init();
        self.cam = 0;
        self.follow(); // follow() + setDeadzone(0, 0) both force a camera update
        self.banner = .{ .pos = 0, .last = @floatFromInt(self.cam), .ratio = BANNER_RATIO, .w = BANNER_W };
        self.rasters_y = 0;
        self.message = null;
        self.message_frames = 0;
        self.wants_quit = false;
        self.launch = null;
        self.launch_pending = false;

        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(A.palette);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        zg.requestSong(MUSIC);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.rasters_y = (self.rasters_y + world.RASTER_STEP) % world.RASTER_WRAP;
        self.banner.update(@floatFromInt(self.cam));
        self.charly.update(self.controls.state(), &A.collision);
        if (self.controls.fire) {
            if (doors.touching(self.charly.box())) |d| self.enter(d);
        }
        self.follow();
        self.hud.update();
        self.controls.tick();
        self.message_frames -|= 1;
        if (self.message_frames == 0) self.message = null;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb = &zigos.lfbs[0];
        world.drawRasters(fb, self.rasters_y);
        world.drawBanner(fb, self.banner.pos);
        world.drawForeground(fb, self.cam);
        world.drawCharly(fb, &self.charly, self.cam);
        self.hud.draw(fb);
        if (self.message) |d| drawMessage(zigos, d);
    }

    /// Back (6) leaves for the menu: with pollCart declared, demo_main no
    /// longer does that for us.
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == 6) self.wants_quit = true else self.controls.input(dir);
    }

    /// -1 the menu, 1 a door's cart (demo_main.pollCartRequest).
    pub fn pollCart(self: *Demo) i32 {
        if (self.wants_quit) return -1;
        if (!self.launch_pending) return 0;
        self.launch_pending = false; // the host reads cartTag in this same poll
        return 1;
    }

    pub fn cartTag(self: *Demo) []const u8 {
        return self.launch orelse "";
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) {
            self.wants_quit = true;
        } else self.controls.key(cp);
    }

    fn follow(self: *Demo) void {
        const dz = zg.tilemap.deadzone(VIEW_W, 0); // setDeadzone(0, 0) (entities.js:49)
        self.cam = zg.tilemap.followAxis(self.cam, self.charly.x, dz.lo, dz.hi, CAM_LIMIT);
    }

    // DoorEntity.onCollision: the remake changes state to the door's loader. A
    // ported screen's cart plays its own loader as it depacks; a door whose
    // screen is not ported yet says so instead.
    fn enter(self: *Demo, d: usize) void {
        if (doors.DOORS[d].tag) |tag| {
            self.launch = tag;
            self.launch_pending = true;
            return;
        }
        self.message = d;
        self.message_frames = MESSAGE_FRAMES;
    }
};

fn drawMessage(zigos: *ZigOS, d: usize) void {
    var buf: [40]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{s}: COMING SOON", .{doors.DOORS[d].title}) catch return;
    const x: i16 = @intCast((320 - @as(i32, @intCast(text.len)) * 8) >> 1);
    zigos.printText(&zigos.lfbs[0], text, x, 96, A.colors.WHITE, A.colors.BLACK);
}
