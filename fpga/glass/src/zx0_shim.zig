// The test build's `zx0`: the machine's depacker as zx0_pack.zig carries it,
// plus the packer, so tests can pack what the loader unpacks (build.zig says why).
const pack_mod = @import("zx0_pack");

pub const depack = pack_mod.zx0.depack;
pub const depackedLen = pack_mod.zx0.depackedLen;
pub const isPacked = pack_mod.zx0.isPacked;
pub const pack = pack_mod.pack;
