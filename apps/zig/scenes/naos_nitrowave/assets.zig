// --------------------------------------------------------------------------
// The programs as the disk holds them, ZX0-packed (build.zig: packed_assets.
// naos_nitrowave), each depacked into the ONE part memory (st.Ram, 512 KB from
// the cart arena) at the address it runs from, when its part is entered:
//   menu  MENU.PRG's TEXT+DATA (252,016 bytes), relocated to 0
//   bspr  B_SPRITE.BIN (95,078 bytes) at $800, where the menu's loader puts it
//   dam   DAMIER3D.BIN's memory at its main loop's first stop, $400..$7A000:
//         the file after its own set-up ran (dam.zig says why)
// --------------------------------------------------------------------------
const zg = @import("zigos");
const zx0 = @import("depackers").zx0;
const PACKED = @import("packed_assets").naos_nitrowave;
const st = @import("st.zig");

pub const Set = enum { menu, bspr, dam };

const Blob = struct { src: []const u8, at: u32, len: usize };

fn blob(set: Set) Blob {
    return switch (set) {
        .menu => .{ .src = PACKED.menu, .at = 0, .len = 252016 },
        .bspr => .{ .src = PACKED.bspr, .at = 0x800, .len = 95078 },
        .dam => .{ .src = PACKED.dam, .at = 0x400, .len = 0x79C00 },
    };
}

var ram_bytes: []u8 = &.{};

/// The part memory, taken once per cart load (zeroed by the arena).
pub fn ram() st.Ram {
    if (ram_bytes.len == 0) ram_bytes = zg.mem.mustAlloc(u8, st.RAM_LEN);
    return .{ .m = ram_bytes };
}

/// Clear the part memory and depack `set` into it. False if the blob does not
/// depack to its size: a build fault, never expected at run time.
pub fn load(r: *const st.Ram, set: Set) bool {
    @memset(r.m, 0);
    const b = blob(set);
    const n = zx0.depack(b.src, r.m[b.at..][0..b.len]) orelse return false;
    return n == b.len;
}
