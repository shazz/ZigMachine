// --------------------------------------------------------------------------
// HMD "Factory Cracktro": the timeline. hmdfac.zig carries the port notes;
// assets.zig the rips, rasters.zig the Timer B chain, cube_run.zig +
// cube.zig + cube_fill.zig the frustum, p4.zig + p4_dots.zig + p4_scroll.zig
// phase 4.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;

const A = @import("assets.zig");
const R = @import("rasters.zig");
const run = @import("cube_run.zig");
const p4 = @import("p4.zig");

pub const MUSIC = "hmd_cracoucass.sndh";
pub const MUSIC_TUNE = 1;
pub const PLANE = 0;

// --- the frame timeline (from the original, frames from the first loop VBL)
pub const OPEN_END = 193; // $b9dc: 192 bob words, then word 0 once more
pub const FLASH_END = OPEN_END + 12; // $ac6a: 3 x (-$888, 2 frames, +$777, 2 frames)
pub const HOLD_END = FLASH_END + 4; // band A pasted into both pages, still $ccc
pub const CUBE1_END = HOLD_END + 120; // the $78 / $fa / $80 loop counters
pub const CUBE2_END = CUBE1_END + 250;
pub const CUBE_END = CUBE2_END + 128;
pub const P4_START = CUBE_END + 17; // pages cleared, band B, $1108c/$1103a precalc

const FLASH_C0 = [6]u16{ 0x777, 0xeee, 0x666, 0xddd, 0x555, 0xccc };
const HOLD_C0: u16 = 0xccc;
const POP_C0: u16 = 0x711; // the $38 key: move.b #$7 into colour 0's high byte
const BUF_H = 2 * p4.HALF; // two pages; the bob reads up to 32 lines into the first's spare

const K_ESC: u32 = 0xE012;
const K_SPACE: u32 = 32;
const DIR_BACK: u8 = 6;

// --- state: module level, so testapi.zig can read every word ---------------
pub var wants_quit: bool = false;
pub var frame: u32 = 0; // frames since start; update() arms the one render() shows
pub var popped: bool = false;
pub var bob_off: u32 = 0; // lines the opening's screen address is moved down by

/// Frames the Timer B chain has run before frame f (it is off in the flash).
pub fn laserCount(f: u32) u32 {
    if (f < OPEN_END) return f;
    if (f < HOLD_END) return OPEN_END;
    return OPEN_END + f - HOLD_END;
}

/// The opening's screen offset in lines: $2d1ea words / 160.
pub fn bobLines(f: u32) u32 {
    const i = if (f < A.BOB_N) f else 0;
    return A.bob[i] / 160;
}

/// The opening: the logo page read from `off` lines down, stripes kept on
/// their physical rows.
fn setOffset(fb: *zg.LogicalFB, whole: blit.Dst, off: u32) void {
    if (off == bob_off) return;
    R.unstamp(whole, bob_off);
    bob_off = off;
    fb.setScroll(0, off);
    R.stamp(whole, off, false);
}

/// The register story of frame f: which palettes the chain installs and
/// what the lasers show.
fn palettes(fb: *zg.LogicalFB, f: u32) void {
    if (f >= OPEN_END and f < HOLD_END) {
        const c0 = if (f < FLASH_END) FLASH_C0[(f - OPEN_END) / 2] else HOLD_C0;
        R.setPalettes(&A.art_pal, &A.art_pal, c0, null);
        return R.lasers(fb, 0, c0);
    }
    const pop: ?u16 = if (popped) POP_C0 else null;
    const bottom = if (f < CUBE1_END) &A.boot_pal else if (f < CUBE_END) &A.art_pal else &A.band_pal;
    R.setPalettes(if (f < CUBE_END) &A.art_pal else &A.pal4, bottom, null, pop);
    R.lasers(fb, laserCount(f), null);
}

// --------------------------------------------------------------------------
pub const Demo = struct {
    pub fn init(self: *Demo, zigos: *ZigOS) void {
        _ = self;
        wants_quit = false;
        frame = 0;
        popped = false;
        run.reset();
        p4.alloc();

        zg.requestSongTune(MUSIC, MUSIC_TUNE);
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.setOverscanScrollPlane(zg.PHYSICAL_WIDTH, BUF_H);
        R.install(fb);
        const whole = blit.Dst.plane(fb);
        const plate = whole.window(A.ART_X, A.ART_Y, A.ART_W, A.ART_H);
        blit.blit(plate, blit.Image.init(A.logo_data, A.ART_W), null, 0, 0, null, .copy);
        bob_off = bobLines(0);
        fb.setScroll(0, bob_off);
        R.stamp(whole, bob_off, false);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt; // frame-based: one step a rendered frame
        const f = frame;
        if (f >= HOLD_END and f < CUBE_END) run.step(if (f < CUBE1_END) 1 else if (f < CUBE2_END) 2 else 3);
        frame += 1;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        const whole = blit.Dst.plane(fb);
        const plate = whole.window(A.ART_X, A.ART_Y, A.ART_W, A.ART_H);
        const f = frame - 1; // update() already counted this frame
        palettes(fb, f);
        if (f < OPEN_END) return setOffset(fb, whole, bobLines(f));
        if (f == OPEN_END) setOffset(fb, whole, 0); // the cube page
        if (f == HOLD_END) {
            run.restoreRows(plate, A.BAND_A_Y, A.BAND_A_Y + A.BAND_A_H - 1);
            R.stamp(whole, 0, true); // band A's blank top rows covered line 196
        }
        if (f >= HOLD_END and f < CUBE_END) return run.frame(whole, plate);
        if (f == CUBE_END) p4.reset(whole); // $ade0..$ae76
        if (f >= P4_START) p4.frame(fb, whole);
    }

    /// SPACE toggles the $38 key's colour-0 pop ($0711 over lines 0..1 and
    /// the top border, until the top palette reload); Escape and the host's
    /// Back leave (declaring key() owns every key).
    pub fn key(self: *Demo, cp: u32) void {
        _ = self;
        if (cp == K_SPACE) popped = !popped else if (cp == K_ESC) wants_quit = true;
    }

    pub fn input(self: *Demo, dir: u8) void {
        _ = self;
        if (dir == DIR_BACK) wants_quit = true;
    }

    pub fn pollCart(self: *Demo) i32 {
        _ = self;
        return if (wants_quit) -1 else 0;
    }
};
