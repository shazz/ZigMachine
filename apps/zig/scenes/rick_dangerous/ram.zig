// --------------------------------------------------------------------------
// The game's memory: the ST's first 512 KB, so every transcribed routine uses
// the 68000's own absolute addresses (the reference model's state.py keeps a
// 1 MB image; nothing the game touches lies above $80000: the two screens end
// there).
//
//   $0AAA0-$41C57  image.bin, cut from the entry RAM by
//                  tools/rick_dangerous/extract_assets.py: tiles, maps,
//                  sprites, title, banners, the tables and the variables at
//                  their entry values, the sound driver and the digis
//   $63800-$6FFFF  the work buffers ($65B00 the erase source, $66010 the
//                  clean playfield copy); $70000 / $78000 the two screens
//
// Values are i64, the model's unbounded Python ints: the writes mask to their
// size as the model's put() does, and the transcriptions mask where the model
// masks. An access outside the 512 KB is counted (oob) and checked 0 by the
// headless harness: the model would have read the entry image there.
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const MEM_LEN: usize = 0x80000;
pub const IMAGE_AT: usize = 0xAAA0;
const IMAGE = @embedFile("../../assets/screens/rick_dangerous/image.bin");

/// From the cart RAM arena, once per cart load (alloc()).
pub var mem: []u8 = &.{};
/// Accesses outside the 512 KB.
pub var oob: u32 = 0;

pub fn alloc() void {
    if (mem.len == 0) mem = zg.mem.mustAlloc(u8, MEM_LEN)[0..MEM_LEN];
}

/// The entry image: zero everywhere, the extracted data at $AAA0.
pub fn loadImage() void {
    @memset(mem, 0);
    @memcpy(mem[IMAGE_AT..][0..IMAGE.len], IMAGE);
    oob = 0;
}

inline fn at(a: i64) ?usize {
    if (a < 0 or a >= MEM_LEN) {
        oob += 1;
        return null;
    }
    return @intCast(a);
}

pub fn rb(a: i64) i64 {
    const i = at(a) orelse return 0;
    return mem[i];
}
pub fn rw(a: i64) i64 {
    return (rb(a) << 8) | rb(a + 1);
}
pub fn rl(a: i64) i64 {
    return (rw(a) << 16) | rw(a + 2);
}
/// A word read signed.
pub fn sw(a: i64) i64 {
    return s16(rw(a));
}
pub fn wb(a: i64, v: i64) void {
    const i = at(a) orelse return;
    mem[i] = @truncate(@as(u64, @bitCast(v)));
}
pub fn ww(a: i64, v: i64) void {
    wb(a, v >> 8);
    wb(a + 1, v);
}
pub fn wl(a: i64, v: i64) void {
    ww(a, v >> 16);
    ww(a + 2, v);
}

/// n bytes from src to dst (the model's slice assignment; the ranges never overlap).
pub fn copy(dst: i64, src: i64, n: i64) void {
    const d = at(dst) orelse return;
    const s = at(src) orelse return;
    const len: usize = @intCast(n);
    if (d + len > MEM_LEN or s + len > MEM_LEN) {
        oob += 1;
        return;
    }
    @memcpy(mem[d..][0..len], mem[s..][0..len]);
}

pub fn zero(dst: i64, n: i64) void {
    const d = at(dst) orelse return;
    const len: usize = @intCast(n);
    if (d + len > MEM_LEN) {
        oob += 1;
        return;
    }
    @memset(mem[d..][0..len], 0);
}

pub fn s8(v: i64) i64 {
    const b = v & 0xFF;
    return if (b & 0x80 != 0) b - 0x100 else b;
}
pub fn s16(v: i64) i64 {
    const w = v & 0xFFFF;
    return if (w & 0x8000 != 0) w - 0x10000 else w;
}
pub fn s32(v: i64) i64 {
    const l = v & 0xFFFFFFFF;
    return if (l & 0x80000000 != 0) l - 0x100000000 else l;
}
/// (An, Dn.w): An + the sign-extended word, on the 24-bit bus.
pub fn idx(base: i64, d: i64) i64 {
    return (base + s16(d)) & 0xFFFFFF;
}
