// RAYTRACE F32: the same ray-traced scene as raytrace.zig on f32 numbers, for
// the side-by-side benchmark (soft-float on the FPGA's FPU-less core).
pub const Demo = @import("raytrace/app.zig").Demo(@import("raytrace/float.zig"));
