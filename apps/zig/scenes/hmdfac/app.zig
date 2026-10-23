// --------------------------------------------------------------------------
// HMD "HMDFAC": the timeline. hmdfac.zig carries the port notes; assets.zig
// the rips, cube.zig the frustum, scroll.zig phase 4.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const blit = zg.blit;

const A = @import("assets.zig");
const cube = @import("cube.zig");
const scroll = @import("scroll.zig");

pub const MUSIC = "hmd_cracoucass.sndh";
pub const MUSIC_TUNE = 1;
pub const PLANE = 0;

// --- the frame timeline (all from the dis) ----------------------------------
const BOOT_FRAMES = 200;
const FLASH_FRAMES = 12; // 3 iterations of $1d0..$1f0, 2 frames per word
const CUBE_FRAMES = [3]u32{ 120, 250, 128 }; // the $78/$fa/$80 counters
pub const BOOT_END = BOOT_FRAMES; // 200
pub const FLASH_END = BOOT_END + FLASH_FRAMES; // 212
pub const CUBE1_END = FLASH_END + CUBE_FRAMES[0]; // 332
pub const CUBE2_END = CUBE1_END + CUBE_FRAMES[1]; // 582
pub const CUBE_END = CUBE2_END + CUBE_FRAMES[2]; // 710

/// The flash's visible color0 words, two frames each (the instant #$fff
/// write before the loop never lands on a frame).
const FLASH_C0 = [6]u16{ 0x777, 0xeee, 0x666, 0xddd, 0x555, 0xccc };
const CUBE_C0: u16 = 0xccc; // the flash's last word stands through the cube
const SCROLL_C0: u16 = 0x011; // $3e8, rewritten every phase-4 frame
const SCROLL_POP: u16 = 0x711; // $41a: move.b #$7 into color0's high byte

// --- machine state constants ----------------------------------------------------
const CX0: u32 = 0x1356; // $1660c at boot
const CX_HOLD: u32 = 0x79e; // phase 1's stop value
const CX_STEP: u32 = 0x28;
const WHEEL_MAX: u16 = 0x2ce; // counters wrap to 0 above this
const CNT_INIT: u16 = 0x80; // cc's boot value

const K_ESC: u32 = 0xE012;
const K_SPACE: u32 = 32;
const DIR_BACK: u8 = 6;

/// $fa4's wheel counter: add the step, wrap to 0 above $2ce.
fn adv(c: u16, step: u16) u16 {
    const v = c +% step;
    return if (v > WHEEL_MAX) 0 else v;
}

// --- state: module level, so testapi.zig can read every word ---------------
pub var wants_quit: bool = false;
pub var frame: u32 = 0; // frames since boot; update() arms the frame render() shows
pub var wheel: cube.Wheel = undefined; // ca/cb/cc, camera, this frame's queue pair
pub var qi: u16 = 0; // the $16612 pair walk
pub var popped: bool = false; // SPACE: the $38 key's color0 pop, as a toggle
var pal_key: u32 = 0xFFFF_FFFF; // which register story is installed
var dirty: cube.Rows = .{}; // plate rows the last cube frame drew on
var scroll_on: bool = false; // phase 4's one-time clear + band B done

/// Install palette `words` with color0 = `c0`, only when that changed: the
/// registers hold their colours between frames, as on the machine.
fn setPalette(fb: *zg.LogicalFB, which: u32, words: *const [16]u16, c0: ?u16) void {
    const k_ = (which << 16) | (if (c0) |c| @as(u32, c) else 0xFFFF);
    if (k_ == pal_key) return;
    pal_key = k_;
    for (0..16) |ci| fb.palette[ci] = A.st(words[ci]);
    if (c0) |c| fb.palette[0] = A.st(c);
}

