// The scripted runs the DARK SIDE OF THE SPOON menu is traced with, shared by
// the Chrome reference (apps/ulm_dsots_ref.mjs) and the cart's harness
// (apps/ulm_dsots_headless.mjs). [key, down at frame, up at frame]; a key
// goes down or up BEFORE that frame's tick.
export const TIMELINES = {
    // Walk right (camera x, walk cycle, parallax), fly up (camera y), Space in
    // mid-air far from the door (nothing), walk left into the wall at column 11,
    // back right, fly to the ceiling (row 0) and drift right while falling.
    tour: {
        frames: 760,
        hold: [["right", 20, 80], ["up", 90, 150], ["space", 120, 160], ["left", 170, 330], ["right", 340, 420],
            ["up", 430, 640], ["right", 600, 700]],
        shots: [0, 50, 120, 300, 520, 640, 759],
    },
    // From the spawn straight up through the temple's platform (passable from
    // below), land on it in front of the ULM door, then Space.
    door: {
        frames: 200,
        hold: [["up", 3, 133], ["space", 150, 152]],
        shots: [60, 149],
    },
};

/// The frame the door must open on, and a Space that must open nothing.
export const DOOR_FRAME = 150;
