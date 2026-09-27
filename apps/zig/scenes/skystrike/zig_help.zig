// --------------------------------------------------------------------------
// ZIG mode's key help, over the game while it is paused (P: line 151 waits
// for a key with the music on). ORIGINAL shows the pause as the ST did.
//
// Every binding is the listing's (lines 80-165, 350-381) as this port maps
// the ST's keys (skystrike.zig's hostKey, input.zig: the arrows are the
// joystick, Space its fire, F1-F10 the scancodes 59-68 the game tests):
//   80-81 up/down turn the plane; 120/129 left/right the throttle, when not
//   firing, down to 4 at the least; 150 0-9; 350-381 fire, fire+left a bomb,
//   fire+right a rocket -- in ZIG one key each, Ctrl, Space and Shift, and
//   Ctrl is a fire button for the chords (zig_keys.zig); 124 C/F9 cluster
//   (a bonus held); 125 B/F5 turbo (a bonus held); 152 U/F10 wheels; 162
//   T/F3 turn round (stopped); 156
//   F/F8 gives up a plane landed and stopped for a new one (it costs one,
//   line 68); 161 S the carrier's catapult; 157 A autoland on an airfield's
//   sector (not on Hard: atlf, 2133; it costs points); 158 M/F2 moves the
//   main base; 160 E/F4 the extinguisher (a bonus held); 121 R repairs this
//   sector's base; 106 W/F7 waggles the wings; 153 Esc bails out; 154 Enter
//   opens the chute; 155 Space lands it; 82-83 left/right steer it.
//
// Drawn like the game's own boxed messages (1506: SQUARE's frame 3 pixels
// inside the cells, corners out, pen 1 on paper 14, the text pen 0) in its
// 8x8 font, onto the overlay only: the game's screens are never touched.
// It ends with ZIG's music and its licences (zig_music.zig).
// --------------------------------------------------------------------------
const flow = @import("flow.zig");
const hud = @import("zig_hud.zig");
const scroll = @import("zig_scroll.zig");

const LINES = [_][]const u8{
    "@          K E Y S",
    "@FLYING",
    " Up/Down     turn     0-9  throttle",
    " Right/Left  throttle up/down (not below 4)",
    "@WEAPONS",
    " Ctrl  guns   Shift  rocket   Space  bomb",
    " Ctrl+Left  bomb      Ctrl+Right  rocket",
    " C/F9 cluster bomb   B/F5 turbo",
    "@ON THE GROUND",
    " U/F10 wheels        T/F3 turn round",
    " S  catapult         M/F2 move main base",
    " R  repair base      E/F4 extinguisher",
    " A  autoland (not on Hard)",
    " F/F8 new plane (costs one)",
    " W/F7 waggle the wings",
    "@EMERGENCY",
    " Esc bail out        Enter open the chute",
    " Space land it       Left/Right steer it",
    "@MUSIC (The Mod Archive)",
    " Explore the sky   BLuRry     CC BY-SA 4.0",
    " The Hawk's Claw   Drozerix   Public Domain",
    " dog75             Songerson  CC BY 4.0",
    "@P pause   Z ORIGINAL/ZIG   any key: fly",
};
const COLS: usize = 46;
const ROWS: usize = LINES.len + 2;
const W: usize = @intCast(scroll.WIN_W);
/// The panel's top-left in the frame: centred in the world's part.
pub const X0: usize = (W - COLS * 8) / 2;
pub const Y0: usize = (@as(usize, @intCast(scroll.VIEW_H)) - ROWS * 8) / 2;
const PAPER: u8 = 14;
const FRAME: u8 = 1;
const TEXT: u8 = 0;
const HEAD: u8 = 1;

pub var shown: bool = false;

/// While line 151 waits for the key that ends the pause.
pub fn draw(ov: []u8) void {
    shown = flow.pc == .l151a;
    if (!shown) return;
    for (0..ROWS * 8) |y| @memset(ov[(Y0 + y) * W + X0 ..][0 .. COLS * 8], PAPER);
    frame(ov);
    for (LINES, 0..) |line, r| {
        const head = line[0] == '@';
        const s = if (head) line[1..] else line;
        hud.text(ov, W, X0 + 8, Y0 + 8 + r * 8, s, if (head) HEAD else TEXT, null);
    }
}

/// SQUARE's frame: 3 pixels inside the cells, the corners left out.
fn frame(ov: []u8) void {
    const x1 = X0 + COLS * 8 - 1;
    const y1 = Y0 + ROWS * 8 - 1;
    for (X0 + 4..x1 - 3) |x| {
        ov[(Y0 + 3) * W + x] = FRAME;
        ov[(y1 - 3) * W + x] = FRAME;
    }
    for (Y0 + 4..y1 - 3) |y| {
        ov[y * W + X0 + 3] = FRAME;
        ov[y * W + x1 - 3] = FRAME;
    }
}