/// The plate's static art (logo + band A) over plate rows [lo, hi] only:
/// $5444's undo of the last frame's overdraw, as CHISEL copies.
fn restoreRows(plate: blit.Dst, lo: i32, hi: i32) void {
    if (lo > hi) return;
    const n: usize = @intCast(hi - lo + 1);
    const y0: usize = @intCast(lo);
    blit.blit(plate, blit.Image.init(A.logo_data, A.ART_W), .{ .x = 0, .y = y0, .w = A.ART_W, .h = n }, 0, lo, null, .copy);
    const a_lo = @max(lo, A.BAND_A_Y);
    const a_hi = @min(hi, A.BAND_A_Y + A.BAND_A_H - 1);
    if (a_lo > a_hi) return;
    const part = blit.Rect{ .x = 0, .y = @intCast(a_lo - A.BAND_A_Y), .w = A.ART_W, .h = @intCast(a_hi - a_lo + 1) };
    blit.blit(plate, blit.Image.init(A.band_a_data, A.ART_W), part, 0, a_lo, null, .copy);
}

fn stepCube(f: u32) void {
    if (f < CUBE1_END) {
        // phase 1: step the camera down until it reaches $79e
        if (wheel.camera != CX_HOLD) {
            const next = wheel.camera -% CX_STEP;
            wheel.camera = if (next <= CX_HOLD) CX_HOLD else next;
        }
    } else if (f >= CUBE2_END) {
        wheel.camera += CX_STEP; // phase 3: back up, no stop
    }
    wheel.ca = adv(wheel.ca, 4);
    wheel.cb = adv(wheel.cb, 2);
    wheel.cc = adv(wheel.cc, 4);
    wheel.sy = A.queue[@as(usize, qi) * 2];
    wheel.sx = A.queue[@as(usize, qi) * 2 + 1];
    qi += 1;
    if (qi >= A.QUEUE_PAIRS) qi = 0;
}

// --------------------------------------------------------------------------
pub const Demo = struct {
    pub fn init(self: *Demo, zigos: *ZigOS) void {
        _ = self;
        wants_quit = false;
        frame = 0;
        wheel = .{ .ca = 0, .cb = 0, .cc = CNT_INIT, .camera = CX0, .sy = 0, .sx = 0 };
        qi = 0;
        popped = false;
        pal_key = 0xFFFF_FFFF;
        dirty = .{};
        scroll_on = false;

        zg.requestSongTune(MUSIC, MUSIC_TUNE);
        zigos.setBackgroundColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });

        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        fb.openBorders(.all);

        // The boot story: sixteen $0011 registers hide the already-painted
        // art; the machine's pages carry the logo + the strip from $1f4 on.
        setPalette(fb, 0, &A.boot_pal, null);
        fb.clearFrameBuffer(0);
        const plate = blit.Dst.plane(fb).window(A.ART_X, A.ART_Y, A.ART_W, A.ART_H);
        restoreRows(plate, 0, A.ART_H - 1);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt; // frame-based: one step a rendered frame
        // the cube phases' per-frame state, in the machine's own order
        if (frame >= FLASH_END and frame < CUBE_END) stepCube(frame);
        frame += 1;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = dt;
        const fb = &zigos.lfbs[PLANE];
        const whole = blit.Dst.plane(fb);
        const plate = whole.window(A.ART_X, A.ART_Y, A.ART_W, A.ART_H);
        const f = frame;
        if (f < BOOT_END) {
            setPalette(fb, 0, &A.boot_pal, null); // sixteen $0011: the roll stays dark
        } else if (f < FLASH_END) {
            setPalette(fb, 1, &A.art_pal, FLASH_C0[(f - BOOT_END) / 2]);
        } else if (f < CUBE_END) {
            setPalette(fb, 1, &A.art_pal, CUBE_C0);
            restoreRows(plate, dirty.lo, dirty.hi);
            dirty = cube.drawFaces(plate, cube.project(wheel));
        } else {
            setPalette(fb, 2, &A.pal4, if (popped) SCROLL_POP else SCROLL_C0);
            if (!scroll_on) scroll.enter(whole);
            scroll_on = true;
            scroll.frame(whole, f - CUBE_END);
        }
    }

    /// SPACE toggles the $38 key's color0 pop ($0711 over $0011, only
    /// meaningful in phase 4 — hmdfac.zig departure 4); Escape and the host's
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
