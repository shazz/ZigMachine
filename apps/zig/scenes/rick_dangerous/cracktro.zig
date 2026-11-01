// --------------------------------------------------------------------------
// The Empire's CABAL cracktro (EMP_CABL.PRG, The Fallen Angels / Illegal),
// in front of the game as its trainer menu. A port of the program:
//
//   music     its Hippel COSO replay (TEXT+$16AA, data "COSO" at $207A),
//             song 2, IS Leavin Teramis subtune 10 (leavin_teramis.sndh):
//             the YM registers match frame for frame over 6000 frames
//   typing    $2EDE prints ESC E, ESC e; the main loop $98 then calls the
//             typewriter $2EEC until the ACIA's last byte is Space's make
//             code ($FC02 = $39); every output waits two VBLs ($2F8A: two
//             Vsync), the end of text ($FF) none
//   trainer   Space: the music stops (the VBL slot cleared, the PSG
//             silenced), ESC E "Trainer y/n:" and Crawcin until y or n
//             (or.b #$20 first: Y / N too); then colour 0 = black and the game
//
// PATCHED to fit the game (Matt: "you can patch it to fit the game"): the
// title text reads RICK DANGEROUS (cracktro_text.zig), and the one question
// becomes Rick's three, one a line, each answer echoed (the original's
// Crawcin does not echo; three silent answers would leave the player unsure):
// infinite lives, bullets, dynamite. The original had no level select, so
// there is none.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const vt52 = @import("vt52.zig");
const text = @import("cracktro_text.zig");
const trainer = @import("trainer.zig");
const stColor = @import("present.zig").stColor;

pub const MUSIC = "leavin_teramis.sndh";
// Subtune 11: the original running in Hatari (STE, TOS 1.62) matches it register for register at two
// samples 37 frames apart, frames 1071/1108 of the dump; the ripped-player rebuild had matched 10.
pub const MUSIC_TUNE: u8 = 11;
/// ESC E ESC e, $2FCA.
const START = "\x1bE\x1be";
const PROMPTS = [_][]const u8{
    "\x1bEInfinite lives y/n:",
    "Infinite bullets y/n:",
    "Infinite dynamite y/n:",
};

pub const Phase = enum { typing, trainer, done };

pub const Cracktro = struct {
    vt: vt52.Screen,
    text: []const u8 = text.RICK,
    phase: Phase = .typing,
    /// a5: the next byte of the text.
    pos: u16 = 0,
    /// VBLs left in the current two-VBL wait.
    wait: u8 = 0,
    /// $01 n / $02 n: cursor moves still to make, each followed by a wait.
    moves: u8 = 0,
    move: u8 = 'D',
    /// $F7 read: its wait runs, then the page clears.
    page: bool = false,
    /// The ACIA's last byte is Space's make code.
    space: bool = false,
    question: u8 = 0,

    pub fn start(self: *Cracktro) void {
        self.vt.fb.palette[vt52.PAPER] = stColor(0x777);
        self.vt.fb.palette[vt52.INK] = stColor(0x000);
        self.vt.fb.clearFrameBuffer(vt52.PAPER);
        zg.requestSongTune(MUSIC, MUSIC_TUNE);
        self.vt.outs(START);
        self.proceed();
    }

    /// One 50 Hz VBL.
    pub fn vbl(self: *Cracktro) void {
        self.vt.vbl();
        if (self.phase != .typing) return;
        if (self.wait > 0) {
            self.wait -= 1;
            if (self.wait > 0) return;
        }
        self.proceed();
    }

    /// A key's make: the ACIA byte the main loop reads, or Crawcin's answer.
    pub fn key(self: *Cracktro, cp: u32) void {
        self.space = cp == ' ';
        if (self.phase != .trainer) return;
        const c = cp | 0x20; // or.b #$20,d0
        if (c != 'y' and c != 'n') return;
        const on = c == 'y';
        switch (self.question) {
            0 => trainer.infinite_lives = on,
            1 => trainer.infinite_bullets = on,
            else => trainer.infinite_dynamite = on,
        }
        self.vt.out(@intCast(cp & 0xFF));
        self.vt.outs("\r\n");
        self.question += 1;
        if (self.question < PROMPTS.len) self.vt.outs(PROMPTS[self.question]) else self.phase = .done;
    }

    /// A key's break code replaces the make in the ACIA's data register.
    pub fn keyUp(self: *Cracktro, cp: u32) void {
        _ = cp;
        self.space = false;
    }

    /// The main loop from the end of a wait: until the next wait.
    fn proceed(self: *Cracktro) void {
        var guard: u16 = 0;
        while (guard < 1024) : (guard += 1) {
            if (self.moves > 0) return self.moveOnce();
            if (self.page) {
                self.page = false;
                self.vt.outs("\x1bE");
                if (self.tail(self.next())) return;
                continue;
            }
            if (self.space) return self.toTrainer();
            if (self.step()) return;
        }
    }

    /// $2EEC. True when it ends in a wait.
    fn step(self: *Cracktro) bool {
        var d = self.next();
        if (d == 0) {
            self.vt.outs("\n\r");
            self.waitTwo();
            return true;
        }
        if (d == 0xFE) {
            self.vt.outs("\x1bp");
            d = self.next();
        }
        if (d == 0xFC) {
            self.vt.outs("\x1bq");
            d = self.next();
        }
        if (d == 0xF7) {
            self.waitTwo();
            self.page = true;
            return true;
        }
        return self.tail(d);
    }

    /// $2F34: the end of text, the cursor moves, a character.
    fn tail(self: *Cracktro, d: u8) bool {
        switch (d) {
            0xFF => {
                self.vt.outs("\x1bE");
                self.pos = 0;
                return false;
            },
            1, 2 => {
                self.move = if (d == 1) 'D' else 'C';
                self.moves = self.next();
                self.moveOnce();
            },
            else => {
                self.vt.out(d);
                self.waitTwo();
            },
        }
        return true;
    }

    fn moveOnce(self: *Cracktro) void {
        self.moves -= 1;
        self.vt.out(0x1B);
        self.vt.out(self.move);
        self.waitTwo();
    }

    /// $2F8A: two Vsyncs; three VBLs when the step cleared the screen.
    fn waitTwo(self: *Cracktro) void {
        self.wait = if (self.vt.cleared) 3 else 2;
        self.vt.cleared = false;
    }

    fn next(self: *Cracktro) u8 {
        const d = self.text[self.pos];
        self.pos = @intCast((self.pos + 1) % self.text.len);
        return d;
    }

    /// $A6..$11E: the music off, the trainer question.
    fn toTrainer(self: *Cracktro) void {
        zg.stopSong();
        self.phase = .trainer;
        self.question = 0;
        trainer.set(0);
        self.vt.outs(PROMPTS[0]);
    }
};
