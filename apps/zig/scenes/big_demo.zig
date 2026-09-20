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
// this is 320x270, sitting centred in the 400x280 overscan plane. ALL FOUR
// borders are open — fb.openBorders(.all), the res-flicker HBL at
// OVERSCAN_MAGIC_X on every line — because the real screen is full overscan and
// puts content in the side borders. An earlier pass used .top_bottom on the
// belief that the sides stayed shut; the capture refutes it (see big/border.zig)
// and the remake simply has no artwork out there to have shown otherwise.
//
// Music: the remake names a .ym per entry; this plays the real SNDHs — Mad
// Max's own 68000 replay code on the emulated CPU — mapping "<Tune> N.ym" to
// <Tune>.sndh subtune N (see big/list.zig). Four of the 116 entries have no
// SNDH in the archive (Delta preview, Thalamus, The Last V8 #2 and #3) and
// behave like the list's own four separator rows: selectable, silent.
//
// The SIDE BORDERS are the demo's, not the remake's: main.png stops at the
// screen edge, but the real screen runs the song-list frame's shadow and the
// bottom scroller's pipes and shadows out past the 320 columns (Matt,
// 2026-09-19). big/border.zig carries that, measured off the real capture.
//
// NOT ported: the main picture advertises "Hit 1...3 for Psych-O-Screens" and
// "Hit B for the B.I.G.-Scroller". Those keys are real on the machine (Matt,
// 2026-09-19) and open four further screens, but the remake's KeyCheck()
// (screen.js:33) implements neither and those screens are not here yet.
//
// THE LIST IS THE DEMO'S OWN, NOT THE REMAKE'S.
// big/list.zig is TEX's 118-row table ripped out of the running demo's memory
// (Hatari, table at $A4BC, stride 38), not a transcription of screen.js. The
// remake's 116 rows turned out to be a RENAMED, RE-SORTED and incomplete copy:
// ACTION-BIKER became "CLUMSY COLIN ACTION BIKER" and moved A->C, STRONGMAN
// became "GEOFF CAPES STRONGMAN" and moved S->G, two entries were dropped, one
// was invented, and the durations were lost entirely. We follow the REAL demo
// — the same call already made for the colour bands and the border.
//
// The cost, stated plainly: the list block can no longer be compared against a
// Chrome replay of screen.js at all, because it is no longer the remake's list.
// Everything outside it still is. The list is 118 rows and `curent` clamps at
// [2, 115] = `mylist.length - 3`, which lands exactly on the Digital
// Department row where the real table puts it — the demo's own data and its own
// clamp agreeing is the strongest evidence we have that the row belongs there.
// The four baked frame hashes DID move, because the rows on screen in an
// input-free run (TOP OF LIST, blank, ACE 2, ACTION-BIKER #1, #2) are now the
// real ones and carry their durations.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Console = zg.Console;

const A = @import("big/assets.zig");
const Screen = @import("big/screen.zig").Screen;
const list = @import("big/list.zig");
const digital = @import("big/digital.zig");
const border = @import("big/border.zig");

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
    /// The Digital Solution is up, over the jukebox (list.DIGITAL was chosen).
    /// Its scroller runs off THIS struct's `screen`, so the text carries on
    /// across the swap rather than restarting — the state has one home.
    digital_up: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("B.I.G. Demo init", .{});
        self.running = false;
        self.leave = false;
        self.digital_up = false;
        self.screen.init();

        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.openBorders(.all); // 400x280 + the flicker HBL on EVERY line
        fb.setPalette(A.palette);
        fb.setPaletteEntry(A.TRANSPARENT, zg.Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        // The whole 400x280 buffer: the 5 rows above and below the 270-row screen
        // AND the 40-px side margins. PANEL, not BLACK — the real screen's border
        // is the same grey as the panel, so the join is invisible.
        fb.clearFrameBuffer(A.PANEL);
        // The hardware border beyond the plane, for the same reason.
        zigos.setBackgroundColor(A.palette[A.PANEL]);
        // Colour 0 per scanline, once: it is static apart from the two rule
        // rows, and those carry the PULSE pen, which the palette write moves.
        border.paint(fb);
        border.paintRules(fb, A.PANEL); // until go() owns them
        fb.setPaletteEntry(A.PULSE, A.PULSE_RAMP[0]);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        // wait() shows the instruction screen, then calls go() ON THAT FRAME:
        // the 201st is the jukebox's first, and the tune starts with it.
        if (self.running) return;
        if (!self.screen.waited()) return;
        self.running = true;
        border.paintRules(&zigos.lfbs[0], A.PULSE);
        zg.requestSongTune(FIRST.song, FIRST.tune);
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        const fb: *LogicalFB = &zigos.lfbs[0];
        if (self.digital_up) return digital.draw(&self.screen, fb);
        if (self.running) self.screen.go(fb) else self.screen.drawWait(fb);
    }

    /// The jukebox binds Up/Down/Return, so it owns the keyboard — and owning
    /// it means owning Escape, which is how you leave for the menu.
    pub fn ownsKeyboard(self: *Demo) u32 {
        _ = self;
        return 1;
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) {
            self.leave = true;
            return;
        }
        // The Digital Solution owns every other key while it is up: 1-6 play,
        // Space comes back here ("-PRESS SPACE TO EXIT TO THE B.I.G. DEMO-").
        if (self.digital_up) {
            if (digital.key(cp)) self.digital_up = false;
            return;
        }
        // Return: the highlight moves whatever the row is, and the Digital
        // Department row opens its screen instead of playing anything.
        if (cp == K_RETURN) {
            self.screen.select();
            if (self.screen.curentlplay == list.DIGITAL) {
                self.digital_up = true;
                digital.enter(); // the screen opens WITH its music
            }
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
        if (self.digital_up) return; // the Digital Solution has no cursor to move
        if (dir == DIR_UP) self.screen.scrollUp();
        if (dir == DIR_DOWN) self.screen.scrollDown();
    }

    pub fn pollCart(self: *Demo) i32 {
        if (!self.leave) return 0;
        self.leave = false;
        return -1; // back to the menu disk
    }
};
