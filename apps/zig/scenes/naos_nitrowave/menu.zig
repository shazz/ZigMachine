// --------------------------------------------------------------------------
// THE BATTLETEC MENU (AUTO/MENU.PRG): Freddi's sprite scroller over ATM's
// fullscreen picture, Aragorn's overscan. MENU.PRG's TEXT+DATA sit at 0 in the
// part's memory (the rip is relocated to 0); every address below is the
// program's own (prototypes/naos_nitrowave_re/NOTES.md, "Menu").
//
// The VBL is a generated fullscreen routine ($78800): the template at $E10 and
// the fragment stream $1688..$C3F8 packed into each overscan line's free
// cycles. Its logical program (menu_vbl.zig) erases the band drawn two frames
// ago and draws 22 columns of a 48x31 font as masked sprites, one vertical
// path word each. The main loop, after every VBL, swaps the two screens
// ($6C4), scrolls the column tables ($630) and appends a letter every sixth
// frame ($794/$7DC), and restarts the path every $2CA frames ($76C).
// --------------------------------------------------------------------------
const st = @import("st.zig");
const vbl = @import("menu_vbl.zig");

pub const PIC: u32 = 0xC418; // the picture, laid out as a screen (+160: line 0)
pub const PALETTE: u32 = 0xC3F8;
pub const SCR_A: u32 = 0x69100;
pub const SCR_B: u32 = 0x59A00;
pub const PIC_LEN: usize = 160 + 59800; // 260 lines of 230 bytes after the top line
const TEXT0: u32 = 0x1AE50;
const PATH0: u32 = 0x1B956;
const PATH_PERIOD: u16 = 0x2CA;
const TABLE_ENTRIES = 27; // $630 moves 26 longs down one; entry 26 stays blank
// A letter's three columns, in the font sheets: gfx A, gfx B, mask A, mask B
// (the two screens' preshifts); rows of six letters every $14A0 bytes.
const FONT = [4]u32{ 0x1C6C4, 0x2440E, 0x2C148, 0x33E92 };
const ROW_STEP: u32 = 0x14A0;
// where $7DC writes them: entries 23..25 of the gfx A, gfx B, mask A, mask B tables
const SLOT = [4]u32{ 0x1C526, 0x1C59E, 0x1C616, 0x1C68E };
const GFX_A: u32 = 0x1C4CA;
const GFX_B: u32 = 0x1C542;
const MASK_A: u32 = 0x1C5BA;
const MASK_B: u32 = 0x1C632;
// variables (BSS)
pub const V_DRAW: u32 = 0x3D8D6; // the screen the next VBL draws on
pub const V_BG: u32 = 0x3D8E2; // the picture the erase copies from
pub const V_GFX: u32 = 0x3D8DA;
pub const V_MASK: u32 = 0x3D8DE;
pub const V_PATH: u32 = 0x3D8E6;
const V_TEXT: u32 = 0x3D8EA;
const V_PCNT: u32 = 0x3D904;
const V_PAUSE_N: u32 = 0x3D902;
const V_SIX: u32 = 0x3D906;
const V_PAUSE: u32 = 0x3D907;
const V_TOGGLE: u32 = 0x3D908;

