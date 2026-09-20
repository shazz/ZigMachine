// --------------------------------------------------------------------------
// The 30 floating cubes ($ce8 -> $dd2), two bitplanes deep, behind the panel.
//
// The sprite bank at $c4da holds 360 pre-rendered frames of one rotating cube,
// 32 px wide, 2 planes, 288 bytes apart; the blit draws the first 28 lines of
// each.  $cc8 builds, for object n, the list `frame = (n + t) mod 360` -- an
// exact integer relation, so the wave rolling across the grid is integer here
// too.  The grid is the word table at $c49e: 10 columns 16 bytes apart from a
// base of +$10, 3 rows 34 lines apart from a base of +$2a80.  Column 9 lands
// exactly one screen line on, at x 0 of the row below; the original drew it
// there and so does this.
//
// The cubes' colours are palette entries 1-3, and $b83a rewrites them FOUR
// times down the screen from the Timer-B chain -- at splits 9, 26, 43 and 60 --
// out of the three slots $d24 keeps cross-fading toward the target records
// between $c240 and $c414.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const P = @import("planes.zig");
const pal = @import("palette.zig");

pub const COUNT: usize = 30;
const BASE_Y: usize = 68; // $2a80 / 160
const BASE_BYTE: usize = 16; // the +$10 the blit adds before the table
const REC_WORDS: usize = 9; // 3 cubes x 3 channels
const RECORDS: usize = 26;
const LOOP_RECORD: usize = 13; // $c32a, where the walk restarts
const HOLD_AFTER_LOOP: u16 = 100; // $d96 sets $c228 to $64

/// The rows the Timer-B chain hands each colour set, from split*2 + 47.
pub const BAND_ROW = [5]usize{ 47, 65, 99, 133, 167 };

pub const Cubes = struct {
    t: usize, // $c222
    cur: [3][3]u16, // $c414/$c41a/$c420
    record: usize, // $c23c
    hold: u16, // $c226
    reload: u16, // $c228
    slot: usize, // $c22a

    pub fn init(self: *Cubes) void {
        self.t = 0;
        self.cur = .{.{ 0, 0, 0 }} ** 3; // $c414 ships zeroed
        self.record = 0;
        self.hold = 200;
        self.reload = 25;
        self.slot = 0;
    }

    /// $d24: one slot cross-faded a step per frame, the target record held for
    /// $c228 rounds of three.
    pub fn fadeColours(self: *Cubes) void {
        const base = self.record * REC_WORDS + self.slot * 3;
        for (&self.cur[self.slot], 0..) |*c, i| c.* = pal.stepColour(c.*, A.be(A.cube_targets_b, base + i));
        self.slot += 1;
        if (self.slot < 3) return;
        self.slot = 0;
        self.hold -= 1;
        if (self.hold != 0) return;
        self.record += 1;
        if (self.record >= RECORDS) {
            self.record = LOOP_RECORD;
            self.reload = HOLD_AFTER_LOOP;
        }
        self.hold = self.reload;
    }

    /// The cube colours for band 0..4; band 0 is whatever the VBL's palette
    /// write left in entries 1-3, i.e. the logo palette.
    pub fn band(self: *const Cubes, i: usize, fade: *const pal.Fade) [3]u16 {
        return switch (i) {
            0 => .{ fade.live[1], fade.live[2], fade.live[3] },
            1, 2, 3 => self.cur[i - 1],
            else => .{ A.be(A.cube_targets_b, 0), A.be(A.cube_targets_b, 1), A.be(A.cube_targets_b, 2) },
        };
    }

    pub fn draw(self: *Cubes) void {
        for (0..COUNT) |n| blitCube((n + self.t) % A.CUBE_FRAMES, n / 3, n % 3);
        self.t += 1;
        if (self.t >= A.CUBE_FRAMES) self.t = 0;
    }
};

fn blitCube(frame: usize, col: usize, row: usize) void {
    var byte = BASE_BYTE + col * 16;
    var y = BASE_Y + row * 34;
    if (byte >= 160) {
        byte -= 160;
        y += 1;
    }
    const g = byte / 8;
    var src = frame * A.CUBE_LINES * 8;
    for (0..A.CUBE_LINES) |line| {
        P.cube_lo[y + line][g] = A.be(A.cubes, src / 2);
        P.cube_hi[y + line][g] = A.be(A.cubes, src / 2 + 1);
        P.cube_lo[y + line][g + 1] = A.be(A.cubes, src / 2 + 2);
        P.cube_hi[y + line][g + 1] = A.be(A.cubes, src / 2 + 3);
        src += 8;
    }
}

comptime {
    if (A.cube_targets_b.len != RECORDS * REC_WORDS * 2) @compileError("cube_targets.dat is not 26 records");
    if (BASE_Y + 2 * 34 + A.CUBE_LINES > P.LIVE_TOP + P.LIVE_ROWS)
        @compileError("the cube grid runs below the recomposed band");
}
