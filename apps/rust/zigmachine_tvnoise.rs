// ---------------------------------------------------------------------------
// zigmachine_tvnoise.rs — the channel-change snow for a Rust cart.
//
// The Rust twin of apps/c/zigmachine_tvnoise.h. On +/- the host calls tuneIn(25)
// instead of skipBoot() (docs/sealed-loader.js); a cart without tuneIn just
// starts. This is apps/zig/demo_main.zig's snow BYTE-FOR-BYTE: tvnoise.zig's
// xorshift32, ramp, band and tears, demo_main's seed and first index, on a 400x280
// overscan plane 0 whose borders are flickered open on every line, in the buffer
// resetForScene + openBorders give it. apps/tunein_check.mjs proves it.
//
// The cart has already run boot(), so tuneIn saves the video registers and
// palette 0 it overwrites and puts them back when the snow ends: the cart's first
// frame sees what skipBoot() would have left.
//
//     mod zigmachine_tvnoise;                          // once per cart: defines tuneIn
//     fn frame(..)       { if zigmachine_tvnoise::step() { return; } ... }
//     fn hblDispatch(..) { if zigmachine_tvnoise::hbl() { return; } ... }
//     fn skipBoot()      { zigmachine_tvnoise::stop(); }
//
// A cart that shows a plane other than 0 must answer isPlaneEnabled with
// `id == 0` while active().
// ---------------------------------------------------------------------------
#![allow(dead_code)] // a cart that shows only plane 0 never asks active()

use core::ptr::addr_of_mut;

#[link(wasm_import_module = "env")]
extern "C" {
    fn hwVideoBase() -> i32;
}

// tvnoise.zig and demo_main.zig. Change one there, change it here.
const LEVELS: u32 = 8;
const RAMP: [u8; LEVELS as usize] = [0x00, 0x24, 0x49, 0x6d, 0x92, 0xb6, 0xdb, 0xff];
const BAND_ROWS: u32 = 24;
const BAND_BOOST: u32 = 3;
const FIRST: u32 = 0; // demo_main NOISE_FIRST
const SEED: u32 = 0x5EED_7E1E; // demo_main NOISE_SEED

// machine/sdk/memmap.zig.
const W: u32 = 400; // PHYSICAL_WIDTH
const H: u32 = 280; // PHYSICAL_HEIGHT
const OFF_PAL: usize = 0x0100;
const PAL_BYTES: usize = 1024;
const REG_RES: usize = 0x00;
const REG_BG: usize = 0x04;
const REG_GHBL_ID: usize = 0x10;
const REG_HBL_ID: usize = 0x20;
const REG_HBL_POS: usize = 0x28;
const REG_FRAME: usize = 0x30; // read-only counter: never restored
const REG_STRIDE: usize = 0x34;
const REG_HSCROLL: usize = 0x3C;
const REG_FB_BASE: usize = 0x44;
const REG_MODE: usize = 0x54;
const REG_FLICKER: usize = 0x58;
const REGS: usize = 0x5C; // everything below REG_CART_HIGH, which the host owns
const MODE_OVERSCAN: u8 = 4;
const RES_PLANES: u8 = 0;
const RES_MEDIUM: u8 = 2;
const MAGIC_X: u16 = 40;
// resetForScene allocates four 320x200 planes from OFF_VRAM, then openBorders
// gives plane 0 the next 400x280: past the cart's own plane-0 buffer.
const SNOW_FB: u32 = 0x1100 + 4 * 64000;

struct Tv {
    tuning: bool,  // snow on screen
    started: bool, // the cart has run: tuneIn is ignored from here on
    frames: u32,
    state: u32,
    roll: u32,
    regs: [u8; REGS],
    pal: [u8; PAL_BYTES],
}

static mut TV: Tv = Tv {
    tuning: false, started: false, frames: 0, state: 0, roll: 0,
    regs: [0; REGS], pal: [0; PAL_BYTES],
};

fn tv() -> &'static mut Tv {
    // SAFETY: wasm32 carts are single-threaded and the host never re-enters.
    unsafe { &mut *addr_of_mut!(TV) }
}

fn io() -> &'static mut [u8] {
    // SAFETY: the registers and palette 0, inside the machine's video region.
    unsafe { core::slice::from_raw_parts_mut(hwVideoBase() as usize as *mut u8, OFF_PAL + PAL_BYTES) }
}

fn put16(io: &mut [u8], off: usize, v: u16) {
    io[off..off + 2].copy_from_slice(&v.to_le_bytes());
}

impl Tv {
    /// tvnoise.zig Noise.next.
    fn next(&mut self) -> u32 {
        let mut x = self.state;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.state = x;
        x
    }

