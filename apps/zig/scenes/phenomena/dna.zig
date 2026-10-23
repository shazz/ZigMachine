// --------------------------------------------------------------------------
// The scroller's state, screen.js's chr/frm/slc arrays and scrollMessage /
// renderNextFrames, transcribed. Each array element is one 2-pixel slice of a
// glyph: chr = glyph, frm = which of the 30 rotation frames, slc = which slice.
//
// The arrays are a QUEUE, not a fixed 240: shiftLeft drops the head, and a new
// character pushes all 8 of its slices at once, so the queue runs 240..247
// long. renderNextFrames only turns the first 240, so a fresh character's
// hidden slices wait unturned. That is kept: it is what the remake does.
//
// frm is in twentieths (0.35 = 7, 1 = 20), exact where the remake's doubles
// drift: `> 29` resets to 0, `< 0` adds 30.
// --------------------------------------------------------------------------
const A = @import("assets.zig");

pub const VISIBLE: usize = 240;
pub const ONE: i16 = 20; // frm units per frame
pub const RUN_SPEED: i16 = 7; // rotSpeed 0.35
const WRAP: i16 = 30 * ONE;
const TOP: i16 = 29 * ONE; // frm > 29 resets to 0

// Control characters (screen.js ctrlchars): a pause, with the rotation it sets.
const CTRL_UP: u8 = 0xF0; // '^' 275 frames, rotSpeed -1
const CTRL_DOWN: u8 = 0xF1; // '&' 275 frames, rotSpeed +1
const CTRL_HASH: u8 = 0xF2; // '#' 250 frames, rotSpeed -1
const CTRL_PCT: u8 = 0xF3; // '%' 225 frames, rotSpeed unchanged

/// The message as glyph numbers, control characters as CTRL_*.
const CODES: [A.MESSAGE.len]u8 = blk: {
    @setEvalBranchQuota(200_000);
    var t: [A.MESSAGE.len]u8 = undefined;
    for (A.MESSAGE, 0..) |ch, i| t[i] = switch (ch) {
        '^' => CTRL_UP,
        '&' => CTRL_DOWN,
        '#' => CTRL_HASH,
        '%' => CTRL_PCT,
        else => A.glyphOf(ch),
    };
    break :blk t;
};
const RESTART: u16 = 90; // msgIndex past the end -> 90

pub var chr: [256]u8 = undefined;
pub var frm: [256]i16 = undefined;
pub var slc: [256]u8 = undefined;
pub var head: u8 = 0; // queue element 0 is [head]
pub var len: u16 = 0;
pub var msg_index: u16 = 0;
pub var slice_count: u8 = 0;
pub var pause: bool = true;
pub var pause_time: i32 = 0;
pub var scroll_speed: u8 = 0;
pub var rot_speed: i16 = 0;

pub inline fn cell(i: usize) u8 {
    return head +% @as(u8, @intCast(i));
}

/// screen.js init(): 240 blank slices, then 320 steps to bring the message in.
pub fn reset() void {
    for (0..256) |i| {
        chr[i] = 0;
        frm[i] = 0;
        slc[i] = 0;
    }
    head = 0;
    len = VISIBLE;
    msg_index = 0;
    slice_count = 0;
    pause = true;
    pause_time = 250;
    scroll_speed = 0;
    rot_speed = RUN_SPEED;
    for (0..320) |_| {
        scroll(1);
        turn(rot_speed);
    }
}

fn shiftLeft() void {
    head +%= 1;
    len -= 1;
}

fn addSlicesOfChar(g: u8) void {
    const f = frm[cell(len - 1)];
    for (0..8) |s| {
        const c = cell(len);
        chr[c] = g;
        frm[c] = f;
        slc[c] = @intCast(s);
        len += 1;
    }
}

pub fn scroll(speed: u8) void {
    var i: u8 = 0;
    while (i < speed) : (i += 1) {
        if (slice_count == 0) {
            const code = CODES[msg_index];
            if (code >= CTRL_UP) {
                control(code);
            } else {
                shiftLeft();
                addSlicesOfChar(code);
                slice_count = 1;
            }
            msg_index += 1;
            if (msg_index > CODES.len - 1) msg_index = RESTART;
        } else {
            shiftLeft();
            slice_count = (slice_count + 1) & 7;
        }
    }
}

fn control(code: u8) void {
    pause = true;
    switch (code) {
        CTRL_UP => {
            pause_time = 275;
            rot_speed = -ONE;
        },
        CTRL_DOWN => {
            pause_time = 275;
            rot_speed = ONE;
        },
        CTRL_HASH => {
            pause_time = 250;
            rot_speed = -ONE;
        },
        else => pause_time = 225,
    }
}

/// renderNextFrames: turn the first 240 slices.
pub fn turn(speed: i16) void {
    for (0..VISIBLE) |i| {
        const c = cell(i);
        var v = frm[c] + speed;
        if (v > TOP) v = 0 else if (v < 0) v += WRAP;
        frm[c] = v;
    }
}

/// drawGraphics' scroll step: scroll, or count the pause down.
pub fn tick() void {
    if (!pause) {
        scroll(scroll_speed);
    } else {
        pause_time -= 1;
        if (pause_time == 0) {
            pause = false;
            rot_speed = RUN_SPEED;
            scroll_speed = 1;
        }
    }
}
