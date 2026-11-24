// --------------------------------------------------------------------------
// Follow-play (playadapter.inc `followplay`): while the song plays with follow on, every track's pattern view goes
// to the pattern the player is in and scrolls so the played row stays 12 rows down the screen, and the cursor
// sits on the played row of the current track (when it is on screen). Called once per player tick.
// The toggles: Config AutoFollow (menu row, F1 follows when it is on), C= + F1 / F3 / Run-Stop (setFlwP), and the
// key that flips it while playing (keys.zig `toggflw`).
// --------------------------------------------------------------------------
const dsp = @import("display.zig");
const swm = @import("swm.zig");

const MAX_PTN_LEN = 249; // maxptnlen
const HALF_SCREEN = 12;

pub fn apply(song: *const swm.Song, view: *dsp.View) void {
    for (0..3) |x| {
        const p = view.played_curptn[x];
        if (p == 0 or p > 100) continue; // an empty subtune: leave the view alone
        view.curptn1[x] = p;
        const row = view.ptrowpos[x];
        const top: u8 = if (row >= HALF_SCREEN) row - HALF_SCREEN else 0;
        const limit: u8 = song.ptn_len[p] -% HALF_SCREEN; // lda ptnlength,y / sec / sbc #12
        if (limit < row or top >= MAX_PTN_LEN) continue; // cmp ptrowpos,x / bcc: past the end, keep the old top
        view.prowpos[x] = top;
    }
    const t = view.subwpos1[0];
    if (t > 2) return;
    if (view.ptrowpos[t] < view.prowpos[t]) return;
    const d = view.ptrowpos[t] - view.prowpos[t];
    if (d < 25) view.subwpos3[0] = d;
}

const std = @import("std");

test "follow scrolls the view to the played pattern, keeping the played row 12 down" {
    var song: swm.Song = undefined;
    swm.reset(&song);
    song.ptn_len[5] = 64;
    var v: dsp.View = .{};
    v.played_curptn = .{ 5, 0, 5 };
    v.ptrowpos = .{ 30, 7, 3 };
    apply(&song, &v);
    try std.testing.expectEqual(@as(u8, 5), v.curptn1[0]);
    try std.testing.expectEqual(@as(u8, 18), v.prowpos[0]); // 30 - 12
    try std.testing.expectEqual(@as(u8, 1), v.curptn1[1]); // track 2 has no pattern yet: untouched
    try std.testing.expectEqual(@as(u8, 0), v.prowpos[2]); // row 3: the top
    try std.testing.expectEqual(@as(u8, 12), v.subwpos3[0]); // the cursor on the played row of track 1
}

test "follow leaves the top alone past the pattern's end and the cursor alone off screen" {
    var song: swm.Song = undefined;
    swm.reset(&song);
    song.ptn_len[2] = 20;
    var v: dsp.View = .{};
    v.played_curptn = .{ 2, 0, 0 };
    v.ptrowpos = .{ 19, 0, 0 };
    v.prowpos[0] = 4;
    apply(&song, &v); // 20 - 12 = 8 < 19: skipped
    try std.testing.expectEqual(@as(u8, 4), v.prowpos[0]);
    try std.testing.expectEqual(@as(u8, 15), v.subwpos3[0]);
    v.ptrowpos[0] = 200;
    v.subwpos3[0] = 3;
    apply(&song, &v);
    try std.testing.expectEqual(@as(u8, 3), v.subwpos3[0]); // 200 - 4 >= 25
}
