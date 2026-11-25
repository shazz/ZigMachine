// Aurora boot variant f (cart aurora_boot_f): its own aurora frames and palette (aurora_boot_f/), its sky and star records too (the star detector's band and soft paint-out fix
// are in these, not in cart 161), the sound shared with the main set (aurora_boot/). tools/boot/aurora_bake.py --variant f writes them.
pub const meta = @import("aurora_boot_f/aurora_meta.zig");
pub const sky = @embedFile("aurora_boot_f/sky.zx0");
pub const aurora = @embedFile("aurora_boot_f/aurora.zx0");
pub const aurora_idx = @embedFile("aurora_boot_f/aurora.idx");
pub const stars = @embedFile("aurora_boot_f/stars.zx0");
pub const pcm = @embedFile("aurora_boot/boot.raw");
pub const palette = @embedFile("aurora_boot_f/palette.bin"); // BAND_ROWS x 256 u16 LE, one table per stored row
pub const word = @embedFile("aurora_boot_f/word.bin"); // the baked script name (tools/boot/aurora_word.py)
