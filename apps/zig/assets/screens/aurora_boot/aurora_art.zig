// The Aurora boot's baked data (tools/boot/aurora_bake.py writes every file beside this one).
pub const meta = @import("aurora_meta.zig");
pub const sky = @embedFile("sky.zx0"); // the 565 base picture, ZX0
pub const aurora = @embedFile("aurora.msk"); // per 60 Hz half-frame: change mask + nibble codes (aurora_mask.py), back to back
pub const aurora_idx = @embedFile("aurora.idx"); // their u32 LE offsets (2 * AURORA_FRAMES + 1)
pub const overlay = @embedFile("overlay.bin"); // the star plane's changed bytes per 60 Hz frame (aurora_overlay.py)
pub const pcm = @embedFile("boot.raw"); // signed 8-bit mono, meta.SAMPLE_RATE Hz
