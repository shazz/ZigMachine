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
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const rom = @import("rom_sdk");

const PLANE: u32 = 0; // GEM owns plane 0

pub const Demo = struct {
    desk_medium: bool = false, // desktop resolution (Options menu); GEM defaults to LOW
    fb: *LogicalFB = undefined,
    // The program the desktop asked us to run, held until the host polls for it.
    // 16 bytes because that is a FAT entry's name field (docs/FLOPPY_DISK.md).
    run_name: [16]u8 = [_]u8{0} ** 16,
    run_len: u8 = 0,

    pub fn init(self: *Demo, os: *ZigOS) void {
        self.desk_medium = false;
        self.run_len = 0;
        self.fb = &os.lfbs[0];
        self.fb.is_enabled = true;
        self.fb.setMediumPlane(); // allocate the 640-wide buffer once (serves LOW and MEDIUM)
        rom.installPalette(PLANE); // one palette for desktop AND apps
        os.setBackgroundColor(.{ .r = 255, .g = 255, .b = 255, .a = 255 }); // border white
        // The ROM binds the desktop to a PLANE and reads its registers; applyDeskRes
        // below switches the resolution, which rewrites the stride, and deskSetScreen
        // re-binds. So the order here is: configure the plane, bind, then set the res.
        rom.Desktop.initPlane(PLANE, 640, 200);
        self.applyDeskRes();
    }

    // GEM binds its own keys, so the host must forward rather than interpret.
    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    fn applyDeskRes(self: *Demo) void {
        if (self.desk_medium) self.fb.setResMedium() else self.fb.setResLow();
        rom.Desktop.setScreen(if (self.desk_medium) 640 else 320, 200);
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

    pub fn pointer(self: *Demo, x: i32, y: i32, buttons: u32) void {
        // The host sends physical-visible coords (0..640). Medium logical is 640
        // (1:1); low logical is 320, so halve X. Y is 200 in both.
        const lx = if (self.desk_medium) x else @divTrunc(x, 2);
        if (buttons & 2 != 0) {
            rom.Desktop.requestOpenAt(lx, y); // native double-click pulse from the loader
        } else {
            rom.Desktop.setPointer(lx, y, buttons);
        }
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
