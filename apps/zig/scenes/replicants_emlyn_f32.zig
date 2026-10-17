// REPLICANTS EMLYN F32: the same Emlyn Hughes cracktro as replicants_emlyn.zig,
// booting with its per-frame maths on the CODEF port's own algorithm in f32
// (the FPU test cart: hardware float on a ZM_FPU=1 board, soft-float elsewhere).
// F switches it to the integers and back, as on replicants_emlyn.
pub const Demo = @import("replicants_emlyn/app.zig").Demo(true);
