// The Aurora boot variant H's baked data (tools/boot/aurora_bake.py --full writes every file beside this one).
// aurora.msk is NOT embedded: at 400x280 it is ~3 MB, so it rides on the floppy as AURORA.MSK (tools/mkdisks.sh)
// and the cart reads it a container at a time (apps/zig/scenes/aurora_boot_h/stream.zig).
pub const meta = @import("aurora_meta.zig");
pub const sky = @embedFile("sky.zx0"); // the 565 base picture, 400x280, ZX0
pub const aurora_idx = @embedFile("aurora.idx"); // AURORA.MSK's container offsets, u32 LE (2 * AURORA_FRAMES + 1)
pub const overlay = @embedFile("overlay.bin"); // the star plane's changed bytes per 60 Hz frame, two 64 K sections
pub const pcm = @embedFile("boot.raw"); // signed 8-bit mono, meta.SAMPLE_RATE Hz
