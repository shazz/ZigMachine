// REPLICANTS EMLYN F32: the same Emlyn Hughes cracktro as replicants_emlyn.zig,
// on the CODEF port's own algorithm in f32 (soft-float on the FPU-less board
// CPU), kept to measure the single-precision FPU planned for it.
pub const Demo = @import("replicants_emlyn/app.zig").Demo(@import("replicants_emlyn/float.zig"));