    /// tvnoise.zig Noise.fill, over the whole 400x280 buffer.
    fn fill(&mut self, buf: &mut [u8]) {
        let tear_a = self.next() % H;
        let tear_b = self.next() % H;
        for (y, row) in (0..H).zip(buf.chunks_exact_mut(W as usize)) {
            if y == tear_a || y == tear_b {
                let jitter = self.next() % 8;
                for (x, px) in (0..W).zip(row.iter_mut()) {
                    *px = (if x < jitter { FIRST + 2 } else { FIRST }) as u8;
                }
                continue;
            }
            let in_band = y.wrapping_sub(self.roll) % H < BAND_ROWS;
            let (mut bits, mut left) = (0u32, 0u32);
            for px in row.iter_mut() {
                if left < 3 {
                    bits = self.next();
                    left = 30;
                }
                let mut lvl = bits & 7;
                bits >>= 3;
                left -= 3;
                if in_band {
                    lvl = (lvl + BAND_BOOST).min(LEVELS - 1);
                }
                *px = (FIRST + lvl) as u8;
            }
        }
        self.roll = (self.roll + 3) % H;
    }
}

/// End the snow now (if any) and give the machine back to the cart. Also the
/// cart's skipBoot: Escape during the snow lands in the cart, as in demo_main.
pub fn stop() {
    let t = tv();
    if t.tuning {
        let io = io();
        io[..REG_FRAME].copy_from_slice(&t.regs[..REG_FRAME]);
        io[REG_FRAME + 4..REGS].copy_from_slice(&t.regs[REG_FRAME + 4..]);
        io[OFF_PAL..].copy_from_slice(&t.pal);
    }
    t.tuning = false;
    t.started = true;
}

pub fn active() -> bool {
    tv().tuning
}

/// Call first thing in frame(). True = this frame was snow, return without
/// drawing. The frame after the last snow frame restores the machine and returns
/// false, so the cart draws it: its first, exactly as after skipBoot().
pub fn step() -> bool {
    let t = tv();
    if t.tuning && t.frames > 0 {
        t.frames -= 1;
        // SAFETY: the snow's 400x280 buffer, inside the machine's VRAM pool.
        let buf = unsafe {
            core::slice::from_raw_parts_mut((hwVideoBase() as u32 + SNOW_FB) as *mut u8, (W * H) as usize)
        };
        t.fill(buf);
        return true;
    }
    stop();
    false
}

/// Call first thing in hblDispatch(). True = the snow's HBL: open this line's borders.
pub fn hbl() -> bool {
    if !tv().tuning {
        return false;
    }
    let io = io();
    io[REG_RES] = RES_MEDIUM; // the ST resolution flicker (zigos flickerBorder)
    io[REG_RES] = RES_PLANES;
    let latch = u16::from_le_bytes([io[REG_FLICKER], io[REG_FLICKER + 1]]);
    put16(io, REG_FLICKER, latch.wrapping_add(1));
    true
}

/// demo_main tuneIn: `frames` frames of snow over the whole tube, then the cart.
#[no_mangle]
pub extern "C" fn tuneIn(frames: u32) {
    let t = tv();
    if t.started {
        return; // a running cart ignores it
    }
    if frames == 0 {
        return stop();
    }
    let io = io();
    if !t.tuning {
        // a second tuneIn must not save the snow as the cart's state
        t.regs.copy_from_slice(&io[..REGS]);
        t.pal.copy_from_slice(&io[OFF_PAL..]);
    }
    // resetForScene: planes resolution, dark grey border, no global HBL, palette 0 clear.
    io[REG_RES] = RES_PLANES;
    io[REG_BG..REG_BG + 4].copy_from_slice(&[20, 20, 20, 255]);
    put16(io, REG_GHBL_ID, 0);
    io[OFF_PAL..].fill(0);
    // openBorders(.all) on plane 0: overscan buffer, HBL id plane+1 at the magic column.
    put16(io, REG_STRIDE, W as u16);
    put16(io, REG_HSCROLL, 0);
    io[REG_MODE] = MODE_OVERSCAN;
    io[REG_FB_BASE..REG_FB_BASE + 4].copy_from_slice(&SNOW_FB.to_le_bytes());
    put16(io, REG_HBL_ID, 1);
    put16(io, REG_HBL_POS, MAGIC_X);
    for (i, &g) in RAMP.iter().enumerate() {
        let e = OFF_PAL + (FIRST as usize + i) * 4;
        io[e..e + 4].copy_from_slice(&[g, g, g, 255]);
    }
    t.state = SEED; // tvnoise.zig maps only seed 0 elsewhere
    t.roll = 0;
    t.frames = frames;
    t.tuning = true;
}
