// --------------------------------------------------------------------------
// SysInfo — the ZigMachine's take on SysInfo for the Atari ST (HWAM, version
// 8.34, 1992; atari-wiki.co.uk "SysInfo"): a full-screen medium-res page of
// what the machine reports about itself, two columns of "LABEL : value" under
// underlined headings, and a GEM dialog (Space or a click) to pick the page:
// system & memory, video, sound, disk, and speed tests against a stock ST.
//
// Like ST Replay it is an application on the ROM's GEM toolkit (rom_sdk): the
// drawing, the dialog and the alert are the ROM's, through handles. Unlike
// ST Replay it boots from its own disk; quitting goes back to the OS (GEM).
// Input is sysinfo/control.zig's. It reads the machine only through what a cart is given (sysinfo/probe.zig),
// so the same cart links lean for the KESTREL board; what is not given reads
// n/a. On the board every store is a blocking DDR write, so the glass is
// written only where a page changed (sysinfo/grid.zig + screen.zig), and live
// values are re-read twice a second, as SysInfo's own refresh clock did.
//
// NOTE: HWAM's title line carries its own copyright; this is a homage, not
// their program, so it names itself and credits the original instead.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const rom = @import("rom_sdk");
const grid = @import("sysinfo/grid.zig");
const screen = @import("sysinfo/screen.zig");
const pages = @import("sysinfo/pages.zig");
const probe = @import("sysinfo/probe.zig");
const menu = @import("sysinfo/menu.zig");
const control = @import("sysinfo/control.zig");
const bench = @import("sysinfo/bench.zig");
const k = @import("sysinfo/kernels.zig");
const diskinfo = @import("sysinfo/diskinfo.zig");

const PLANE: u32 = 0;
const SPARE_PLANE: usize = 3; // the blitter probe's 8 pixels: never enabled
const REFRESH_FRAMES: u32 = 30; // live values twice a second

pub const App = struct {
    os: *ZigOS,
    g: rom.Gui,
    dialog: rom.Dialog,
    blit: zg.Blitter,
    page: pages.Page,
    want: grid.Grid, // what the page says now
    shown: grid.Grid, // what is on the glass
    bench: bench.Bench,
    scratch: *[k.SCATTER_BYTES]u8,
    disk: ?diskinfo.Info,
    files: [pages.MAX_FILES]pages.File,
    nfiles: u8,
    blit_probe: probe.Blit,
    menu_open: bool,
    menu_drawn: bool,
    covered: bool, // a dialog or the menu drew over the page: repaint it all
    dirty: bool, // compose this frame, not at the next refresh
    frames: u32,
    last_us: u32,
    last_frames: u32,
    frame_us: u32,
    wants_quit: bool,

    pub fn init(self: *App, os: *ZigOS) void {
        self.os = os;
        const fb = &os.lfbs[PLANE];
        // A standalone cart: the plane is ours to bring up, BEFORE the ROM binds
        // a context to it (it reads the plane's registers), as ST Replay does.
        fb.is_enabled = true;
        fb.setMediumPlane();
        fb.setResMedium();
        self.g.close(); // memory reused across a cart swap may hold a stale handle
        self.dialog.close();
        self.g = rom.Gui.openPlane(PLANE, screen.SW, screen.SH);
        self.dialog = rom.Dialog.open();
        rom.installPalette(PLANE);
        os.setBackgroundColor(fb.getPaletteEntry(rom.WHITE)); // an ST's border is colour 0, GEM's white
        self.blit = .{};
        self.blit.init();
        self.blit_probe = probe.blitterTest(&self.blit, &os.lfbs[SPARE_PLANE]);
        self.readDisk();
        self.scratch = zg.mem.mustAlloc(u8, k.SCATTER_BYTES)[0..k.SCATTER_BYTES];
        self.bench.reset();
        self.bench.warmUp(self.target());
        self.resetState();
    }

    fn resetState(self: *App) void {
        self.page = .system;
        self.menu_open = false;
        self.menu_drawn = false;
        self.covered = true; // the first frame paints the paper and the whole page
        self.dirty = true;
        self.frames = 0;
        self.last_us = 0;
        self.last_frames = 0;
        self.frame_us = 0;
        self.wants_quit = false;
    }

    /// The mounted disk, once: its descriptor and its FAT, through the drive.
    fn readDisk(self: *App) void {
        self.disk = probe.readDisk();
        self.nfiles = 0;
        const lay = zg.disk.mount() orelse return;
        var i: u16 = 0;
        while (i < lay.count and self.nfiles < pages.MAX_FILES) : (i += 1) {
            const e = zg.disk.entryAt(lay, i) orelse continue;
            self.files[self.nfiles] = .{ .name = e.name, .len = e.e.len, .kind = e.e.kind };
            self.nfiles += 1;
        }
    }

    pub fn ownsKeyboard(self: *App) u32 {
        _ = self;
        return 1; // a GEM application: Space is the menu, not the host's Fire
    }

    /// The host's swap protocol (demo_main.zig): 4 = back to the OS.
    pub fn pollCart(self: *App) i32 {
        return if (self.wants_quit) 4 else 0;
    }

    pub fn pointer(self: *App, x: i32, y: i32, buttons: u32) void {
        self.g.setPointer(x, y, buttons);
    }

    pub fn key(self: *App, cp: u32) void {
        control.key(self, cp);
    }

    pub fn input(self: *App, dir: u32) void {
        control.input(self, dir);
    }

    pub fn setShadeMode(self: *App, mode: u32) void {
        control.digit(self, mode);
    }

    pub fn update(self: *App, os: *ZigOS, dt: f32) void {
        _ = os;
        _ = dt; // the host's pace is measured with its clock (tick), not read from dt
        self.g.beginFrame();
        self.frames +%= 1;
        if (self.dialog.active()) return;
        control.click(self);
        if (self.page == .speed and self.bench.running()) {
            self.bench.step(self.target());
            self.dirty = true;
        }
    }

    pub fn render(self: *App, os: *ZigOS, dt: f32) void {
        _ = os;
        _ = dt;
        defer self.g.endFrame();
        if (self.dialog.active()) {
            _ = self.dialog.process(self.g);
            self.covered = true;
            return;
        }
        if (self.menu_open) {
            if (!self.menu_drawn) menu.draw(self.g);
            self.menu_drawn = true;
            return;
        }
        if (self.covered) screen.blank(self.g, &self.shown);
        const due = self.frames % REFRESH_FRAMES == 0;
        if (due) self.tick();
        if (!(self.covered or self.dirty or due)) return;
        self.compose();
        screen.flush(self.g, &self.want, &self.shown);
        self.covered = false;
        self.dirty = false;
    }

    fn target(self: *App) bench.Target {
        return .{ .os = self.os, .blit = &self.blit, .scratch = self.scratch };
    }

    /// The host's real frame period, averaged since the last tick.
    fn tick(self: *App) void {
        const now = bench.micros();
        const n = self.frames -% self.last_frames;
        if (now != 0 and self.last_us != 0 and n != 0) self.frame_us = (now -% self.last_us) / n;
        self.last_us = now;
        self.last_frames = self.frames;
    }

    fn compose(self: *App) void {
        const c = pages.Ctx{
            .os = self.os,
            .bench = &self.bench,
            .blit = self.blit_probe,
            .disk = self.disk,
            .files = self.files[0..self.nfiles],
            .gem_ok = self.g.h != 0,
            .dialog_ok = self.dialog.h != 0,
            .frame_us = self.frame_us,
        };
        pages.compose(&self.want, self.page, &c);
    }
};