pub const Menu = struct {
    shown: u32, // the screen $6C4 set: the shifter shows it from the next VBL
    displayed: u32, // the screen shown while the last VBL ran

    /// From $472 to the main loop's first `stop` ($528).
    pub fn enter(self: *Menu, r: *const st.Ram) void {
        prepareMasks(r);
        for ([2]u32{ SCR_A, SCR_B }) |s| r.cp(s + 160, PIC + 160, PIC_LEN - 160); // $AA..$E6
        r.sl(V_TEXT, TEXT0);
        r.sw(V_PCNT, 0);
        r.sl(V_PATH, PATH0);
        r.sb(V_PAUSE, 0);
        r.sb(V_TOGGLE, 0); // $504
        self.shown = SCR_A;
        self.displayed = SCR_A;
        self.swap(r);
        self.letterClock(r);
        pathClock(r);
        self.scroll(r);
    }

    /// One VBL, then the main loop's work after it ($528..$578).
    pub fn frame(self: *Menu, r: *const st.Ram) void {
        self.displayed = self.shown;
        vbl.run(r);
        self.swap(r);
        self.scroll(r);
        pathClock(r);
    }

    /// $6C4: show one screen, draw the next VBL on the other. A pause draws
    /// both from the B tables ($74A -> $702).
    fn swap(self: *Menu, r: *const st.Ram) void {
        r.sl(V_BG, PIC);
        if (r.b(V_TOGGLE) == 1) {
            self.shown = SCR_A;
            r.sb(V_TOGGLE, 0);
            r.sl(V_DRAW, SCR_B);
            if (r.b(V_PAUSE) != 1) return setTables(r, GFX_A, MASK_A);
        } else {
            r.sb(V_TOGGLE, 1);
            self.shown = SCR_B;
            r.sl(V_DRAW, SCR_A);
        }
        setTables(r, GFX_B, MASK_B);
    }

    /// $630: the tables the next VBL draws from move one column (16 px) left.
    fn scroll(self: *Menu, r: *const st.Ram) void {
        if (r.b(V_PAUSE) == 1) return pauseClock(r);
        for ([2]u32{ r.l(V_GFX), r.l(V_MASK) }) |t| {
            for (0..TABLE_ENTRIES - 1) |i| r.sl(t + 4 * @as(u32, @intCast(i)), r.l(t + 4 * @as(u32, @intCast(i)) + 4));
        }
        self.letterClock(r);
    }

    /// $794: every sixth call, the next character ($7DC).
    fn letterClock(_: *Menu, r: *const st.Ram) void {
        r.sb(V_SIX, r.b(V_SIX) +% 1);
        if (r.b(V_SIX) != 6) return;
        r.sb(V_SIX, 0);
        nextChar(r);
    }
};

fn setTables(r: *const st.Ram, gfx: u32, mask: u32) void {
    r.sl(V_MASK, mask);
    r.sl(V_GFX, gfx);
}

/// $496 / $4B6: in each 8-byte group of the mask sheets, word 0 is copied over
/// word 1, so `and.l` masks all four planes with it ($2C148's first group is
/// left out, as the original does).
fn prepareMasks(r: *const st.Ram) void {
    for ([2]u32{ 0x2C150, 0x33E92 }) |src| {
        for (0..0xF01) |i| {
            const a = src + 8 * @as(u32, @intCast(i));
            r.sl(a + 2, r.l(a));
        }
    }
}

/// $7B4: a lower-case 's' holds the scroller for $A0 frames.
fn pauseClock(r: *const st.Ram) void {
    const n = r.w(V_PAUSE_N) + 1;
    r.sw(V_PAUSE_N, n);
    if (n != 0xA0) return;
    r.sb(V_PAUSE, 0);
    r.sw(V_PAUSE_N, 0);
}

/// $7DC: $FF restarts the text, 's' pauses, ' ' appends nothing (the blank
/// entry 26 scrolls in), anything else appends its three columns.
fn nextChar(r: *const st.Ram) void {
    if (r.b(V_PAUSE) == 1) return pauseClock(r);
    const p = r.l(V_TEXT);
    const c = r.b(p);
    r.sl(V_TEXT, p + 1);
    switch (c) {
        0xFF => r.sl(V_TEXT, TEXT0),
        0x73 => {
            r.sb(V_PAUSE, 1);
            r.sw(V_PAUSE_N, 0);
        },
        0x20 => {},
        else => appendLetter(r, c),
    }
}

/// The subi / mulu #$18 / adda.w of $83C..$A74: rows of six letters from 'A',
/// 'G', 'M', 'S', 'Y' (the last row also holds [ \ ] ^).
fn appendLetter(r: *const st.Ram, c: u8) void {
    const row: u32, const first: u8 = if (c > 0x58) .{ 4, 0x59 } else if (c > 0x52) .{ 3, 0x53 } else if (c > 0x4C) .{ 2, 0x4D } else if (c > 0x46) .{ 1, 0x47 } else .{ 0, 0x41 };
    const k: u32 = c -% first;
    for (FONT, SLOT) |base, slot| {
        const src = base + row * ROW_STEP + k * 0x18;
        for (0..3) |j| r.sl(slot + 4 * @as(u32, @intCast(j)), src + 8 * @as(u32, @intCast(j)));
    }
}

/// $76C: the path starts over every $2CA frames.
fn pathClock(r: *const st.Ram) void {
    const n = r.w(V_PCNT) + 1;
    r.sw(V_PCNT, n);
    if (n != PATH_PERIOD) return;
    r.sw(V_PCNT, 0);
    r.sl(V_PATH, PATH0);
}
