// --------------------------------------------------------------------------
// The GEM shell — a cart that boots the desktop and launches programs off the
// floppy. It is not much more than that, which is the point.
//
// Phase 2, step 2.3:
//   (a) the desktop itself moved into rom.wasm, so this links no GEM;
//   (b) launching moved to the HOST. This file used to embed st_replay.App
//       outright — every app GEM could launch was linked into GEM's own binary,
//       which does not scale past one app and is why the launch double-click
//       leaked into the app it had just started (the app was already there, so
//       the second click of the double-click landed in it).
//
// Now a program is a FILE on the mounted disk. The desktop reports which one was
// double-clicked, this shell asks the host to run it (request 3), and the host
// instantiates it as the next cart over the same memory. That is what TOS does,
// and a freshly instantiated cart cannot inherit a pointer press.
//
// Select in apps/zig/floppy.zig.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const hw = @import("hardware");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const rom = @import("rom_sdk");
const gem_inf = @import("gem_inf.zig");

const PLANE: u32 = 0; // GEM owns plane 0
const WHITE = zg.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

/// The desktop's screen (Options > Set Preferences), numbered as DESKTOP.INF's #E codes.
/// desk is the 640x480 desk mode (HW 1.17.0, docs/GEM_DESK_MODE.md), where the machine has it.
const Mode = enum(u8) { low = 0, medium = 1, desk = 2 };

