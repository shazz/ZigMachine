// --------------------------------------------------------------------------
// The demo's FIRST screen, before the V title: three pages of 8x8 text on a
// black band, the border white at the end.
//
// It is a little script, not hand-written timing.  The interpreter at $b5b8
// walks 16-byte records from $3fdc, one step whenever its frame counter
// ($ebaa) runs out:
//   d1 = the delay in frames, applied AFTER the record runs
//   low byte of d2 = the opcode, d3 = its argument, d4 = a row
// and the opcodes are:
//   1  ink := d3            ($b5fe)
//   2  border := white      ($b606)
//   3  wait only            ($b610)
//   4  clear from row d4    ($b612, 8004 bytes = 50 lines of 160)
//   5  draw text d3 at d4   ($b632 -> $b674; $a advances $780 = 12 rows)
//   $ff end                 ($b650, sets the title state machine to 2)
// tools/private_tools/vex_assets.py re-emits those 19 records as fixed 8-byte
// ones so this file carries no link pointers, and the delays/rows/colours are
// the original's own numbers.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;

const A = @import("assets.zig");
const pal = @import("palette.zig");

pub const BAND: u8 = 0; // colour 0 -- the raster paints it, see below
pub const INK: u8 = 1; // $b6a0 writes plane 0 only, so the text is index 1

/// The black band is NOT the framebuffer clear: it is a Timer-B split on
/// colour 0, exactly like the intro's border. $b412 arms $fa21 = $40 = 64
/// scanlines and writes colour 0 from $ef6e; $b45c writes $777 back. Since the
/// ST's border is colour 0 too, the band runs the full width of the raster.
/// op 4 only erases the previous page's text.
/// BAND_TOP is MEASURED off the demozoo reference (rows 70..134), not derived
/// from the code -- the cycle timing inside $b45c's waits would not tell me.
pub const BAND_TOP: u16 = 70;
pub const BAND_ROWS: u16 = 64; // $fa21 = $40

const REC: usize = 8; // delay u16, op u8, text u8, row u16, colour u16
const CLEAR_ROWS: usize = 50; // 8004 bytes at 160 B/line
const LINE_STEP: usize = 12; // $780 / $a0

pub const Intro = struct {
    pc: usize, // which record
    delay: u16, // $ebaa
    /// $b360 runs the $ab86 crossfade EVERY VBL, so op 1 sets a target and the
    /// live colour walks toward it one level per channel per frame — the text
    /// fades in and out rather than snapping. That is what the 50-frame delays
    /// after each op 1 are for: the ramp, then the hold.
    ink: u16, // live
    ink_target: u16, // $16cb8, what op 1 writes
    border_white: bool, // op 2
    finished: bool,

    pub fn init(self: *Intro, fb: *LogicalFB) void {
        self.pc = 0;
        self.delay = 0;
        self.ink = 0;
        self.ink_target = 0;
        self.border_white = false;
        self.finished = false;
        fb.clearFrameBuffer(BAND);
    }

    /// One frame of the interpreter: run records until one asks to wait.
    pub fn step(self: *Intro, fb: *LogicalFB) void {
        if (self.finished) return;
        self.ink = pal.stepColour(self.ink, self.ink_target); // every frame, like the VBL
        if (self.delay > 0) {
            self.delay -= 1;
            return;
        }
        while (self.delay == 0 and !self.finished) self.run(fb);
    }

    fn run(self: *Intro, fb: *LogicalFB) void {
        const o = self.pc * REC;
        if (o + REC > A.intro_script.len) return self.end();
        const delay = A.be(A.intro_script, self.pc * 4);
        const op = A.intro_script[o + 2];
        const text = A.intro_script[o + 3];
        const row = A.be(A.intro_script, self.pc * 4 + 2);
        const colour = A.be(A.intro_script, self.pc * 4 + 3);
        self.pc += 1;
        switch (op) {
            1 => self.ink_target = colour,
            2 => self.border_white = true,
            4 => clearRows(fb, row),
            5 => draw(fb, text, row),
            0xff => return self.end(),
            else => {}, // 3 is a pure wait, and the original ignores the rest
        }
        self.delay = delay;
    }

    fn end(self: *Intro) void {
        self.finished = true;
        self.delay = 0;
    }
};

/// $b674: ASCII - $20 into an 8x8 sheet, a byte a row, $a starts a new line.
fn draw(fb: *LogicalFB, text: u8, row: u16) void {
    const s = A.intro_texts[text];
    var x: usize = 0;
    var y: usize = row;
    for (s) |ch| {
        if (ch == '\n') {
            y += LINE_STEP;
            x = 0;
            continue;
        }
        if (ch >= 0x20 and @as(usize, ch - 0x20) * 8 + 8 <= A.introfont.len) blit(fb, ch, x, y);
        x += 8;
    }
}

fn blit(fb: *LogicalFB, ch: u8, x: usize, y: usize) void {
    const g = (@as(usize, ch) - 0x20) * 8;
    for (0..8) |r| {
        if (y + r >= zg.HEIGHT) return;
        const bits = A.introfont[g + r];
        for (0..8) |c| {
            if (x + c >= zg.WIDTH) break;
            if (bits >> @intCast(7 - c) & 1 != 0) fb.fb[(y + r) * fb.stride + x + c] = INK;
        }
    }
}

/// op 4: 8004 bytes = 50 lines of 160. It only wipes the last page's text.
fn clearRows(fb: *LogicalFB, row: u16) void {
    var y: usize = row;
    while (y < @min(row + CLEAR_ROWS, zg.HEIGHT)) : (y += 1) {
        @memset(fb.fb[y * fb.stride ..][0..zg.WIDTH], BAND);
    }
}
