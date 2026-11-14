// A traced sample before it is a colour: what it hit (its class), its 0..256 light
// intensity and, on the floor, its 0..256 fog. All three engines produce it (trace.zig
// for fixed and f32, astro/rays.zig for ASTROLABE); colour.zig turns it into RGB.
pub const Shade = struct { cls: u8, q: u16, fog: u16 };

pub const CLS_SKY: u8 = 0;
pub const CLS_FLOOR: u8 = 1; // + tone (0 cream, 1 maroon)
pub const CLS_MAT: u8 = 3; // + sphere id (0 chrome, 1 red, 2 gold, 3 blue, 4 green)
