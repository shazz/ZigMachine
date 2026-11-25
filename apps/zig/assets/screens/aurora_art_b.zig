// Aurora boot variant b (cart aurora_boot_b): its own aurora frames and palette (aurora_boot_b/), its sky and star records too (the star detector's band and soft paint-out fix
// are in these, not in cart 161), the sound shared with the main set (aurora_boot/). tools/boot/aurora_bake.py --variant b writes them.
pub const meta = @import("aurora_boot_b/aurora_meta.zig");
pub const sky = @embedFile("aurora_boot_b/sky.zx0");
pub const aurora = @embedFile("aurora_boot_b/aurora.zx0");
pub const aurora_idx = @embedFile("aurora_boot_b/aurora.idx");
pub const stars = @embedFile("aurora_boot_b/stars.zx0");
pub const pcm = @embedFile("aurora_boot/boot.raw");
