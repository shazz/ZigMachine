// Aurora boot variant c (cart aurora_boot_c): its own aurora frames and palette (aurora_boot_c/), its sky and star records too (the star detector's band and soft paint-out fix
// are in these, not in cart 161), the sound shared with the main set (aurora_boot/). tools/boot/aurora_bake.py --variant c writes them.
pub const meta = @import("aurora_boot_c/aurora_meta.zig");
pub const sky = @embedFile("aurora_boot_c/sky.zx0");
pub const aurora = @embedFile("aurora_boot_c/aurora.zx0");
pub const aurora_idx = @embedFile("aurora_boot_c/aurora.idx");
pub const stars = @embedFile("aurora_boot_c/stars.zx0");
pub const pcm = @embedFile("aurora_boot/boot.raw");
