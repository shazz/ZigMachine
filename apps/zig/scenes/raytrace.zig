// RAYTRACE: an old-school SDF ray-traced scene (chrome, red, gold, blue and
// green spheres on a checker floor, one light, hard shadows, a sky gradient)
// that doubles as the FPGA CPU benchmark. This cart is the FIXED-POINT one:
// Q16.16 integers and an integer square root, no float in the hot path, for
// the VexRiscv rv32im core that has no FPU. raytrace_f32.zig is the same
// source on f32. Details: raytrace/app.zig, raytrace/fixed.zig.
pub const Demo = @import("raytrace/app.zig").Demo(@import("raytrace/fixed.zig"));
