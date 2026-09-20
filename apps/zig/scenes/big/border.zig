// The B.I.G. Demo's SIDE BORDERS — the part the CODEF remake does not have.
//
// The remake's main.png is 640x540 = exactly 2x 320x270 and stops at the screen
// edge, so the remake simply has no data for the left and right borders. The
// real screen is full overscan and USES them: the song-list frame's shadow and
// the bottom scroller's pipes and shadows all run out past the 320 columns
// (Matt, 2026-09-19). Following the real demo over the remake is the standing
// rule for this screen.
//
// HOW THE MACHINE DOES IT. There is no artwork out there. The border is palette
// entry 0, and the HBL chain writes colour 0 once (sometimes twice) per
// scanline, so every border row is ONE FLAT COLOUR. A row where colour 0 is
// written twice shows the early value on the left and the late one on the
// right — that is the only way left and right ever differ, and it is what the
// song-list frame's one-sided shadow is.
//
// WHERE THE NUMBERS COME FROM. Measured off the atarimania capture of the real
// screen (prototypes/codef/23/atarimania/BIG_DEMO.gif), not from the 68000
// code. That capture is 768x540 = exactly 2x on both axes; halved it is 384x270
// and splits cleanly as 32 flat border columns, 320 content columns, 32 flat
// border columns. Every one of its colours sits on an 8-level ladder with ZERO
// error, so the ST nibbles are exactly recoverable, and the levels land on
// main.png's own grey ladder (0,32,64,...,224 = level x 32) with nothing to
// convert or guess: $0333 IS pen 4, $0555 IS PANEL.
//
// The capture is offset 16 rows from the remake's canvas (capture row = content
// row + 16), pinned three ways: main.png correlates best at +16, and the two
// rows where the border pulses land exactly on RULE_Y = {107, 115} — the rules
// that bracket the cursor. The pulse rows are not listed below because the
// PULSE pen already carries them; painting them here once is enough, the
// palette write does the rest (see assets.PULSE_RAMP).
//
// WHAT IS MEASURED AND WHAT IS NOT. Content rows 0..253 are measured. The
// capture is a 270-row crop that ends there, so rows 254..269 are NOT:
//   254, 255  extend the 250..255 shadow using SHADOW_TONE's own {1,0,0,0,0,1}
//             shape, whose first four rows the capture does confirm
//   256..269  PANEL, on the evidence that every other gap between features is
// Both are flagged rather than silently filled. One frame of one capture, so a
// colour that animates would read here as a constant — only the two pulse rows
// are known to move, and they are not in this table.
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;
const A = @import("assets.zig");

/// main.png's grey ladder is ST level x 32, so an ST word maps to a pen with
/// no conversion at all. PANEL (pen 6) is $0555, the screen's own grey.
const G3: u8 = 4; // $0333
const G4: u8 = 5; // $0444
const G6: u8 = 7; // $0666
const G7: u8 = 8; // $0777
const PA: u8 = A.PANEL; // $0555
const PU: u8 = A.PULSE; // driven per frame from the gradient

const Run = struct { last: u16, l: u8, r: u8 };

