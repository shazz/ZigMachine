// --------------------------------------------------------------------------
// "No virus in ZigMachine" — an executable BOOT SECTOR (ZigCart format v2).
// --------------------------------------------------------------------------
// A bare wasm boot program: NO ZigOS, NO ROM — it pokes the sealed video ABI
// directly and stays tiny enough to live in the 1 KB boot sector. The host
// instantiates it (block 0 of a v2 .zmd, when the sector sums to $1234), runs it
// through the normal render loop, and — when pollCartRequest() returns 2 — chain-
// loads the disk's real cart. The ST-antivirus-bootsector homage.
//
// Inverse video: white ground (REG_BACKGROUND) with black text on plane 0.
// TODO(bootsector): add a low YM2149 tone once the boot-audio path exists.
// --------------------------------------------------------------------------
const hw = @import("hardware"); // sealed video ABI header (offsets only, no code)

extern fn hwVideoBase() i32; // the machine tells us where its region lives
extern fn beep() void; // host bridge: a low YM2149 tone (silenced on chainload)

const HOLD_FRAMES: u32 = 120; // ~2 s at 60 fps, then chainload the cart
const CHAINLOAD: i32 = 2; // pollCartRequest() code: "boot this disk's cart"
const W: usize = hw.WIDTH; // 320 (visible plane width)

var frame_count: u32 = 0;

inline fn regBase() usize {
    return @intCast(hwVideoBase());
}
inline fn w32(off: usize, v: u32) void {
    @as(*volatile u32, @ptrFromInt(regBase() + off)).* = v;
}
inline fn r32(off: usize) u32 {
    return @as(*volatile u32, @ptrFromInt(regBase() + off)).*;
}
inline fn fbPtr() [*]u8 {
    return @ptrFromInt(regBase() + @as(usize, r32(hw.REG_FB_BASE))); // plane 0 framebuffer
}
inline fn palEntry(i: usize, rgba: u32) void {
    w32(hw.OFF_PAL + i * 4, rgba);
}

// 8x8 uppercase glyphs — only the letters "NO VIRUS IN ZIGMACHINE" needs. Bit 7 = left.
const GLYPHS = [_][8]u8{
    .{ 0, 0, 0, 0, 0, 0, 0, 0 }, //  (space) 0
    .{ 0x38, 0x6C, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0 }, // A 1
    .{ 0x3C, 0x66, 0xC0, 0xC0, 0xC0, 0x66, 0x3C, 0 }, // C 2
    .{ 0xFE, 0xC0, 0xC0, 0xFC, 0xC0, 0xC0, 0xFE, 0 }, // E 3
    .{ 0x3C, 0x66, 0xC0, 0xCE, 0xC6, 0x66, 0x3C, 0 }, // G 4
    .{ 0xC6, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0 }, // H 5
    .{ 0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7E, 0 }, // I 6
    .{ 0xC6, 0xEE, 0xFE, 0xD6, 0xC6, 0xC6, 0xC6, 0 }, // M 7
    .{ 0xC6, 0xE6, 0xF6, 0xDE, 0xCE, 0xC6, 0xC6, 0 }, // N 8
    .{ 0x38, 0x6C, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0 }, // O 9
    .{ 0xFC, 0xC6, 0xC6, 0xFC, 0xD8, 0xCC, 0xC6, 0 }, // R 10
    .{ 0x7C, 0xC6, 0xC0, 0x7C, 0x06, 0xC6, 0x7C, 0 }, // S 11
    .{ 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0 }, // U 12
    .{ 0xC6, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x10, 0 }, // V 13
    .{ 0xFE, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0xFE, 0 }, // Z 14
};

fn glyphIndex(c: u8) usize {
    return switch (c) {
        'A' => 1, 'C' => 2, 'E' => 3, 'G' => 4, 'H' => 5, 'I' => 6, 'M' => 7,
        'N' => 8, 'O' => 9, 'R' => 10, 'S' => 11, 'U' => 12, 'V' => 13, 'Z' => 14,
        else => 0, // space / unknown
    };
}

const MSG = "NO VIRUS IN ZIGMACHINE"; // 22 chars -> 176 px wide

fn drawChar(fb: [*]u8, x: usize, y: usize, gi: usize) void {
    const g = GLYPHS[gi];
    var row: usize = 0;
    while (row < 8) : (row += 1) {
        var col: usize = 0;
        while (col < 8) : (col += 1) {
            if ((g[row] >> @intCast(7 - col)) & 1 != 0) fb[(y + row) * W + (x + col)] = 1; // black ink
        }
    }
}

// One-shot setup: white ground + black message on plane 0 (inverse video).
export fn boot() void {
    frame_count = 0;
    w32(hw.REG_BACKGROUND, 0xFFFFFFFF); // inverse video: white everywhere (borders + visible)
    // The compositor writes every plane pixel (no alpha skip), so paint the plane's
    // ground white too (not transparent) — it then matches the white border.
    palEntry(0, 0xFFFFFFFF); // plane index 0 = opaque white (paper)
    palEntry(1, 0xFF000000); // plane index 1 = opaque black (ink) -> inverse video

    const fb = fbPtr();
    var i: usize = 0;
    while (i < W * hw.HEIGHT) : (i += 1) fb[i] = 0; // clear the plane to transparent

    const x0: usize = (W - MSG.len * 8) / 2; // centre horizontally
    const y0: usize = (hw.HEIGHT - 8) / 2; // centre vertically
    var c: usize = 0;
    while (c < MSG.len) : (c += 1) drawChar(fb, x0 + c * 8, y0, glyphIndex(MSG[c]));

    beep(); // low YM2149 tone for the hold (host silences it on chainload)
}

export fn frame(dt: f32) void {
    _ = dt;
    frame_count +%= 1;
}

export fn isPlaneEnabled(plane: i32) i32 {
    return if (plane == 0) 1 else 0; // only the text plane
}

export fn pollCartRequest() i32 {
    return if (frame_count >= HOLD_FRAMES) CHAINLOAD else 0;
}
