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
    fb: *LogicalFB = undefined,

    pub fn init(self: *Demo, os: *ZigOS) void {
        self.* = .{}; // demo_main declares `var demo: Demo = undefined` — apply field defaults
        self.fb = &os.lfbs[0];
        self.fb.is_enabled = true;
        self.fb.setMediumPlane(); // the whole GEM (desktop + apps) is medium-res
        gem.gui.installPalette(self.fb); // one shared palette for desktop AND apps
        os.setBackgroundColor(.{ .r = 0, .g = 150, .b = 90, .a = 255 });
        self.blit.init();
        self.desktop.init(os, self.fb, &self.blit);
        self.app.init(os); // set up (but do not show) the app; host fills its sample
    }

    pub fn update(self: *Demo, os: *ZigOS, dt: f32) void {
        if (self.running) {
            self.app.update(os, dt);
            if (self.app.wants_quit) { // ejected -> desktop
                self.running = false;
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
        const launch = self.desktop.render(); // ST Replay icon clicked?
        self.desktop.g.endFrame();
        if (launch) {
            self.running = true;
            self.app.init(os); // reset transport/quit flag, keep windows + sample
        }
    }

    pub fn pointer(self: *Demo, x: i32, y: i32, buttons: u32) void {
        if (self.running) self.app.pointer(x, y, buttons) else self.desktop.setPointer(x, y, buttons);
    }

    // Forward the sample-display bridge to the hosted app so the host can fill it.
    pub fn sampleBuf(self: *Demo) [*]u8 {
        return self.app.sampleBuf();
    }
    pub fn sampleLen() usize {
        return st_replay.App.sampleLen();
    }
};
