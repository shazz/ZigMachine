// --------------------------------------------------------------------------
// The ST under the program: the 50 Hz VBL (STOS's system VBL -- TIMER, the
// fades and FLASH, MOVE / ANIM, the sprite redraw -- then the BASIC side
// until it waits), and the Shifter: the physical screen shown through the 16
// colour registers.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const S = @import("stos.zig");
const scr = @import("scr.zig");
const gfx = @import("gfx.zig");
const text = @import("text.zig");
const blocks = @import("blocks.zig");
const sprite = @import("sprite.zig");
const zone = @import("zone.zig");
const pal = @import("pal.zig");
const move = @import("move.zig");
const input = @import("input.zig");
const sound = @import("sound.zig");
const B = @import("basic.zig");
const flow = @import("flow.zig");
const clock = @import("clock.zig");
const V = @import("vars.zig");

pub var vbls: u64 = 0;

/// Once per cart load: the screens and buffers, the sprite images.
pub fn alloc() void {
    scr.alloc();
    blocks.alloc();
    sprite.load();
    flow.register(&@import("boot.zig").steps);
    flow.register(&@import("title.zig").steps);
    flow.register(&@import("tscreen.zig").steps);
    flow.register(&@import("loop.zig").steps);
    flow.register(&@import("mission.zig").steps);
    flow.register(&@import("endings.zig").steps);
    flow.register(&@import("hiscore.zig").steps);
}

/// Power on: every module as the program finds it.
pub fn reset() void {
    V.v = .{};
    for (0..4) |i| @memset(scr.pix[i], 0);
    scr.pal = [_][16]u16{[_]u16{0} ** 16} ** 4;
    scr.reset();
    gfx.reset();
    text.reset();
    sprite.reset();
    zone.resetAll();
    pal.reset();
    move.reset();
    input.reset();
    sound.reset();
    B.reset();
    flow.reset();
    clock.reset();
    S.timer = 0;
    vbls = 0;
    @import("pass.zig").passes = 0;
    @import("title.zig").budget = 0;
    zone.refused = 0;
}

/// One VBL.
pub fn vbl() void {
    vbls += 1;
    S.timer +%= 1;
    pal.vbl();
    move.vbl();
    sprite.update();
    flow.vbl();
}

/// VBLs until `limit`.
pub fn run(limit: u64) void {
    while (vbls < limit) vbl();
}

/// An ST colour register ($0RGB, three bits a gun) as RGBA.
pub fn stColor(word: u16) u32 {
    const r: u32 = (word >> 8 & 7) * 255 / 7;
    const g: u32 = (word >> 4 & 7) * 255 / 7;
    const b: u32 = (word & 7) * 255 / 7;
    return (0xFF << 24) | (b << 16) | (g << 8) | r;
}

pub fn present(fb: *zg.LogicalFB) void {
    for (0..16) |i| fb.palette[i] = stColor(pal.hw[i]);
    const p = scr.get(.physic);
    if (p.len == 0) return;
    for (0..scr.H) |y| @memcpy(fb.fb[y * fb.stride ..][0..scr.W], p[y * scr.W ..][0..scr.W]);
}
