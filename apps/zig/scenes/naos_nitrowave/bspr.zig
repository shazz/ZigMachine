// --------------------------------------------------------------------------
// F2: BIGSPRITE + OVERSCAN, by Aragorn (B_SPRITE.BIN, loaded at $800). A
// 144x80 sprite, every line placed on its own -- position, preshift and mask
// from a 12-byte entry -- over a full-overscan tiled background, double
// buffered. As in the menu, the VBL ($79800) is generated from a template
// ($1558) and a fragment stream ($5024..$10796); its logical program:
//   erase  80 lines: 72 bytes back from the picture ($4D700) at the offsets
//          this screen's table ($1263A) kept two frames ago
//   draw   80 lines, a6 -> entry i: offset + *($12A5A) (the whole sprite's
//          move), kept in the table; 9 groups: both longs &= the mask long,
//          |= the preshift's longs
// The main loop ($1140/$11BA, two halves) then picks the next a6 ($1218: seven
// states walking the entry tables) and the next global offset ($140C), and
// swaps the screens. 'F' freezes both ($17B86). Checked against Hatari and the
// original code on Musashi: prototypes/naos_nitrowave_re/bspr_model.py, NOTES.md.
// --------------------------------------------------------------------------
const st = @import("st.zig");
const I = @import("bspr_init.zig");
const LINE = I.LINE;

pub const PALETTE: u32 = 0x10796;
pub const SCR_A: u32 = 0x5C200;
pub const SCR_B: u32 = 0x6AD00;
const BG: u32 = 0x4D700;
const TAB_A: u32 = 0x1263E; // the erase tables, 80 longs
const TAB_B: u32 = 0x1277E;
const V_SCREEN: u32 = 0x12636;
const V_TABLE: u32 = 0x1263A;
const V_PATH: u32 = 0x12A56;
const V_GLOB: u32 = 0x12A5A;
const V_GN: u32 = 0x12A5E;
const V_GSTATE: u32 = 0x12A60;
const V_PN: u32 = 0x12A62;
const V_PSTATE: u32 = 0x12A64;
const GLOB_FIRST: u32 = 0x128C2;
const GLOB_END: u32 = 0x12A52;
const ENTRY: u32 = 12;

/// $1218's states 2..6: the end of each entry table, where it restarts, and the
/// next state's count (state 6 runs on into state 7's table instead).
const Walk = struct { end: u32, restart: u32, next: ?u16 };
const walks = [_]Walk{
    .{ .end = 0x135B2, .restart = 0x12E32, .next = 8 },
    .{ .end = 0x13D32, .restart = 0x13972, .next = 4 },
    .{ .end = 0x14F86, .restart = 0x1416A, .next = 1 },
    .{ .end = 0x1697E, .restart = 0x1545A, .next = 4 },
    .{ .end = 0x173CE, .restart = 0x1697E, .next = null },
};

