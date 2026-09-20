// --------------------------------------------------------------------------
// The 40-column credits panel ($33a2 renders it, $340c shows it, $3434/$3468/
// $35ec cycle it).
//
// $33a2 lays each of the four pages out once into its own buffer with an 8x8
// font at $2819e, 40 columns by up to 15 rows of text: a byte per glyph row,
// $0a starts the next text line ($500 = 8 screen lines), $00 ends the page.
// The panel then lives for 1000 frames, is erased one line a frame for 120
// frames, and the next page is drawn back in one line a frame for another 120.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const P = @import("planes.zig");

const COLS: usize = 40;
const FIRST_CHAR: u8 = 0x20;
const TEXT_ROWS: usize = P.CREDIT_ROWS / 8;
/// $3468 zeroes 50 words a frame while stepping the cursor one line (20 words).
const WIPE_WORDS: usize = 50;
const HOLD_FRAMES: u16 = 1000; // $3434 counts to $3e8

var pages: [4][P.CREDIT_ROWS][P.WORDS]u16 = undefined;

/// One page rendered into its own bit buffer, exactly as $33a2 fills plane 0
/// of a page buffer: column c is the high byte of word c/2 when c is even.
fn layout(page: usize, text: []const u8) void {
    for (&pages[page]) |*row| @memset(row, 0);
    var col: usize = 0;
    var line: usize = 0;
    for (text) |ch| {
        if (ch == '\n') {
            line += 1;
            col = 0;
            continue;
        }
        if (line >= TEXT_ROWS or col >= COLS) continue;
        // The font starts at ' ' and holds 96 cells; a control byte has none.
        if (ch < FIRST_CHAR or ch - FIRST_CHAR >= A.creditsfont.len / 8) continue;
        const glyph = (@as(usize, ch) - FIRST_CHAR) * 8;
        const shift: u4 = if (col & 1 == 0) 8 else 0;
        for (0..8) |r| {
            const bits = @as(u16, A.creditsfont[glyph + r]) << shift;
            pages[page][line * 8 + r][col / 2] |= bits;
        }
        col += 1;
    }
}

pub const Phase = enum { hold, wipe_out, wipe_in };

pub const Credits = struct {
    phase: Phase,
    frames: u16, // $27c64, the 1000-frame hold
    line: usize, // $27c66 / $a0, the wipe cursor
    page: usize, // $27c68, the page the NEXT wipe-in draws from

    pub fn init(self: *Credits) void {
        for (A.credit_pages, 0..) |text, i| layout(i, text);
        @memcpy(&P.credits, &pages[0]); // $340c shows page 0 from the start
        self.phase = .hold;
        self.frames = 0;
        self.line = 0;
        self.page = 1; // $27c68 ships as 1
    }

    pub fn update(self: *Credits) void {
        switch (self.phase) {
            .hold => {
                self.frames += 1;
                if (self.frames < HOLD_FRAMES) return;
                self.frames = 0;
                self.phase = .wipe_out;
                self.line = 0;
            },
            .wipe_out => {
                self.clearRun();
                self.line += 1;
                if (self.line >= P.CREDIT_ROWS) {
                    self.line = 0;
                    self.phase = .wipe_in;
                }
            },
            .wipe_in => {
                if (self.line < P.CREDIT_ROWS)
                    P.credits[self.line] = pages[self.page][self.line];
                self.line += 1;
                // NOT a typo, and NOT symmetric with wipe_out's `>=` above: the
                // original is asymmetric and this reproduces it. Both phases
                // step 160 a frame and compare against $4b00 (= 120 * 160), but
                // the erase at $3468 ends on `blt` (120 frames) and the draw-in
                // at $35ec ends on `ble` (121 — it runs one more idle frame at
                // exactly $4b00). One instruction apart in the binary. Changing
                // this to `>=` "fixes" SLiPPY's off-by-one and shortens the page
                // cycle by a frame, so leave it.
                if (self.line > P.CREDIT_ROWS) {
                    self.line = 0;
                    self.phase = .hold;
                    self.page = (self.page + 1) % A.credit_pages.len;
                }
            },
        }
    }

    /// $3468's 50 words, flattened over the block and clipped at its end (the
    /// original ran two and a half lines past into the screen below).
    fn clearRun(self: *const Credits) void {
        const flat: [*]u16 = @ptrCast(&P.credits);
        const total = P.CREDIT_ROWS * P.WORDS;
        var i = self.line * P.WORDS;
        var n: usize = 0;
        while (n < WIPE_WORDS and i < total) : ({
            n += 1;
            i += 1;
        }) flat[i] = 0;
    }
};
