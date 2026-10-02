// --------------------------------------------------------------------------
// DUNE -- GEN4 DEMO (Atari ST, 29 June 1990), for the 3615 GEN4 contest. Code
// by Hades, graphics by Black Eagle, music by 520 (Demozoo; the YM tune's SNDH
// and the demo's own scroller credit Mr X for it). All of it is theirs.
//
// Ported from the ORIGINAL DISK (fujiology DUNEGEN4.MSA; RE notes, tools and
// Hatari measurements in prototypes/dune_gen4_re/NOTES.md), run from the
// desktop; DUNE.PRG's JEK Packer 1.3 depacking screen is not reproduced.
//
// THE SHOW, as DUNE.PRG runs it:
//   1. intro      INTRO.TNY's logo bounced down the screen        intro.zig
//   2. main part  the logo parked, "3615 GEN4" bouncing over grey  mainpart.zig
//                 colour-0 bars in a colour-8 rainbow, a scroller
//                 in the lower border; to the text's end or Space
//   3. title      DUNE.TNY faded in; Space                        (here)
//   4. menu       MENU.TNY, rainbow rasters, a scroller            menu.zig
//                 F1 -> the BLACK letters                          black.zig
//                 F2 -> the HADES screen                           hades.zig
//                 F3 -> the Quartet sound screen: NOT PORTED (four
//                       SingSong sample tunes; no replay here)
//   Space leaves F1 or F2 for the menu, loaded and faded in again. Escape
//   leaves the cart (not in the original).
//
// MUSIC. MUSIQUE.PRG at $10000 is Gen4.sndh's tune (TITL "Gen4 Demo", ~y),
// byte for byte bar relocations: the main part plays it. The title plays a
// Quartet tune (SINGSONG.PRG): silent here. For the menu DUNE.PRG pokes three
// sequence pointers ($10024.. over $1000C..) and starts it again:
// dune_gen4_menu.sndh is Gen4.sndh with that same poke.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const st = @import("dune_gen4/st.zig");
const tny = @import("dune_gen4/tny.zig");
const fade = @import("dune_gen4/fade.zig");
const A = @import("dune_gen4/assets.zig");
const Intro = @import("dune_gen4/intro.zig").Intro;
const MainPart = @import("dune_gen4/mainpart.zig").MainPart;
const Menu = @import("dune_gen4/menu.zig").Menu;
const black = @import("dune_gen4/black.zig");
const Hades = @import("dune_gen4/hades.zig").Hades;

const ZigOS = zg.ZigOS;
const MUSIC = "dune_gen4.sndh";
const MENU_MUSIC = "dune_gen4_menu.sndh";
const VBL_MS: f32 = 20.0; // the ST's 50 Hz
const MAX_VBLS = 4; // per host frame, after a stall

const K_SPACE: u32 = 32;
const K_ESC: u32 = 0xE012;
const K_F1: u32 = 0xE001;
const K_F2: u32 = 0xE002;

pub const Part = enum(u8) { intro, main, title, menu, black, hades };

/// The picture of the part on show (the original decodes into the screen).
var pic: tny.Picture = undefined;

pub const Demo = struct {
    part: Part,
    acc: f32,
    title_n: u32,
    menu_music: bool,
    ok: bool, // every picture decoded
    wants_quit: bool,
    fb: *zg.LogicalFB,
    intro: Intro,
    main: MainPart,
    menu: Menu,
    black: black.Black,
    hades: Hades,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.fb = st.init(zigos);
        self.acc = 0;
        self.title_n = 0;
        self.menu_music = false;
        self.wants_quit = false;
        self.black.init();
        self.menu.init();
        self.hades.init();
        self.ok = true;
        self.part = .intro;
        self.intro.init();
        self.load(A.INTRO_TNY);
    }

    pub fn update(_: *Demo, _: *ZigOS, _: f32) void {}

    pub fn render(self: *Demo, _: *ZigOS, dt: f32) void {
        self.acc += dt;
        var n: u32 = 0;
        while (self.acc >= VBL_MS and n < MAX_VBLS) : (n += 1) {
            self.acc -= VBL_MS;
            self.vbl();
        }
        if (n == MAX_VBLS) self.acc = 0;
        self.draw();
    }

    fn vbl(self: *Demo) void {
        switch (self.part) {
            .intro => if (self.intro.vbl()) {
                self.toMain();
                self.main.vbl();
            },
            .main => {
                self.main.vbl();
                if (self.main.done()) self.toTitle();
            },
            .title => self.title_n += 1,
            .menu => {
                self.menu.vbl();
                if (self.menu.ready() and !self.menu_music) {
                    self.menu_music = true;
                    zg.requestSong(MENU_MUSIC);
                }
            },
            .black => self.black.vbl(),
            .hades => {
                self.hades.vbl(&self.menu.scroll.rows);
                // the menu's VBL stays until F2's own is installed
                if (!self.hades.running()) self.menu.vbl();
            },
        }
    }

    fn draw(self: *Demo) void {
        if (!self.ok) {
            st.clear(self.fb);
            return st.setPalette(&[_]u16{0} ** 16);
        }
        switch (self.part) {
            .intro => self.intro.render(self.fb, &pic),
            .main => self.main.render(self.fb),
            .title => {
                const pal = fade.at(&pic.palette, self.title_n, fade.SCREEN);
                st.setPalette(&pal);
            },
            .menu => self.menu.render(self.fb),
            .black => self.black.render(self.fb, &pic),
            .hades => if (self.hades.running()) self.hades.render(self.fb) else self.menu.render(self.fb),
        }
    }

    fn load(self: *Demo, file: []const u8) void {
        if (!tny.decode(file, &pic)) {
            self.ok = false;
            zg.Console.log("dune_gen4: a Tiny picture does not decode", .{});
        }
    }

    fn toMain(self: *Demo) void {
        self.part = .main;
        self.main.enter(self.fb, &pic);
        zg.requestSong(MUSIC);
    }

    fn toTitle(self: *Demo) void {
        self.part = .title;
        self.title_n = 0;
        zg.stopSong(); // $10004; the Quartet tune that follows is not ported
        self.load(A.DUNE_TNY);
        st.clear(self.fb);
        st.copyRows(self.fb, &pic.px, 0, 0, st.H);
    }

    fn toMenu(self: *Demo) void {
        self.part = .menu;
        self.load(A.MENU_TNY);
        self.menu.enter(self.fb, &pic);
    }

    fn toBlack(self: *Demo) void {
        self.part = .black;
        self.load(if (black.SHOW_DISK_BUG) A.MENU_TNY else A.BLACKEAG_TNY);
        self.black.enter(&pic);
    }

    fn toHades(self: *Demo) void {
        self.part = .hades;
        st.clear(self.fb); // $39E
        self.menu.scroll.load(self.fb); // the band rolls on over nothing
        self.hades.enter();
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) {
            self.wants_quit = true;
            return;
        }
        switch (self.part) {
            .intro => {},
            .main => if (cp == K_SPACE) self.toTitle(),
            .title => if (cp == K_SPACE and self.title_n >= fade.SCREEN.frames()) self.toMenu(),
            .menu => if (!self.menu.ready()) {} else if (cp == K_F1) self.toBlack() else if (cp == K_F2) self.toHades(),
            .black => if (cp == K_SPACE and self.black.running()) self.toMenu(),
            .hades => if (cp == K_SPACE and self.hades.running()) self.toMenu(),
        }
    }
};