pub const Bspr = struct {
    a6: u32,
    freeze: bool,
    second_half: bool,
    shown: u32, // the screen the shifter shows from the next VBL
    displayed: u32, // the screen shown while the last VBL ran

    /// $800..$1140: the precalculation, then the main loop's entry state.
    pub fn enter(self: *Bspr, r: *const st.Ram) void {
        I.background(r);
        I.sprites(r);
        self.a6 = 0x12E32; // $1134
        self.freeze = false;
        self.second_half = false;
        self.shown = SCR_A; // $84E
        self.displayed = SCR_A;
    }

    pub fn frame(self: *Bspr, r: *const st.Ram) void {
        self.displayed = self.shown;
        erase(r);
        self.draw(r);
        self.path(r);
        self.glob(r);
        const draw_next: u32, const table: u32 = if (self.second_half) .{ SCR_B, TAB_A } else .{ SCR_A, TAB_B };
        r.sl(V_SCREEN, draw_next);
        r.sl(V_TABLE, table);
        self.shown = if (draw_next == SCR_A) SCR_B else SCR_A;
        self.second_half = !self.second_half;
    }

    pub fn toggleFreeze(self: *Bspr) void {
        self.freeze = !self.freeze; // $11AA: not.w $17B86
    }

    fn draw(self: *const Bspr, r: *const st.Ram) void {
        const scr = r.l(V_SCREEN);
        const tab = r.l(V_TABLE);
        const moved = r.l(r.l(V_GLOB)); // the whole sprite's offset
        for (0..I.LINES) |i| {
            const ii: u32 = @intCast(i);
            const e = self.a6 + ENTRY * ii;
            const pos = r.l(e) +% moved;
            r.sl(tab + 4 * ii, pos);
            line(r, (pos +% scr +% LINE * ii) & 0xFFFFFF, r.l(e + 4) + 72 * ii, r.l(e + 8) + 36 * ii);
        }
    }

    /// $1218: a6 for the next VBL.
    fn path(self: *Bspr, r: *const st.Ram) void {
        if (self.freeze) return self.setA6(r.l(V_PATH));
        if (r.w(V_PSTATE) == 1) {
            const n = r.w(V_PN) -% 1;
            r.sw(V_PN, n);
            if (n != 0) return self.setA6(r.l(V_PATH));
            r.sw(V_PSTATE, 2);
            r.sw(V_PN, 8);
        }
        self.walk(r);
    }

    fn setA6(self: *Bspr, a: u32) void {
        self.a6 = a;
    }

    /// $125E..$13F0: one entry on in the current table.
    fn walk(self: *Bspr, r: *const st.Ram) void {
        while (true) {
            const s = r.w(V_PSTATE);
            var a0 = r.l(V_PATH) + ENTRY;
            if (s >= 2 and s <= 6) {
                const w = walks[s - 2];
                if (a0 == w.end) {
                    const n = r.w(V_PN) -% 1;
                    r.sw(V_PN, n);
                    if (n == 0) {
                        r.sw(V_PSTATE, s + 1);
                        if (w.next) |next| r.sw(V_PN, next);
                        continue;
                    }
                    a0 = w.restart;
                }
                r.sl(V_PATH, a0);
                return self.setA6(a0);
            }
            r.sw(V_PSTATE, 7); // $13CC
            if (a0 != 0x1779A) {
                r.sl(V_PATH, a0);
                return self.setA6(a0);
            }
            r.sw(V_PSTATE, 1); // $11FE: start over, then $1218 again
            r.sw(V_PN, 0x190);
            r.sl(V_PATH, 0x12A66);
            return self.path(r);
        }
    }

    /// $140C: the offset the whole sprite moves by.
    fn glob(self: *Bspr, r: *const st.Ram) void {
        if (self.freeze) return;
        if (r.w(V_GSTATE) == 1) {
            const n = r.w(V_GN) -% 1;
            r.sw(V_GN, n);
            if (n != 0) return;
            r.sw(V_GSTATE, 2);
            r.sw(V_GN, 0xA);
        }
        const a0 = r.l(V_GLOB) + 4;
        r.sl(V_GLOB, a0);
        if (a0 != GLOB_END) return;
        const n = r.w(V_GN) -% 1;
        r.sw(V_GN, n);
        r.sl(V_GLOB, GLOB_FIRST);
        if (n != 0) return;
        r.sw(V_GN, 0x320); // $13F2, then $140C again
        r.sw(V_GSTATE, 1);
        self.glob(r);
    }
};

fn erase(r: *const st.Ram) void {
    const scr = r.l(V_SCREEN);
    const tab = r.l(V_TABLE);
    for (0..I.LINES) |i| {
        const ii: u32 = @intCast(i);
        const off = r.l(tab + 4 * ii) +% LINE * ii;
        r.cp((scr +% off) & 0xFFFFFF, (BG +% off) & 0xFFFFFF, 72);
    }
}

fn line(r: *const st.Ram, dst: u32, g: u32, k: u32) void {
    for (0..I.GROUPS) |j| {
        const jj: u32 = @intCast(j);
        const m = r.l(k + 4 * jj);
        for ([2]u32{ 0, 4 }) |h| {
            const a = dst + 8 * jj + h;
            r.sl(a, (r.l(a) & m) | r.l(g + 8 * jj + h));
        }
    }
}
