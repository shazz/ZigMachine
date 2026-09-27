// --------------------------------------------------------------------------
// The hall of fame (the model's d_hof.py): $38998 draws it; $38A4E inserts
// the score and runs the NAME ENTRY, resumable. The table: 8 entries of $1E
// bytes at $388AA (6 score digit tiles, then text: spaces, the name at +$10,
// $FF-terminated). A tie with an entry's score enters the table.
//
// Name entry: a 6x5 letter grid ($38A23 + row x 6 + col), the stick moves
// the cursor every 4 VBLs, FIRE picks: $37 = END, $36 = rub out, else the
// letter (10 at most). Fire held: the name and the cursors are reprinted,
// without a wait, until it is released. END: 'POOKY' turns the level select
// on; the name is copied to +$10 with $39 -> $5E, counting with the
// character register (dbra d3): up to the first 0 byte.
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const clock = @import("clock.zig");
const game = @import("game.zig");
const hud = @import("hud.zig");
const screen = @import("screen.zig");
const fade = @import("fade.zig");
const Status = fade.Status;

const HOF: i64 = 0x388AA;
const NAME: i64 = 0x38A42;
const GRID: i64 = 0x38A23;
pub const CURSOR: i64 = 0x389CA;
pub const BLANK: i64 = 0x389CC;

/// $38998: clear, the 'HALL OF FAME' banner, the 8 entries at column 7.
pub fn screenDraw() void {
    screen.clearBoth();
    screen.banner(0x31E70);
    var k: i64 = 0;
    while (k < 8) : (k += 1) screen.printAt(7, 6 + 2 * k, HOF + 0x1E * k);
}

pub const Insert = struct {
    pc: enum { fo, fi, grid, waits, held, done } = .done,
    fade: fade.Fade = .{},
    a1: i64 = 0,
    d2: i64 = 5,
    d3: i64 = 4,
    d7: i64 = 0,
    w: u8 = 0,

    /// $38A4E: nothing when the score is below the 8th entry.
    pub fn start(self: *Insert) void {
        self.* = .{};
        const d0 = m.rw(0x3ADB2);
        const d1 = m.rl(0x3ADB4);
        var a1 = HOF - 2;
        var d2: i64 = 7;
        while (d2 >= 0) : (d2 -= 1) {
            const e0 = m.rw(a1 + 2);
            if (m.s16(d0) > m.s16(e0) or (d0 == e0 and !(m.s32(d1) < m.s32(m.rl(a1 + 4))))) break;
            a1 += 0x1E;
        } else {
            clock.work(400);
            return;
        }
        shift(d2);
        m.ww(a1 + 2, d0);
        m.wl(a1 + 4, d1);
        clock.work(300 + 200 * d2);
        self.a1 = a1;
        self.fade.start(true); // $38ABE: the name screen
        self.pc = .fo;
    }

    pub fn step(self: *Insert) Status {
        while (true) switch (self.pc) {
            .fo => {
                if (self.fade.step() == .yield) return .yield;
                nameScreen();
                self.fade.start(false);
                self.pc = .fi;
            },
            .fi => {
                if (self.fade.step() == .yield) return .yield;
                self.pc = .grid;
            },
            .grid => {
                show(self.d2, self.d3, self.d7);
                self.w = 0;
                self.pc = .waits;
            },
            .waits => {
                while (self.w < 4) : (self.w += 1) {
                    if (hud.waitBlocked()) return .yield;
                    screen.waitD();
                }
                self.pc = self.pick();
            },
            .held => { // $38BB0: until FIRE is released
                if (game.ahead()) return .yield;
                show(self.d2, self.d3, self.d7);
                clock.poll();
                if (m.rb(F.JOY) & 0x80 == 0) self.pc = .grid;
            },
            .done => return .done,
        };
    }

    /// After the 4 waits: move, or pick a letter / rub out / END.
    fn pick(self: *Insert) @TypeOf(self.pc) {
        const d4 = m.rb(F.JOY);
        if (d4 & 0x80 == 0) {
            self.move(d4);
            return .grid;
        }
        const d5 = m.rb(GRID + self.d3 * 6 + self.d2);
        if (d5 == 0x37) {
            store(self.a1);
            return .done;
        }
        screen.printAt((self.d7 + 0xE) & 0xFFFF, 0x15, BLANK);
        const a2 = NAME + self.d7;
        if (d5 == 0x36) { // rub out
            m.wb(a2, 0x39);
            if (self.d7 != 0) self.d7 -= 1;
        } else {
            m.wb(a2, d5);
            if (self.d7 != 9) self.d7 += 1;
        }
        return .held;
    }

    /// $38BC2: left/right then up/down, clamped to the grid; the old cursor erased.
    fn move(self: *Insert, d4: i64) void {
        const d5 = self.d2;
        const d6 = self.d3;
        if (d4 & 4 != 0) {
            if (self.d2 != 0) self.d2 -= 1;
        } else if (d4 & 8 != 0) {
            if (self.d2 != 5) self.d2 += 1;
        }
        if (d4 & 1 != 0) {
            if (self.d3 != 0) self.d3 -= 1;
        } else if (d4 & 2 != 0) {
            if (self.d3 != 4) self.d3 += 1;
        }
        screen.printAt((d5 * 2 + 0xE) & 0xFFFF, (d6 * 2 + 9) & 0xFFFF, BLANK);
    }
};

