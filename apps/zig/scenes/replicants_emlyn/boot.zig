// --------------------------------------------------------------------------
// REPLICANTS / EMLYN HUGHES — the disk's executable BOOT SECTOR (ZigCart v2).
// --------------------------------------------------------------------------
// The note the cracking crew used to leave in the boot sector, saying what the
// keys do before the screen comes up. Screen-specific: it talks about THIS
// intro's SPACE key, so it lives with the scene, not in apps/zig/boot/.
//
// A bare wasm boot program, exactly like apps/zig/boot/novirus.zig: NO ZigOS,
// NO ROM — it pokes the sealed video ABI directly and must fit the 1 KB sector.
// The host runs it through the normal render loop and chainloads the disk's
// cart when pollCartRequest() returns 2.
//
// SIZE BUDGET: mkdisk.py takes at most 1015 B of wasm (1 KB sector minus the 9 B
// `zmck` checksum section). This build lands at 1011 B — FOUR bytes of headroom,
// nearly all of it the font (26 glyphs x 7 B) and MSG itself. Adding a word to
// the note means taking one out somewhere else; do not grow the sector.
// --------------------------------------------------------------------------
const hw = @import("hardware"); // sealed video ABI header (offsets only, no code)

extern fn hwVideoBase() i32;

const HOLD_FRAMES: u32 = 240; // ~4 s at 60 fps — long enough to read it
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

// 8x8 uppercase, 7 rows drawn (row 8 is the gap). Bit 7 = leftmost pixel.
// A..Z in order: a glyph index is c - 'A'. A space draws nothing at all.
const GLYPHS = [_][7]u8{
    .{ 0x38, 0x6C, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6 }, // A
    .{ 0xFC, 0xC6, 0xFC, 0xC6, 0xC6, 0xC6, 0xFC }, // B
    .{ 0x3C, 0x66, 0xC0, 0xC0, 0xC0, 0x66, 0x3C }, // C
    .{ 0xF8, 0xCC, 0xC6, 0xC6, 0xC6, 0xCC, 0xF8 }, // D
    .{ 0xFE, 0xC0, 0xC0, 0xFC, 0xC0, 0xC0, 0xFE }, // E
    .{ 0xFE, 0xC0, 0xC0, 0xFC, 0xC0, 0xC0, 0xC0 }, // F
    .{ 0x3C, 0x66, 0xC0, 0xCE, 0xC6, 0x66, 0x3E }, // G
    .{ 0xC6, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6 }, // H
    .{ 0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7E }, // I
    .{ 0x1E, 0x06, 0x06, 0x06, 0xC6, 0xC6, 0x7C }, // J
    .{ 0xC6, 0xCC, 0xD8, 0xF0, 0xD8, 0xCC, 0xC6 }, // K
    .{ 0xC0, 0xC0, 0xC0, 0xC0, 0xC0, 0xC0, 0xFE }, // L
    .{ 0xC6, 0xEE, 0xFE, 0xD6, 0xC6, 0xC6, 0xC6 }, // M
    .{ 0xC6, 0xE6, 0xF6, 0xDE, 0xCE, 0xC6, 0xC6 }, // N
    .{ 0x38, 0x6C, 0xC6, 0xC6, 0xC6, 0x6C, 0x38 }, // O
    .{ 0xFC, 0xC6, 0xC6, 0xFC, 0xC0, 0xC0, 0xC0 }, // P
    .{ 0x38, 0x6C, 0xC6, 0xC6, 0xD6, 0x6C, 0x3A }, // Q
    .{ 0xFC, 0xC6, 0xC6, 0xFC, 0xD8, 0xCC, 0xC6 }, // R
    .{ 0x7C, 0xC6, 0xC0, 0x7C, 0x06, 0xC6, 0x7C }, // S
    .{ 0xFF, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18 }, // T
    .{ 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C }, // U
    .{ 0xC6, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x10 }, // V
    .{ 0xC6, 0xC6, 0xC6, 0xD6, 0xFE, 0xEE, 0xC6 }, // W
    .{ 0xC6, 0x6C, 0x38, 0x38, 0x6C, 0xC6, 0xC6 }, // X
    .{ 0xC6, 0xC6, 0x6C, 0x38, 0x18, 0x18, 0x18 }, // Y
    .{ 0xFE, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0xFE }, // Z
};

// The note itself. '|' ends a line (an empty line is a blank row of text).
// Letters and spaces only: the font carries no digits or punctuation.
const MSG =
    "REPLICANTS|" ++
    "EMLYN HUGHES SOCCER||" ++
    "PRESS SPACE FOR ZIG MODE|" ++
    "RASTERS TILT|" ++
    "SCROLLER BENDS||" ++
    "SPACE AGAIN FOR|" ++
    "THE ORIGINAL||" ++
    "ESC GOES BACK|";

const LINE_H: usize = 12; // 8 px of glyph + 4 px of air
// Also the guard on the layout: every line must fit the 40-column screen, and
// the note must end with a '|' — the drawing loop scans for one and would run
// off the end of the string without it.
const N_LINES: usize = blk: {
    var n: usize = 0;
    var w: usize = 0;
    for (MSG) |c| {
        if (c != '|') {
            w += 1;
        } else {
            if (w > W / 8) @compileError("boot note: a line is wider than the screen");
            w = 0;
            n += 1;
        }
    }
    if (w != 0) @compileError("boot note: the last line has no '|'");
    break :blk n;
};

fn drawChar(fb: [*]u8, x: usize, y: usize, c: u8) void {
    if (c < 'A' or c > 'Z') return; // a space: nothing to paint
    const g = GLYPHS[c - 'A'];
    var row: usize = 0;
    while (row < 7) : (row += 1) {
        var bits = g[row];
        var col: usize = 0;
        while (col < 8) : (col += 1) {
            if (bits & 0x80 != 0) fb[(y + row) * W + x + col] = 1; // ink
            bits <<= 1;
        }
    }
}

// One-shot setup: white ground, black text, the way an ST boot-sector note reads.
export fn boot() void {
    frame_count = 0;
    w32(hw.REG_BACKGROUND, 0xFFFFFFFF); // inverse video: white everywhere
    palEntry(0, 0xFFFFFFFF); // paper
    palEntry(1, 0xFF000000); // ink

    const fb = fbPtr();
    @memset(fb[0 .. W * hw.HEIGHT], 0); // paper everywhere (a wasm memory.fill)

    var y: usize = (hw.HEIGHT - N_LINES * LINE_H) / 2;
    var start: usize = 0;
    while (start < MSG.len) {
        var end = start;
        while (MSG[end] != '|') end += 1;
        const x0 = (W - (end - start) * 8) / 2; // centred; every line fits 40 chars
        var c = start;
        while (c < end) : (c += 1) drawChar(fb, x0 + (c - start) * 8, y, MSG[c]);
        y += LINE_H;
        start = end + 1;
    }
}

export fn frame(dt: f32) void {
    _ = dt;
    frame_count +%= 1;
}

export fn isPlaneEnabled(plane: i32) i32 {
    return if (plane == 0) 1 else 0;
}

// The host calls this on a disk boot from the menu or a channel change; there is
// no boot ROM animation to skip here, but the call is unguarded in the loader.
export fn skipBoot() void {}

// The VHS name card waits for the CART to be running (cart-osd.js polls this),
// so the deck prints "REPLICANTS EMLYN" over the intro, not over this note.
export fn isBooted() bool {
    return false;
}

export fn pollCartRequest() i32 {
    return if (frame_count >= HOLD_FRAMES) CHAINLOAD else 0;
}
