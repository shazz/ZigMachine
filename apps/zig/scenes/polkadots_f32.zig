// POLKA DOTS F32: the same halftone torus bench as polkadots.zig, booting with
// its maths on the CODEF port's own algorithm in f32 (the FPU test cart:
// hardware float on a ZM_FPU=1 board, soft-float elsewhere). F switches it to
// the integers and back, as on polkadots.
pub const Demo = @import("polkadots/app.zig").Demo(true);
