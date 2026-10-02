// --------------------------------------------------------------------------
// NAOS / THE NITROWAVE DEMO (Atari ST, 29-06-1990), made for the Generation 4
// demo competition (theme: the 3615 GEN4 minitel server). Code by Freddi,
// Aragorn and Ric, graphics by ATM, music by Mad Max and AN Cool: all theirs.
//
// Ported from the DISK (NITROWAV.MSA, fujiology; prototypes/naos_nitrowave_re/
// NOTES.md), not from a remake: AUTO/MENU.PRG is the BATTLETEC menu, and F1 /
// F2 / F3 load DEMO_RIC.BIN (multisprites), B_SPRITE.BIN (big sprite +
// overscan) and DAMIER3D.BIN (Sapristi 3615 GEN 4) to fixed addresses.
//
// PORTED, each frame for frame as Hatari shows the original:
//   menu  the fullscreen picture and Freddi's sprite scroller (menu*.zig)
//   F2    Aragorn's big sprite over the overscan tiles (bspr*.zig)
//   F3    Aragorn's checkerboards, parallax landscape, logo and scroller,
//         with its colour-register writes along the lines (dam*.zig)
// Not shown: the menu's machine test before it (the overscan routine generated
// three ways while the screen stays black) and the floppy loads (~30 s black).
// F1 (Ric's multisprites, interrupt-driven, Timer B rasters) is not ported.
//
// Keys: menu F2 -> the big sprite, F3 -> Sapristi. In a part, 'F' freezes it
// (the original's key) and Space or Return goes back to the menu (the original
// reboots, and the disk boots the menu again from its start). Space in the
// menu leaves, as the original quits to the desktop; Escape too.
//
// MUSIC (prototypes/naos_nitrowave_re/NOTES.md, "Music"): every program carries
// its own TFMX replay and module; each rip plays on the sealed YM
// (apps/sndh_headless.mjs) and matches an archive SNDH register for register
// (ymcheck.sh: identical frames at a 2-frame lag):
//   menu  big_sprite.sndh #1 (Mad_Max/Demos/Cuddly_Demos/Big_Sprite)       0.999
//   F2    so_watt_no_crew.sndh #1 (Mad_Max/Demos/So_Watt/So_Watt_No_Crew)  1.000
//   F3    so_watt_techatron.sndh #1 (AN_Cool/So_Watt-Techatron)            0.999
// --------------------------------------------------------------------------
const zg = @import("zigos");
const st = @import("naos_nitrowave/st.zig");
const assets = @import("naos_nitrowave/assets.zig");
const show = @import("naos_nitrowave/show.zig");
const dam_show = @import("naos_nitrowave/dam_show.zig");
const M = @import("naos_nitrowave/menu.zig");
const B = @import("naos_nitrowave/bspr.zig");
const D = @import("naos_nitrowave/dam.zig");

const ZigOS = zg.ZigOS;

const K_SPACE: u32 = 32;
const K_RETURN: u32 = 13;
const K_ESC: u32 = 0xE012;
const K_F2: u32 = 0xE002;
const K_F3: u32 = 0xE003;
const BSPR_LINES = show.Lines{ .first = 0, .end = 255 };
/// Host frames run at their own rate; a part runs one VBL per 20 ms, catching
/// up at most this many in one host frame (a stalled tab does not replay a
/// minute of VBLs).
const MAX_VBLS_PER_FRAME = 4;

/// The program on screen: the disk image's name for it is its assets set.
pub const Part = assets.Set;

pub const Demo = struct {
    ram: st.Ram,
    fb: *zg.LogicalFB,
    part: Part,
    menu: M.Menu,
    bspr: B.Bspr,
    dam: D.Dam,
    acc: f32,
    ok: bool, // the part on screen depacked
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.wants_quit = false;
        self.ram = assets.ram();
        zigos.setBackgroundColor(st.color(0));
        self.fb = &zigos.lfbs[0];
        self.fb.is_enabled = true;
        self.fb.clearFrameBuffer(0);
        self.go(.menu);
    }

    pub fn update(_: *Demo, _: *ZigOS, _: f32) void {}

    pub fn render(self: *Demo, _: *ZigOS, dt: f32) void {
        if (!self.ok) return;
        self.acc = @min(self.acc + dt, st.VBL_MS * MAX_VBLS_PER_FRAME);
        while (self.acc >= st.VBL_MS) : (self.acc -= st.VBL_MS) self.vbl();
        const px = self.fb.fb[0 .. @as(usize, zg.PHYSICAL_WIDTH) * zg.PHYSICAL_HEIGHT];
        switch (self.part) {
            .menu => {
                show.present(&self.ram, self.menu.displayed, show.MENU_LINES, px);
                show.menuStars(px);
            },
            .bspr => show.present(&self.ram, self.bspr.displayed, BSPR_LINES, px),
            .dam => dam_show.present(&self.ram, self.dam.displayed, px),
        }
    }

    fn vbl(self: *Demo) void {
        switch (self.part) {
            .menu => self.menu.frame(&self.ram),
            .bspr => self.bspr.frame(&self.ram),
            .dam => self.dam.frame(&self.ram),
        }
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) return self.quit();
        const freeze = cp == 'f' or cp == 'F';
        switch (self.part) {
            .menu => {
                if (cp == K_SPACE) return self.quit();
                if (cp == K_F2) self.go(.bspr);
                if (cp == K_F3) self.go(.dam);
                return;
            },
            .bspr => if (freeze) self.bspr.toggleFreeze(),
            .dam => if (freeze) self.dam.toggleFreeze(&self.ram),
        }
        if (cp == K_SPACE or cp == K_RETURN) self.go(.menu);
    }

    fn quit(self: *Demo) void {
        self.wants_quit = true;
    }

    /// A program "loaded off the disk": its image into the part memory, its own
    /// set-up, its palette (F3's: per row, from its HBL) and its tune.
    fn go(self: *Demo, part: Part) void {
        self.part = part;
        self.acc = 0;
        self.ok = assets.load(&self.ram, part);
        if (!self.ok) return zg.Console.log("naos_nitrowave: the {s} image does not depack", .{@tagName(part)});
        self.fb.openBorders(.all);
        switch (part) {
            .menu => {
                self.menu.enter(&self.ram);
                show.palette(&self.ram, M.PALETTE, self.fb);
                zg.requestSongTune("big_sprite.sndh", 1);
            },
            .bspr => {
                self.bspr.enter(&self.ram);
                show.palette(&self.ram, B.PALETTE, self.fb);
                zg.requestSongTune("so_watt_no_crew.sndh", 1);
            },
            .dam => {
                self.dam.enter();
                self.fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, dam_show.hbl);
                zg.requestSongTune("so_watt_techatron.sndh", 1);
            },
        }
    }
};
