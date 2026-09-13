// --------------------------------------------------------------------------
// The Union Demo (1989) MAIN MENU, ported from shazz's melonJS "Union Demo
// HTML5 Remake" 0.9.8 (main.js PlayScreen, entities.js). Artwork, music and
// scrolltext belong to The Union; Charly and the street are TEX's.
//
// Charly walks a 175x25 street of 32x16 tiles (data/union3.tmx); the view
// follows him horizontally; fire in front of one of the eleven doors enters a
// demo screen. Under the playfield runs the TEX scroller.
//
// The street LOOPS, unlike the remake's (its viewport clamps to the map and its
// collision stops Charly at either end): walking past one end continues from
// the other, view, banner parallax, collision and doors included.
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
const menu_loader = @import("union_demo/loading.zig"); // menuloader.js before the street

// "Union Demo MENU" is Mad Max's Alloy Run, and this is the REAL tune: the
// archive's Mad_Max/Demos/Union_Demo/SID/Alloy_Run.sndh (SID effects on MFP
// timers A/B/D). It is the same tune as the remake's U_MENU.BIN YM5! dump, at
// lag 0 (voice B's period matches on 91% of frames); the bleeps at the start of
// that dump were an artefact of sampling a SID tune once per 50 Hz frame, not
// music. It used to play SILENT here because the player loaded tunes at $0 and
// this one installs its timer vectors at $110/$120/$134, over its own code.
const MUSIC = "union/alloy_run.sndh";
const MUSIC_TUNE: u8 = 1; // the file's only subtune

const VIEW_W: i32 = 640; // me.video.init('jsapp', 640, 400) (main.js:240)
const BANNER_RATIO: f32 = 0.5; // plx_banner "ratio" property (union3.tmx)
const BANNER_W: f32 = 640; // banner4.png
const MESSAGE_FRAMES: u16 = 120;
const STEP_MS: f32 = 1000.0 / 60.0;
const STEP_DUE_MS: f32 = 10;
const STEP_DEBT_MS: f32 = 4; // STEP_DUE_MS + STEP_DEBT_MS < the shortest 60 Hz dt
const MAX_STEPS = 4; // a stalled tab catches up 4 steps, not seconds
const K_ESC: u32 = 0xE012;

pub const Demo = struct {
    charly: Charly,
    controls: Controls,
    hud: Hud,
    cam: i32, // viewport pos.x, 640 space
    banner: zg.tilemap.RatioScroll,
    rasters_y: u32, // ScrollingBackgroundLayer pos.y
    clock: f32, // ms towards the next 60 Hz step (negative: carried early time)
    message: ?usize, // door whose COMING SOON is showing
    message_frames: u16,
    wants_quit: bool,
    launch: ?[]const u8, // the cart a door asked for (read by cartTag)
    launch_pending: bool, // reported to the host once, as menu.zig does

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.charly.init(A.map.START_X, A.map.START_Y);
        self.controls.init();
        self.cam = 0;
        self.follow(); // follow() + setDeadzone(0, 0) both force a camera update
        self.banner = .{ .pos = 0, .last = @floatFromInt(self.cam), .ratio = BANNER_RATIO, .w = BANNER_W };
        self.rasters_y = 0;
        self.clock = 0;
        self.message = null;
        self.message_frames = 0;
        self.wants_quit = false;
        self.launch = null;
        self.launch_pending = false;

        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(A.palette);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        menu_loader.start(zigos); // the HUD and the music wait for the graphics
    }

    /// The remake updates on setInterval at me.sys.fps = 60 whatever the display
    /// (main.js:528, useNativeAnimFrame = false), so its speeds are per 1/60 s.
    /// The host calls once per display frame: run the 60 Hz steps that are due.
    /// A step runs once STEP_DUE_MS has built up and at most STEP_DEBT_MS of early
    /// time is carried, so a 60 Hz display gets exactly one step every frame (dt
    /// jitter included) and a 144 Hz one gets 60 a second, not 144.
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        switch (menu_loader.step(zigos)) {
            .loading => return,
            .failed => {
                self.wants_quit = true;
                return;
            },
            .ready => { // PlayScreen.onResetEvent: the HUD, then the menu music
                self.hud.init();
                zg.requestSongTune(MUSIC, MUSIC_TUNE);
            },
            .running => {},
        }
        // The loader's frames are not the street's: the clock starts on .ready, so
        // that frame runs the street's first step, as it did before the clock.
        self.clock += if (std.math.isNan(dt) or dt < 0) STEP_MS else @min(dt, MAX_STEPS * STEP_MS);
        var steps: u8 = 0;
        while (self.clock >= STEP_DUE_MS and steps < MAX_STEPS) : (steps += 1) {
            self.step();
            self.clock = @max(self.clock - STEP_MS, -STEP_DEBT_MS);
        }
    }

    fn step(self: *Demo) void {
        self.rasters_y = (self.rasters_y + world.RASTER_STEP) % world.RASTER_WRAP;
        self.banner.update(@floatFromInt(self.cam));
        const wrapped = self.charly.update(self.controls.state(), &A.collision);
        // round, not truncate: x - unwrapped is a street-length only up to f32
        // error, and 5599.9995 must still shift the view by 5600.
        if (wrapped != 0) self.shiftView(@intFromFloat(@round(wrapped)));
        if (self.controls.fire) {
            if (doors.touching(self.charly.box())) |d| self.enter(d);
        }
        self.follow();
        self.hud.update();
        self.controls.tick(STEP_MS);
        self.message_frames -|= 1;
        if (self.message_frames == 0) self.message = null;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        if (menu_loader.blocking()) return; // the loader panel owns the plane
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

    /// Key-up of a Direction, from a host that sends it (demo_main.inputRelease).
    pub fn inputRelease(self: *Demo, dir: u8) void {
        self.controls.release(dir);
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

    // Viewport._followH with setDeadzone(0, 0) (entities.js:49), minus its clamp
    // to [0, map - view]: on a looping street the view keeps Charly centred
    // across the seam. floor instead of ~~ agrees on every view melonJS could
    // reach (>= 0) and stays continuous below 0, where the start of the street
    // shows the end of it.
    fn follow(self: *Demo) void {
        const dz = zg.tilemap.deadzone(VIEW_W, 0);
        const rel = self.charly.x - @as(f32, @floatFromInt(self.cam));
        const edge: ?i32 = if (rel > @as(f32, @floatFromInt(dz.hi))) dz.hi else if (rel < @as(f32, @floatFromInt(dz.lo))) dz.lo else null;
        if (edge) |e| self.cam = @intFromFloat(@floor(self.charly.x - @as(f32, @floatFromInt(e))));
    }

    // Charly crossed an end and his x jumped a street-length: the view and the
    // banner's last-seen view jump with him, so neither scrolls.
    fn shiftView(self: *Demo, by: i32) void {
        self.cam += by;
        self.banner.last += @floatFromInt(by);
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
