// The Aurora boot's baked data (tools/boot/aurora_bake.py writes every file beside this one).
pub const meta = @import("aurora_meta.zig");
pub const sky = @embedFile("sky.zx0"); // the 565 base picture, ZX0
pub const aurora = @embedFile("aurora.zx0"); // per-frame delta containers back to back
pub const aurora_idx = @embedFile("aurora.idx"); // their u32 LE offsets (AURORA_FRAMES + 1)
pub const stars = @embedFile("stars.zx0"); // the star plane's i16 delta records, ZX0
pub const pcm = @embedFile("boot.raw"); // signed 8-bit mono, meta.SAMPLE_RATE Hz
