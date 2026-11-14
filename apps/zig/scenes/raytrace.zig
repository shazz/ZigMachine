// RAYTRACE: an old-school SDF ray-traced scene (chrome, red, gold, blue and green
// spheres on a checker floor, one light, soft shadows, a sky gradient) in true colour,
// and the FPGA CPU benchmark: the same 16-sample picture in three maths, keys 1..3:
// Q16.16 integers and f32 on ZIGGY, f64 on ASTROLABE (the ARM). It replaced the
// raytrace_f32 twin (cart 85, retired 14 Nov 2026: its f32 is mode 2).
// Details: raytrace/app.zig.
pub const Demo = @import("raytrace/app.zig").Demo;
