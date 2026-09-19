// --------------------------------------------------------------------------
// THE B.I.G. DEMO — The Exceptions (TEX), 1988.
// Ported from Antoine "NoNameNo" Santo's CODEF remake, screen 23 (MIT). The
// artwork is ES's, the 112 tunes are Mad Max's, and the 41 KB scrolltext is
// -ME-'s: all The Exceptions', credited, never re-attributed.
//
// What is on screen (screen.js go(), one canvas, drawn in this order):
//   three 20-row colour bands, cycling through cycle.png's 8 solid tiles at
//     texbg += 0.4 a frame, seen through main.png's transparent windows
//   main.png over the lot
//   the transparent border scroller: the IN font is a mask filled with the
//     fontbg diagonal sliding 3px a frame, the OUT font's outline over it
//   two half-alpha shadow strips
//   five list rows around the cursor, the selected one a filled bar
//   two rules pulsing on a 30-entry grey ramp at fadecpt += 0.5
//
// Geometry: the remake's canvas is 640x540 and every PNG is an exact 2x, so
// this is 320x270 — an ST fullscreen with the TOP and BOTTOM borders open. We
// earn them the real way, fb.openBorders(.top_bottom) (setOverscanBuffer plus
// the res-flicker HBL at OVERSCAN_MAGIC_X, flickering only the border bands so
// the side borders stay shut, which is what the original screen does). The 270
// rows sit centred in the 280 physical ones, 5 black rows top and bottom.
//
// Music: the remake names a .ym per entry; this plays the real SNDHs — Mad
// Max's own 68000 replay code on the emulated CPU — mapping "<Tune> N.ym" to
// <Tune>.sndh subtune N (see big/list.zig). Four of the 116 entries have no
// SNDH in the archive (Delta preview, Thalamus, The Last V8 #2 and #3) and
// behave like the list's own four separator rows: selectable, silent.
//
// NOT ported: the main picture advertises "Hit 1...3 for Psych-O-Screens" and
// "Hit B for the B.I.G.-Scroller", but the remake's KeyCheck() (screen.js:33)
// implements neither — there is no code for them to port.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Console = zg.Console;

const A = @import("big/assets.zig");
const Screen = @import("big/screen.zig").Screen;
const list = @import("big/list.zig");

const K_ESC: u32 = 0xE012; // host KEY_CODES.Escape
const K_RETURN: u32 = 13;
const DIR_UP: u8 = 0;
const DIR_DOWN: u8 = 1;
const DIR_BACK: u8 = 6;

/// wait() ends with player.LoadAndRun('Big - Ace 2.ym') — list entry 2, which
/// is also where the cursor and the highlight start.
const FIRST = list.ENTRIES[2];

pub const Demo = struct {
    screen: Screen,
    running: bool, // false while wait() still owns the frame
    leave: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("B.I.G. Demo init", .{});
        self.running = false;
        self.leave = false;
        self.screen.init();

        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.openBorders(.top_bottom); // 400x280 + the flicker HBL, bands only
        fb.setPalette(A.palette);
        fb.setPaletteEntry(A.TRANSPARENT, zg.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        // The whole 400x280 buffer: the 5 rows above and below the 270-row screen
        // AND the 40-px side margins. PANEL, not BLACK — the real screen's border
        // is the same grey as the panel, so the join is invisible.
        fb.clearFrameBuffer(A.PANEL);
        // The hardware border beyond the plane, for the same reason.
        zigos.setBackgroundColor(A.palette[A.PANEL]);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        // wait() shows the instruction screen, then calls go() ON THAT FRAME:
        // the 201st is the jukebox's first, and the tune starts with it.
        if (self.running) return;
        if (!self.screen.waited()) return;
        self.running = true;
        zg.requestSongTune(FIRST.song, FIRST.tune);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb: *LogicalFB = &zigos.lfbs[0];
        if (self.running) self.screen.go(fb) else self.screen.drawWait(fb);
    }

    /// The jukebox binds Up/Down/Return, so it owns the keyboard — and owning
    /// it means owning Escape, which is how you leave for the menu.
    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            K_ESC => self.leave = true,
            K_RETURN => self.screen.select(),
            else => {},
        }
    }

    /// The host still routes the arrows through input() even for an owning
    /// screen (sealed-loader.js), so Up/Down arrive here, not in key().
    ///
    /// NOT gated on `running`, deliberately: the original binds KeyCheck at
    /// document level before init(), so Up/Down/Return are live DURING the
    /// 200-frame instruction screen. Moving the cursor there is invisible (the
    /// list is not drawn yet) but `curent` carries into the first go() frame,
    /// and a Return can start a tune before go()'s automatic Ace 2 — which is
    /// exactly what the original does. (Matt, 2026-09-19.)
    pub fn input(self: *Demo, dir: u8) void {
        if (dir == DIR_BACK) self.leave = true;
        if (dir == DIR_UP) self.screen.scrollUp();
        if (dir == DIR_DOWN) self.screen.scrollDown();
    }

    pub fn pollCart(self: *Demo) i32 {
        if (!self.leave) return 0;
        self.leave = false;
        return -1; // back to the menu disk
    }
};
