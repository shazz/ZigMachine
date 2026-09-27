// --------------------------------------------------------------------------
// ZIG mode's settings: every value the mode can be tuned by, in one file, so
// a settings panel can be built on it. ORIGINAL reads none of them. The zig_*
// modules take their numbers from here and keep no tunable of their own.
//
// `var`s may change at run time (the harness sets some); `const`s size the
// frame and the buffers, so they are fixed at build time.
// --------------------------------------------------------------------------
const Sample = @import("zig_sound.zig").Sample;

// ---- the mode -------------------------------------------------------------
/// The mode at power on; Z switches (the harness's lockstep power-on is
/// ORIGINAL whatever this says).
pub const default_zig: bool = true;
/// Frames (at 50 Hz) the "ZIG MODE" / "ORIGINAL MODE" notice stays up.
pub const notice_frames: u32 = 100;
/// Its line on the 320 x 200 notice plane.
pub const notice_y: usize = 24;
/// The title, the menu, the briefings, the hall of fame and its name entry
/// in the open-bordered 400 x 280 frame (false: the ST's 320 x 200): the
/// screen 1:1 at screen_x, screen_y with the world extended round it, or the
/// hall's picture scaled under its text (zig_screens.zig).
pub var fullscreen_screens: bool = true;
/// Where the 320 x 200 screen (and the hall's text) sits in the frame: the
/// centre of the 400 columns and of the 240 lines above the bottom border.
pub const screen_x: usize = 40;
pub const screen_y: usize = 40;

// ---- the title's credits scroller (zig_scroller.zig) ------------------------
/// Its first line in the frame: in the bottom border (lines 240-279), its 8
/// lines centred in the 30 above the hud_bottom_margin a monitor covers.
pub const scroller_y: usize = 251;
/// Its colour, an ST colour word (0x777 white); it fades with the screen.
pub const scroller_rgb: u16 = 0x777;
/// Its speed's source is the game's own pass counter (ti, 2005-2006): one
/// pixel every this many passes, a letter every 8 pixels. 3 is the original.
pub const scroller_passes_per_px: i32 = 3;

// ---- the frame (overscan: 400 columns x 280 lines) -------------------------
/// Lines left clear under the HUD panel, where a monitor's frame covers.
pub const hud_bottom_margin: usize = 10;
/// The HUD panel (and the ammo counter beside it) moved sideways from the
/// frame's centre, px; negative is left. Matt, 2026-09-27: 10 px left
/// centres it on the monitor.
pub const hud_x_shift: i32 = -10;
/// Lines the bonus bar's box is moved down from the frame's top.
pub const bar_top_margin: usize = 20;
/// Where the plane sits in the frame (px), the camera's target.
pub const plane_x: i32 = 200;
pub const plane_y: i32 = 128;

// ---- the camera -----------------------------------------------------------
/// Each frame the camera closes 1 / glide_div of the distance to the plane...
pub const glide_div: i32 = 3;
/// ...but at most glide_cap px a frame.
pub const glide_cap: i32 = 16;
/// A jump longer than this (px) is a cut, not a glide (a new plane, the
/// autoland).
pub const glide_snap: i32 = 320;

// ---- the tracers ----------------------------------------------------------
/// Streaks per round the guns take.
pub const tracer_per_round: i32 = 3;
/// Streaks on screen at most.
pub const tracer_max: usize = 12;
/// Pixels a frame, per unit of the heading table (its longest step is 6).
pub const tracer_speed: i32 = 2;
/// A streak's length and the first tracer_head px of it in the head colour.
pub const tracer_len: i32 = 7;
pub const tracer_head: i32 = 3;
/// Frames a streak lives at most (it also ends at the view's edge).
pub const tracer_life: u8 = 30;
/// An enemy fighter this close (px) to a streak's head stops it.
pub const tracer_reach: i32 = 10;

// ---- the craters ----------------------------------------------------------
/// VBLs (50.053 Hz) before the hole an enemy fighter made where it crashed
/// fills in again; 0 = never, as in the original. 30 s. GAMEPLAY: a crater
/// that expires changes the sector's gun bits and wreck table.
pub var crater_life_vbls: u32 = 1502;
/// Holes remembered at once; a crash while all are waiting stays for good.
pub const crater_max: usize = 8;

// ---- the weapon keys ------------------------------------------------------
/// Host key codes (docs/sealed-loader.js MOD_CODES). Each is one key for the
/// chord the original needs: guns = FIRE, rocket = FIRE + right, and Space
/// (unless the pilot has bailed out, when it lands the chute) = FIRE + left,
/// a bomb. The arrows + FIRE chords still work.
pub const key_guns: u32 = 0xE014; // left Ctrl
pub const key_rocket: u32 = 0xE015; // left Shift
pub var space_bombs: bool = true;

// ---- the sound effects ----------------------------------------------------
/// The sample each of the original's effect routines (sfx.zig) plays. There
/// is no volume to set: skystrike.sndh plays them on the STE DMA chip at its
/// full level, as the Microwire volume is not emulated (ste_dma.zig).
pub const Effects = struct {
    guns: Sample = .gun, // 995, looped while firing
    bang: Sample = .bang, // 998: an enemy hit, flak
    crash: Sample = .crash, // 994
    bomb: Sample = .bomb, // 993 on land
    splash: Sample = .splash, // 993 on water
    hit: Sample = .hit, // 997: a scrape, the catapult
};
pub var effects: Effects = .{};

// ---- the music ------------------------------------------------------------
// ORIGINAL plays skystrike.sndh's three tunes (sound.zig); ZIG three
// ProTracker MODs from The Mod Archive, one per situation (zig_music.zig;
// docs/music/skystrike_music_CREDITS.txt).
