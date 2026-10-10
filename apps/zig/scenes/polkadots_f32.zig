// POLKA DOTS F32: the same halftone torus bench as polkadots.zig, on the CODEF
// port's own algorithm in f32 (soft-float on the FPU-less board CPU), kept to
// measure the single-precision FPU planned for it.
pub const Demo = @import("polkadots/app.zig").Demo(@import("polkadots/shade_f32.zig"));