/// $38A86: d2 entries move down one, from the bottom up (only the literal
/// long / word moves: bytes -2..+5 and +$10..+$19 of each entry).
fn shift(d2: i64) void {
    var a2: i64 = 0x3897A;
    var k: i64 = 0;
    while (k < d2) : (k += 1) {
        m.wl(a2, m.rl(a2 - 0x1E));
        m.wl(a2 + 4, m.rl(a2 - 0x1A));
        m.wl(a2 + 0x12, m.rl(a2 - 0xC));
        m.wl(a2 + 0x16, m.rl(a2 - 8));
        m.ww(a2 + 0x1A, m.rw(a2 - 4));
        a2 -= 0x1E;
    }
}

/// $38ABE..$38B2A between the fades: clear, the 'ENTER YOUR NAME' banner,
/// the prompt, the 5 grid rows, a blank name.
fn nameScreen() void {
    screen.clearBoth();
    screen.banner(0x30A70);
    screen.printAt(9, 5, 0x389CE);
    var k: i64 = 0;
    while (k < 5) : (k += 1) screen.printAt(0xE, 8 + 2 * k, 0x389E6 + 0xC * k);
    m.wl(NAME, 0x39393939);
    m.wl(NAME + 4, 0x39393939);
    m.ww(NAME + 8, 0x3939);
}

/// $38C6A: the grid cursor, the name, the cursor under the name.
fn show(d2: i64, d3: i64, d7: i64) void {
    screen.printAt((d2 * 2 + 0xE) & 0xFFFF, (d3 * 2 + 9) & 0xFFFF, CURSOR);
    screen.printAt(0xE, 0x14, NAME);
    screen.printAt((d7 + 0xE) & 0xFFFF, 0x15, CURSOR);
}

/// $38C28.
fn store(a1_: i64) void {
    var a1 = a1_ + 0x12;
    if (m.rl(NAME) == 0x504F4F4B and m.rl(NAME + 4) == 0x59393939) m.ww(F.LEVEL_SELECT_ON, 0xFF);
    var a2 = NAME;
    var n: i64 = 0;
    while (true) {
        var d3 = m.rb(a2);
        a2 += 1;
        if (d3 == 0x39) d3 = 0x5E;
        m.wb(a1, d3);
        a1 += 1;
        n += 1;
        if (d3 == 0) break; // dbra d3: exits when d3 was 0
    }
    clock.work(120 + 40 * n);
}
