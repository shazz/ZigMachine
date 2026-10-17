// The few f64 helpers the screen needs. `no_std` Rust has no libm (f64::sin and
// f64::floor live in std). The per-frame path is integer only (the board's FPU
// is single precision, so every f64 op is a slow soft-float routine): phases are
// u64 turns (2^64 = 2 PI), sin is a Q24 table with linear interpolation. The
// f64 `sin_f64` below runs once, at init, to build that table.

const PI: f64 = 3.141_592_653_589_793;
const TAU: f64 = 2.0 * PI;

pub fn floor(x: f64) -> i32 {
    let t = x as i32;
    if (t as f64) > x { t - 1 } else { t }
}

pub fn ceil(x: f64) -> i32 {
    let t = x as i32;
    if (t as f64) < x { t + 1 } else { t }
}

/// A CODEF canvas coordinate (640x400) to the nearest ST pixel (320x200).
pub fn half(x: f64) -> i32 {
    floor(x * 0.5 + 0.5)
}

/// Math.sin (init only) to ~1e-14: fold into [-PI/2, PI/2], then a Horner Taylor series.
fn sin_f64(x: f64) -> f64 {
    let turns = x / TAU;
    let mut r = x - TAU * ((turns as i64) as f64 - if turns < 0.0 { 1.0 } else { 0.0 });
    if r > PI {
        r -= TAU; // now (-PI, PI]
    }
    if r > PI / 2.0 {
        r = PI - r;
    } else if r < -PI / 2.0 {
        r = -PI - r;
    }
    let q = r * r;
    r * (1.0 - q / 6.0 * (1.0 - q / 20.0 * (1.0 - q / 42.0 * (1.0 - q / 72.0
        * (1.0 - q / 110.0 * (1.0 - q / 156.0 * (1.0 - q / 210.0 * (1.0 - q / 272.0))))))))
}

/// 0.1 rad and 0.05 rad as u64 turns: round(rad / TAU * 2^64). Every phase step of
/// the screen is a small integer multiple of one of them (0.2 = 2x, 0.8 = 16x of
/// 0.05), so a phase advanced N times is N*STEP with no accumulated drift.
pub const TURN_0_1: u64 = 293_589_050_328_200_123;
pub const TURN_0_05: u64 = 146_794_525_164_100_061;

const QUARTER: usize = 1024; // table steps per quarter turn
const SIZE: usize = 4 * QUARTER;
static mut TABLE: [i32; SIZE + 1] = [0; SIZE + 1];

/// Build the Q24 sine table once, from the f64 series (init only, ~1k calls).
pub fn init() {
    // SAFETY: wasm32 carts are single-threaded and the host never re-enters;
    // nothing reads TABLE before boot() has returned.
    let t = unsafe { &mut *core::ptr::addr_of_mut!(TABLE) };
    for i in 0..=QUARTER {
        let v = floor(sin_f64(i as f64 * (PI / 2.0) / QUARTER as f64) * 16777216.0 + 0.5);
        t[i] = v;
        t[2 * QUARTER - i] = v;
        t[2 * QUARTER + i] = -v;
        t[SIZE - i] = -v;
    }
}

/// sin of a u64-turns phase as Q24 (1 << 24 = 1.0): the top 12 bits index the
/// table, the next 16 interpolate between neighbours (error < 3e-7).
pub fn sin_q24(phase: u64) -> i32 {
    let p = (phase >> 32) as u32;
    let i = (p >> 20) as usize;
    let frac = ((p >> 4) & 0xFFFF) as i32;
    // SAFETY: read-only after init(); i < SIZE so i + 1 <= SIZE is in bounds.
    let t = unsafe { &*core::ptr::addr_of!(TABLE) };
    t[i] + (((t[i + 1] - t[i]) * frac) >> 16)
}
