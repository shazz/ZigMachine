// --------------------------------------------------------------------------
// NAOS / THE NITROWAVE DEMO (Atari ST, 29-06-1990), made for the Generation 4
// demo competition (theme: the 3615 GEN4 minitel server). Code by Freddi,
// Aragorn and Ric, graphics by ATM, music by Mad Max: all theirs.
//
// Ported from the DISK (NITROWAV.MSA, fujiology; prototypes/naos_nitrowave_re/
// NOTES.md), not from a remake: AUTO/MENU.PRG is the BATTLETEC menu, and F1 /
// F2 / F3 load DEMO_RIC.BIN (multisprites), B_SPRITE.BIN (big sprite +
// overscan) and DAMIER3D.BIN (Sapristi 3615 GEN 4) to fixed addresses.
//
// PORTED: the menu (menu.zig, menu_vbl.zig, show.zig) -- its fullscreen
// picture and Freddi's sprite scroller, frame for frame as Hatari shows the
// original. The menu's machine test before it (the overscan routine generated
// three ways while the screen stays black) is not shown.
//
// Keys: Space leaves (the original's Space quits to the desktop); Escape too.
//
// MUSIC (prototypes/naos_nitrowave_re/NOTES.md, "Music"): every program carries
// its own Mad Max TFMX replay and module; each rip plays on the sealed YM
// (apps/sndh_headless.mjs) and matches an archive SNDH register for register:
//   menu   big_sprite.sndh #1 (Mad_Max/Demos/Cuddly_Demos/Big_Sprite): 0.999
//          of 1500 frames identical at a 2-frame lag
// --------------------------------------------------------------------------
const zg = @import("zigos");
const st = @import("naos_nitrowave/st.zig");
const assets = @import("naos_nitrowave/assets.zig");
const show = @import("naos_nitrowave/show.zig");
const Menu = @import("naos_nitrowave/menu.zig").Menu;
const M = @import("naos_nitrowave/menu.zig");

const ZigOS = zg.ZigOS;

const K_SPACE: u32 = 32;
const K_ESC: u32 = 0xE012;
const MENU_TUNE = "big_sprite.sndh";
/// Host frames run at their own rate; a part runs one VBL per 20 ms, catching
/// up at most this many in one host frame (a stalled tab does not replay a
/// minute of VBLs).
const MAX_VBLS_PER_FRAME = 4;

pub const Demo = struct {
    ram: st.Ram,
    menu: Menu,
    acc: f32,
    ok: bool, // the menu depacked
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.acc = 0;
        self.wants_quit = false;
        self.ram = assets.ram();
        self.ok = assets.load(&self.ram, .menu);
        if (!self.ok) zg.Console.log("naos_nitrowave: the menu does not depack", .{});
        if (self.ok) self.menu.enter(&self.ram);
        zigos.setBackgroundColor(st.color(0));
        const fb = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.openBorders(.all);
        if (self.ok) show.palette(&self.ram, M.PALETTE, fb);
        fb.clearFrameBuffer(0);
        zg.requestSongTune(MENU_TUNE, 1);
    }

    pub fn update(_: *Demo, _: *ZigOS, _: f32) void {}

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        if (!self.ok) return;
        self.acc = @min(self.acc + dt, st.VBL_MS * MAX_VBLS_PER_FRAME);
        while (self.acc >= st.VBL_MS) : (self.acc -= st.VBL_MS) self.menu.frame(&self.ram);
        const fb = &zigos.lfbs[0];
        show.present(&self.ram, self.menu.displayed, fb.fb[0 .. @as(usize, zg.PHYSICAL_WIDTH) * zg.PHYSICAL_HEIGHT]);
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_SPACE or cp == K_ESC) self.wants_quit = true;
    }
};
