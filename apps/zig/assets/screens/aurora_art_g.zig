// Aurora boot variant g (cart aurora_boot_g): its own aurora, sky and baked star plane (aurora_boot_g/), the sound shared with
// the main set (aurora_boot/). tools/boot/aurora_bake.py --variant g writes them. G keeps no star records: overlay.bin is the
// star plane's changes per 60 Hz frame (aurora_overlay.py), aurora.msk the aurora's change masks (aurora_mask.py).
pub const meta = @import("aurora_boot_g/aurora_meta.zig");
pub const sky = @embedFile("aurora_boot_g/sky.zx0");
pub const aurora = @embedFile("aurora_boot_g/aurora.msk");
pub const aurora_idx = @embedFile("aurora_boot_g/aurora.idx");
pub const overlay = @embedFile("aurora_boot_g/overlay.bin");
pub const pcm = @embedFile("aurora_boot/boot.raw");
pub const word = @embedFile("aurora_boot_g/word.bin"); // the baked script name (tools/boot/aurora_word.py)
