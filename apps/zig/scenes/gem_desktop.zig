// --------------------------------------------------------------------------
// The GEM shell — a cart that BOOTS the desktop, and almost nothing else.
//
// Phase 2, step 2.3: the desktop itself now lives in rom.wasm. This file used to
// be GEM's top level AND the container for the app it launched (it embedded
// st_replay.App outright, so every app GEM could launch was linked into GEM's own
// binary). Now it forwards frames and input across the ROM ABI and owns exactly
// two pieces of state: which resolution the desktop is in, and whether an app is
// running.
//
// It links NO GEM: `rom_sdk` is a header of extern declarations. That is the
// whole point — the toolkit exists once, in the chip.
//
// Select in apps/zig/floppy.zig.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const rom = @import("rom_sdk");
const st_replay = @import("st_replay.zig");

pub const Demo = struct {
    app: st_replay.App = .{},
    running: bool = false,
    desk_medium: bool = false, // desktop resolution (Options menu); GEM defaults to LOW
    fb: *LogicalFB = undefined,

    pub fn init(self: *Demo, os: *ZigOS) void {
        // Field defaults WITHOUT `self.* = .{}`: Demo embeds st_replay.App, whose
        // sample buffer would then be emitted a SECOND time as a data segment.
        // That cost 517 KB of the cart's RAM window until 2026-09-12.
        self.running = false;
        self.desk_medium = false;
        self.fb = &os.lfbs[0];
        self.fb.is_enabled = true;
        self.fb.setMediumPlane(); // allocate the 640-wide buffer once (serves LOW and MEDIUM)
        rom.installPalette(@intCast(@intFromPtr(self.fb))); // one palette for desktop AND apps
        os.setBackgroundColor(.{ .r = 255, .g = 255, .b = 255, .a = 255 }); // border white
        rom.Desktop.init(os, self.fb);
        self.app.init(os); // set up (but do not show) the app
        // A scene can opt to boot straight into the app (skip the GEM desktop) by
        // declaring `pub const BOOT_DIRECT = true;`. File > Quit still drops back
        // to the desktop. Default: show the desktop first.
        if (@hasDecl(st_replay, "BOOT_DIRECT") and st_replay.BOOT_DIRECT) {
            self.launchApp(os);
        } else {
            self.applyDeskRes(); // start at the desktop's resolution (low)
        }
    }

    fn launchApp(self: *Demo, os: *ZigOS) void {
        self.running = true;
        self.fb.setResMedium(); // ST Replay is a medium-res app
        self.app.init(os); // reset transport/quit flag, keep windows + sample
    }

    // GEM and anything it launches bind their own keys — Esc stops ST Replay's
    // replay, Space is its transport — so the host must forward, not interpret.
    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    fn applyDeskRes(self: *Demo) void {
        if (self.desk_medium) self.fb.setResMedium() else self.fb.setResLow();
        rom.Desktop.setScreen(if (self.desk_medium) 640 else 320, 200);
    }

    pub fn update(self: *Demo, os: *ZigOS, dt: f32) void {
        if (self.running) {
            self.app.update(os, dt);
            if (self.app.wants_quit) { // ejected -> back to the desktop (its resolution)
                self.running = false;
                self.applyDeskRes();
                rom.Desktop.beginFrame();
            }
        } else {
            rom.Desktop.beginFrame();
        }
    }

    pub fn render(self: *Demo, os: *ZigOS, dt: f32) void {
        if (self.running) {
            self.app.render(os, dt);
            return;
        }
        const action = rom.Desktop.render();
        rom.Desktop.endFrame();
        switch (action) {
            .launch => self.launchApp(os),
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
        if (self.running) {
            self.app.pointer(lx, y, buttons);
        } else if (buttons & 2 != 0) {
            rom.Desktop.requestOpenAt(lx, y); // native double-click pulse from the loader
        } else {
            rom.Desktop.setPointer(lx, y, buttons);
        }
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (self.running) self.app.key(cp) else rom.Desktop.key(cp);
    }

    // Arrow keys: the running app moves its selection; on the desktop they drive
    // the caret in an open name field.
    pub fn input(self: *Demo, dir: u32) void {
        if (self.running) self.app.input(dir) else rom.Desktop.input(dir);
    }

    // The host reports whether an app-disk is inserted, and packs the mounted
    // disk's FAT into the ROM's buffer (per file: 16-byte name + 1 type + 4 size +
    // 4 date); GEM shows them as icons in the FLOPPY window.
    pub fn insertDisk(self: *Demo, present: u32) void {
        _ = self;
        rom.Desktop.setDiskApp(present);
    }
    pub fn diskDirPtr(self: *Demo) [*]u8 {
        _ = self;
        return rom.Desktop.dirPtr();
    }
    pub fn setDiskFileCount(self: *Demo, n: u32) void {
        _ = self;
        rom.Desktop.setFileCount(n);
    }
};