/// Content rows 0..269, as runs. `last` is the run's final row, so a run covers
/// (previous.last + 1) .. last. Left and right differ only where the HBL writes
/// colour 0 twice on the line.
const RUNS = [_]Run{
    .{ .last = 93, .l = PA, .r = PA },
    // The song-list frame's shadow: RIGHT border only, six rows, the same
    // {outer, inner x4, outer} shape as the on-screen shadow strips.
    .{ .last = 94, .l = PA, .r = G4 },
    .{ .last = 98, .l = PA, .r = G3 },
    .{ .last = 99, .l = PA, .r = G4 },
    .{ .last = 106, .l = PA, .r = PA },
    .{ .last = 107, .l = PU, .r = PU }, // RULE_Y[0]
    .{ .last = 114, .l = PA, .r = PA },
    .{ .last = 115, .l = PU, .r = PU }, // RULE_Y[1]
    .{ .last = 146, .l = PA, .r = PA },
    .{ .last = 147, .l = PA, .r = G4 }, // the frame's lower shadow, same shape
    .{ .last = 151, .l = PA, .r = G3 },
    .{ .last = 152, .l = PA, .r = G4 },
    .{ .last = 213, .l = PA, .r = PA },
    // The scroller frame's upper pipe: a lit edge falling away into shade.
    .{ .last = 214, .l = G6, .r = G6 },
    .{ .last = 215, .l = G7, .r = G7 },
    .{ .last = 216, .l = G6, .r = G6 },
    .{ .last = 217, .l = PA, .r = PA },
    .{ .last = 218, .l = G4, .r = G4 },
    .{ .last = 219, .l = G3, .r = G3 },
    .{ .last = 223, .l = PA, .r = PA },
    .{ .last = 224, .l = G4, .r = G4 }, // SHADOW_Y[0], both sides
    .{ .last = 228, .l = G3, .r = G3 },
    .{ .last = 229, .l = G4, .r = G4 },
    .{ .last = 239, .l = PA, .r = PA },
    .{ .last = 240, .l = G6, .r = G6 }, // the lower pipe, same six rows
    .{ .last = 241, .l = G7, .r = G7 },
    .{ .last = 242, .l = G6, .r = G6 },
    .{ .last = 243, .l = PA, .r = PA },
    .{ .last = 244, .l = G4, .r = G4 },
    .{ .last = 245, .l = G3, .r = G3 },
    .{ .last = 249, .l = PA, .r = PA },
    .{ .last = 250, .l = G4, .r = G4 }, // SHADOW_Y[1]; 251..253 measured,
    .{ .last = 254, .l = G3, .r = G3 }, // 254 extended from SHADOW_TONE
    .{ .last = 255, .l = G4, .r = G4 }, // 255 extended, likewise
    .{ .last = 269, .l = PA, .r = PA }, // 256.. NOT measured: see the header
};

/// Paint both margins for every content row. Called once, from init: colour 0
/// is static for the whole screen except the two pulse rows, and those carry
/// the PULSE pen, so the per-frame palette write moves them without a redraw.
///
/// NOT applied differently during the 200-frame instruction screen. Whether the
/// real demo's wait() runs the same HBL chain is NOT known — the capture is of
/// the jukebox — and painting one border is a smaller invention than inventing
/// a second one.
pub fn paint(fb: *LogicalFB) void {
    var y: usize = 0;
    for (RUNS) |run| {
        while (y <= run.last) : (y += 1) {
            const base = (A.TOP + y) * A.STRIDE;
            @memset(fb.fb[base..][0..A.LEFT], run.l);
            @memset(fb.fb[base + A.LEFT + A.W ..][0 .. A.STRIDE - A.LEFT - A.W], run.r);
        }
    }
}

/// Repaint just the two rule rows' margins. wait() and go() do not agree about
/// what belongs there: go()'s rows carry the gradient (measured), wait()'s are
/// not in any capture we have. They are held at PANEL until go() takes over,
/// because an unknown row that matches the panel cannot look broken, and a
/// stray pen there would be two coloured dashes in a grey border for 200
/// frames. Stated as a choice, not a measurement.
pub fn paintRules(fb: *LogicalFB, pen: u8) void {
    for (A.RULE_Y) |ry| {
        const base = (A.TOP + @as(usize, ry)) * A.STRIDE;
        @memset(fb.fb[base..][0..A.LEFT], pen);
        @memset(fb.fb[base + A.LEFT + A.W ..][0 .. A.STRIDE - A.LEFT - A.W], pen);
    }
}

comptime {
    if (RUNS[RUNS.len - 1].last != A.H - 1) @compileError("the border runs do not cover all 270 rows");
    var prev: i32 = -1;
    for (RUNS) |run| {
        if (@as(i32, run.last) <= prev) @compileError("the border runs are not in order");
        prev = run.last;
    }
    // The two rows the gradient drives must be exactly the two rules, or the
    // border pulses out of step with the rules it is supposed to continue.
    for (A.RULE_Y) |ry| {
        var found = false;
        for (RUNS) |run| {
            if (run.last == ry and run.l == PU) found = true;
        }
        if (!found) @compileError("a rule row has no PULSE run in the border table");
    }
}
