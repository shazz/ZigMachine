// Aurora boot variant g (cart aurora_boot_g): its own aurora frames and palette (aurora_boot_g/), its sky and star records too (the star detector's band and soft paint-out fix
// are in these, not in cart 161), the sound shared with the main set (aurora_boot/). tools/boot/aurora_bake.py --variant g writes them.
pub const meta = @import("aurora_boot_g/aurora_meta.zig");
pub const sky = @embedFile("aurora_boot_g/sky.zx0");
pub const aurora = @embedFile("aurora_boot_g/aurora.zx0");
pub const aurora_idx = @embedFile("aurora_boot_g/aurora.idx");
pub const stars = @embedFile("aurora_boot_g/stars.zx0");
pub const pcm = @embedFile("aurora_boot/boot.raw");
pub const word = @embedFile("aurora_boot_g/word.bin"); // the baked script name (tools/boot/aurora_word.py)
