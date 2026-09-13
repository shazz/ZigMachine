// The few f64 helpers the screen needs. `no_std` Rust has no libm (f64::sin and
// f64::floor live in std), and the screen's tables are driven by Math.sin on
// unbounded phases, so sin has to be accurate everywhere, not a lookup table.

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

/// Math.sin to ~1e-14: fold into [-PI/2, PI/2], then a Horner Taylor series.
pub fn sin(x: f64) -> f64 {
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