pub const Demo = struct {
    mode: Mode = .low, // GEM defaults to LOW
    desk_ok: bool = false, // plane 0 has the desk buffer: the machine shows the desk mode
    desk_back: usize = 0, // the desk's second buffer (deskBuffers), 0: none yet
    fb: *LogicalFB = undefined,
    os: *ZigOS = undefined,
    plane_bg: zg.Color = WHITE, // REG_BACKGROUND before the desk: what leaving it puts back
    // The program the desktop asked us to run, held until the host polls for it.
    // 16 bytes because that is a FAT entry's name field (docs/FLOPPY_DISK.md).
    run_name: [16]u8 = [_]u8{0} ** 16,
    run_len: u8 = 0,
    fat_loaded: bool = false, // drive A's FAT disk is in the model (gem_fat.zig)
    fat_media: u32 = 0, // KOS's media-change count when it was read: a swap re-reads drive A
    c_ok: bool = false, // C: mounted (gem_fat.loadC): Save Desktop writes C:\DESKTOP.INF

    pub fn init(self: *Demo, os: *ZigOS) void {
        self.fat_loaded = false;
        self.fat_media = @import("gem_fat.zig").mediaChanges();
        self.run_len = 0;
        self.desk_back = 0; // the VRAM pool is new: no second desk buffer yet
        self.fb = &os.lfbs[0];
        self.os = os;
        self.fb.is_enabled = true;
        self.allocPlane();
        rom.installPalette(PLANE); // one palette for desktop AND apps
        os.setBackgroundColor(WHITE); // border white
        // The ROM binds the desktop to a PLANE and reads its registers; applyMode
        // below switches the resolution, which rewrites the stride, and deskSetScreen
        // re-binds. So the order here is: configure the plane, bind, then set the res.
        const back = rom.aes.returnMode(); // a program quit: its desktop's mode (initPlane forgets it)
        rom.Desktop.initPlane(PLANE, 640, 200);
        rom.Desktop.setDeskAvailable(self.desk_ok);
        // KOS's C: (docs/KOS_FAT.md F5): the SD card, if a host serves it. Before the mode is
        // set: DESKTOP.INF's C:\ window reopens at that deskSetScreen, on C:'s listing.
        self.c_ok = @import("gem_fat.zig").loadC();
        self.mode = bootMode(self.desk_ok, back);
        self.applyMode();
    }

    // ONE buffer for every mode, allocated once by the capability (DEVPAC_GAP §3b item 4):
    // the desk's 640x480 where the machine shows it (its first 640x200 / 320x200 serve MEDIUM
    // and LOW, as the medium buffer always did), else the 640-wide medium buffer.
    fn allocPlane(self: *Demo) void {
        self.desk_ok = hw.hwDeskAvailable() != 0;
        if (self.desk_ok) {
            if (self.fb.setDeskPlane()) |_| {
                self.fb.leaveDesk(); // back to a plane mode at once: init never shows a frame
                return;
            } else |_| self.desk_ok = false; // the VRAM pool is full: no desk this boot
        }
        self.fb.setMediumPlane();
    }

    // DESKTOP.INF (C:\'s, where Options > Save Desktop writes it, else the boot disk's:
    // gem_inf.zig) picks the boot mode: its #E code, the desk only where the machine has it
    // (else the default, LOW: an alert would stop a boot the user cannot answer yet). Its icons
    // and windows reach the ROM with it, and are laid out on the mode chosen here, clamped
    // (deskSetScreen). Back from a program, the mode it was launched in wins (TOS's Getrez).
    fn bootMode(desk_ok: bool, back: ?rom.aes.ScreenMode) Mode {
        const was: ?Mode = if (back) |b| @enumFromInt(@intFromEnum(b)) else null;
        var buf: [gem_inf.MAX]u8 = undefined;
        const code: ?u8 = if (gem_inf.read(&buf)) |text| rom.Desktop.loadInf(text) else null;
        const mode: Mode = was orelse if (code) |c| @enumFromInt(c) else .low;
        return if (mode == .desk and !desk_ok) .low else mode;
    }

    // GEM binds its own keys, so the host must forward rather than interpret.
    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    // Put plane 0 in `self.mode` and re-bind the desktop to it. Leaving the desk goes back to the
    // same buffer in a plane mode; entering it where it is missing keeps the mode it was in.
    // The desk's bars (80 px a side, 60 lines above and below) show REG_BACKGROUND: white, as
    // TOS's desktop is framed; leaving the desk puts back the colour it found.
    fn applyMode(self: *Demo) void {
        if (self.mode == .desk) {
            const was_desk = self.fb.isDesk();
            if (self.fb.setDeskPlane()) |_| {
                self.deskBuffers();
                if (!was_desk) self.plane_bg = self.os.getBackgroundColor();
                self.os.setBackgroundColor(WHITE);
            } else |_| {
                self.mode = if (self.fb.stride == 640) .medium else .low;
            }
        }
        if (self.mode != .desk and self.fb.isDesk()) {
            self.fb.leaveDesk();
            self.os.setBackgroundColor(self.plane_bg);
        }
        switch (self.mode) {
            .low => self.fb.setResLow(),
            .medium => self.fb.setResMedium(),
            .desk => {},
        }
        const size: [2]i32 = switch (self.mode) {
            .low => .{ 320, 200 },
            .medium => .{ 640, 200 },
            .desk => .{ hw.DESK_WIDTH, hw.DESK_HEIGHT },
        };
        rom.Desktop.setScreen(size[0], size[1]);
    }

    // The desk's second buffer: the board scans plane 0 out live there, so the ROM draws each
    // frame into the buffer not on screen and flips FB_BASE (rom/gem/desktop/deskflip.zig). With
    // no room for it in the VRAM pool the desk stays single-buffered (draws in place, may tear).
    fn deskBuffers(self: *Demo) void {
        if (self.desk_back == 0) self.desk_back = zg.deskBuffer() orelse 0; // once a boot
        rom.Desktop.setBuffers(if (self.desk_back == 0) 0 else self.fb.desk_off, self.desk_back);
    }

    fn setMode(self: *Demo, mode: Mode) void {
        self.mode = mode;
        self.applyMode();
    }

    pub fn update(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = self;
        _ = os;
        _ = dt;
        rom.Desktop.beginFrame();
    }

    pub fn render(self: *Demo, os: *ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        const action = rom.Desktop.render();
        rom.Desktop.endFrame();
        switch (action) {
            .launch => self.requestRun(),
            .res_low => self.setMode(.low),
            .res_medium => self.setMode(.medium),
            .res_desk => self.setMode(.desk),
            .save_inf => if (self.c_ok) {
                _ = gem_inf.writeC(); // a failure is logged there; the ROM's copy stays
            },
            .none => {},
        }
        @import("gem_fileop.zig").tick(); // C:'s file operations the desktop posted: a step a frame
    }

    // Ask the host to run the program the desktop picked. A disk with no program
    // on it is a no-op rather than a request the host cannot satisfy — GEM would
    // otherwise ask again every frame, which reads as a freeze.
    fn requestRun(self: *Demo) void {
        const name = rom.Desktop.launchName(&self.run_name);
        self.run_len = @intCast(name.len);
    }

    // --- the host's cart-swap protocol (see demo_main.zig) ---
    // 3 = run getCartTag* as a FILE on the mounted disk.
    pub fn pollCart(self: *Demo) i32 {
        if (self.run_len == 0) return 0;
        return 3; // the name stays put until cartTag() is read, in this same poll
    }
    pub fn cartTag(self: *Demo) []const u8 {
        return self.run_name[0..self.run_len];
    }

    // The host's coordinates as they come (physical-visible: 0..639 x 0..199, 0..479 in the
    // desk); the ROM maps them to the desktop's mode in one place (gui.Screen.fromHost), and
    // bit 1 is the loader's native double-click pulse.
    pub fn pointer(self: *Demo, x: i32, y: i32, buttons: u32) void {
        _ = self;
        rom.Desktop.hostPointer(x, y, buttons);
    }

    pub fn key(self: *Demo, cp: u32) void {
        _ = self;
        rom.Desktop.key(cp);
    }

    // Arrow keys drive the caret in an open name field.
    pub fn input(self: *Demo, dir: u32) void {
        _ = self;
        rom.Desktop.input(dir);
    }

    // The host reports whether an app-disk is inserted, and packs the mounted
    // disk's FAT into the ROM's buffer (per file: 16-byte name + 1 type + 4 size +
    // 4 date); GEM shows them as icons in the FLOPPY window.
    /// present: bits 7:0 0 none, 1 a .zmd data disk (the host hands the listing), 2 a FAT disk (KOS:
    /// this shell reads it, once per insertion, gem_fat.zig); bit 8 a real floppy (the icon's label).
    pub fn insertDisk(self: *Demo, present: u32) void {
        const kind = present & 0xFF;
        const fat = @import("gem_fat.zig");
        const media = fat.mediaChanges(); // the hosts call this every frame: read a disk once, and a new one again
        if (kind == 2 and (!self.fat_loaded or media != self.fat_media)) _ = fat.load();
        self.fat_loaded = kind == 2;
        self.fat_media = media;
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

// keyUp: a key's release. demo_main forwards none, so the shell exports its own (notepad.zig's
// pattern), guarded so only the GEM shell's cart carries it: the desktop needs Control's release,
// since a drag MOVES while it is held (rom/gem/desktop/deskkey.zig).
fn keyUp(cp: u32) callconv(.c) void {
    rom.Desktop.key(cp | rom.deskop.KEY_RELEASE);
}
comptime {
    if (@import("../cart.zig").Cart == Demo) @export(&keyUp, .{ .name = "keyUp" });
}
