// --------------------------------------------------------------------------
// ZigGEM boot — the desktop shell. This is the "boot ROM" front end: it brings
// up the medium-res GEM desktop and hosts applications. An app (the RAM
// cartridge, apps/scenes/st_replay.zig) is launched from a desktop icon, runs
// full-screen using the ROM's GUI libraries (zg.gem.gui), and File > Quit ejects
// it back to the desktop.
//
// This scene owns the plane/palette (once) and routes the host callbacks
// (init/update/render/pointer) to either the desktop or the running app.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Blitter = zg.Blitter;
const gem = zg.gem;
const st_replay = @import("st_replay.zig");

pub const Demo = struct {
    blit: Blitter = .{},
    desktop: gem.Desktop = .{},
    app: st_replay.App = .{},
    running: bool = false,
    desk_medium: bool = false, // desktop resolution (Options menu); GEM defaults to LOW
    fb: *LogicalFB = undefined,

    pub fn init(self: *Demo, os: *ZigOS) void {
        self.* = .{}; // demo_main declares `var demo: Demo = undefined` — apply field defaults
        self.fb = &os.lfbs[0];
        self.fb.is_enabled = true;
        self.fb.setMediumPlane(); // allocate the 640-wide buffer once (serves both LOW and MEDIUM)
        gem.gui.installPalette(self.fb); // one shared palette for desktop AND apps
        os.setBackgroundColor(.{ .r = 255, .g = 255, .b = 255, .a = 255 }); // GEM: border white, desktop green
        self.blit.init();
        self.desktop.init(os, self.fb, &self.blit);
        self.app.init(os); // set up (but do not show) the app; host fills its sample
        self.applyDeskRes(); // start at the desktop's resolution (low)
    }

    fn applyDeskRes(self: *Demo) void {
        if (self.desk_medium) self.fb.setResMedium() else self.fb.setResLow();
        self.desktop.g.screen_w = if (self.desk_medium) 640 else 320;
        self.desktop.g.screen_h = 200;
        self.desktop.clampIcons(); // keep icons on-screen at the new width
    }

    pub fn update(self: *Demo, os: *ZigOS, dt: f32) void {
        if (self.running) {
            self.app.update(os, dt);
            if (self.app.wants_quit) { // ejected -> back to the desktop (its resolution)
                self.running = false;
                self.applyDeskRes();
                self.desktop.beginFrame();
            }
        } else {
            self.desktop.beginFrame();
        }
    }

    pub fn render(self: *Demo, os: *ZigOS, dt: f32) void {
        if (self.running) {
            self.app.render(os, dt);
            return;
        }
        const action = self.desktop.render();
        self.desktop.endFrame();
        switch (action) {
            .launch => {
                self.running = true;
                self.fb.setResMedium(); // ST Replay is a medium-res app
                self.app.init(os); // reset transport/quit flag, keep windows + sample
            },
            .res_low => {
                self.desk_medium = false;
                self.applyDeskRes();
            },
            .res_medium => {
                self.desk_medium = true;
                self.applyDeskRes();
            },
            .none => {},
        }
    }

    pub fn pointer(self: *Demo, x: i32, y: i32, buttons: u32) void {
        // The host sends physical-visible coords (0..640). Medium logical is 640
        // (1:1); low logical is 320, so halve X. Y is 200 in both. The running app
        // is always medium.
        const medium = self.running or self.desk_medium;
        const lx = if (medium) x else @divTrunc(x, 2);
        if (self.running) self.app.pointer(lx, y, buttons) else self.desktop.setPointer(lx, y, buttons);
    }

    // Forward the sample-display bridge to the hosted app so the host can fill it.
    pub fn sampleBuf(self: *Demo) [*]u8 {
        return self.app.sampleBuf();
    }
    pub fn sampleLen() usize {
        return st_replay.App.sampleLen();
    }
};
