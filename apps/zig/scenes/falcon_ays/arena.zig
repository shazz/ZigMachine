// --------------------------------------------------------------------------
// The parts' big tables (fields, textures, maps, pictures: ~1.1 MB) come from the cart RAM
// arena at init (zg.mem), not from zero-filled statics: those would sit in the wasm data
// section as zeros (docs/MEMORY.md; the zero_segments gate refuses runs over 64 KB).
// --------------------------------------------------------------------------
const zg = @import("zigos");

/// A T from the arena, for the whole run. The parts cannot run without their tables, and the
/// cart's window holds them with ~1.5 MB to spare, so a refusal is a build error in spirit.
pub fn take(comptime T: type) *T {
    const words = zg.mem.alloc(u32, (@sizeOf(T) + 3) / 4) orelse @panic("falcon_ays: cart RAM arena exhausted");
    return @ptrCast(@alignCast(words.ptr));
}
