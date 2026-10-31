// --------------------------------------------------------------------------
// KOS, the KESTREL Operating System: the boot side of the ROM (docs/ZIGTOS_BOOT.md,
// where "ZigTOS" is the same thing).
//
// What lives here is what every host shares: the POST screen (machine/boot.zig's
// look, drawn by the ROM instead of by each cart) and the system variables block
// (§5). The STAGES (power-on, POST, drive A, the boot sector, the cart or the
// desktop) are driven by the host that instantiates the modules: the browser's
// docs/sealed-loader.js, the native host's fpga/host/kos_host.c, the board
// firmware's fpga/cycles/bkos.c. Only a host can instantiate a cart, so the
// sequencing cannot live in a wasm module; the pixels and the variables do, so
// all three draw and report the same bytes.
//
// Every export is appended to the ROM's ABI (fpga/cycles/sys_abi.txt minor bump):
// a cart built before KOS never calls one and keeps running.
// --------------------------------------------------------------------------
const Post = @import("boot_rom").Boot;

/// KOS 1.0, major << 16 | minor: the ROM's version (sysvars.kos_version).
pub const VERSION: u32 = 0x0001_0000;
pub const VERSION_TEXT = "KOS 1.0";
/// "KOSV" in memory order: the block is the system variables, LAYOUT names its fields.
pub const SYSVARS_MAGIC: u32 = 0x5653_4F4B;
pub const SYSVARS_LAYOUT: u32 = 1;
/// The POST's length when the host passes 0: the 3 s the cart-side boot screen played
/// (apps/zig/demo_main.zig BOOT_FRAMES), long enough for its memory test to complete.
pub const POST_FRAMES: u32 = 180;

pub const BOOT_COLD: u32 = 0;
pub const BOOT_WARM: u32 = 1;
/// What booted (sysvars.boot_dev): the desktop (a data disk or an empty drive), the
/// disk in drive A (its cart), or the cartridge slot (v2).
pub const DEV_DESKTOP: u32 = 0;
pub const DEV_DRIVE_A: u32 = 1;
pub const DEV_CARTRIDGE: u32 = 2;
/// sysvars.drive_a: bit 0 = a disk is in, bits 31:8 = media changes since power-on.
pub const DRIVE_PRESENT: u32 = 1;
pub const DRIVE_CHANGES_SHIFT: u5 = 8;

/// The system variables (TOS's _bootdev, memvalid, _frclock ...), at a fixed place in
/// the ROM's RAM window for as long as rom.wasm is instantiated (a power-on). Every field
/// is a u32 so the block reads the same from Zig, C, Rust and JS.
pub const SysVars = extern struct {
    magic: u32 = SYSVARS_MAGIC,
    layout: u32 = SYSVARS_LAYOUT,
    kos_version: u32 = VERSION,
    boot_kind: u32 = BOOT_COLD,
    boot_dev: u32 = DEV_DESKTOP,
    ram_total: u32 = 0, // bytes of the machine's memory (the 7 MiB shared memory)
    ram_free: u32 = 0, // the cart window's free bytes when the POST counted them (the host's hwRamFree)
    frames: u32 = 0, // frames since the last reset (the ST's _frclock)
    drive_a: u32 = 0, // DRIVE_PRESENT | changes << DRIVE_CHANGES_SHIFT
    cart_slot: u32 = 0, // v2: the cartridge slot, the same encoding; always empty in v1
};

var vars: SysVars = .{};
var post: Post = .{};
var post_frames: u32 = POST_FRAMES;
var post_n: u32 = 0;

export fn kosSysVarsPtr() u32 {
    return @intCast(@intFromPtr(&vars));
}

export fn kosSysVarsBytes() u32 {
    return @sizeOf(SysVars);
}

/// A reset (stage 1): what kind, what is about to boot, whether drive A holds a disk.
/// The frame counter restarts; the media-change count survives (it counts since power-on).
export fn kosSetBoot(kind: u32, dev: u32, drive_present: u32, ram_free: u32) void {
    vars.boot_kind = kind;
    vars.boot_dev = dev;
    vars.ram_total = @as(u32, @wasmMemorySize(0)) * 65536;
    vars.ram_free = ram_free;
    vars.frames = 0;
    vars.drive_a = (vars.drive_a & ~DRIVE_PRESENT) | @intFromBool(drive_present != 0);
}

/// A disk went in (present 1) or came out (0) while a program runs (§4.1).
export fn kosMediaChange(present: u32) void {
    const changes = (vars.drive_a >> DRIVE_CHANGES_SHIFT) +% 1;
    vars.drive_a = (changes << DRIVE_CHANGES_SHIFT) | @intFromBool(present != 0);
}

/// Once a frame, by the host, whatever runs.
export fn kosTick() void {
    vars.frames +%= 1;
}

/// How many POST frames this reset shows, the host having `asked` for that many (0: none): none
/// after a WARM reset (kosSetBoot), as TOS sizes and tests memory only when memvalid fails (Matt,
/// 26 Oct): a warm reset goes straight to the boot stages. One rule for every host.
export fn kosPostFrames(asked: u32) u32 {
    return if (vars.boot_kind == BOOT_WARM) 0 else asked;
}

/// Stage 4: the POST screen on plane 0, for `frames` frames (0 = POST_FRAMES). The host
/// shows plane 0 only, and stops early when a key is held or the POST is switched off.
export fn kosPostStart(frames: u32) void {
    post.init();
    post_frames = if (frames == 0) POST_FRAMES else frames;
    post_n = 0;
}

/// One POST frame drawn; 1 once the last one is (the host then boots drive A).
export fn kosPostFrame() u32 {
    const ram = post.counter_ram;
    const boot = post.counter_boot;
    post.update();
    if (post_n == 0) {
        post.render();
        post.text(VERSION_TEXT, VERSION_X, VERSION_Y, BLACK, WHITE);
    } else changed(ram, boot);
    post_n += 1;
    return @intFromBool(post_n >= post_frames);
}

/// What Boot.render() would change this frame, and only that. render() redraws the logo and
/// every line byte by byte each frame, which held the board's POST under 60 fps (38.8); plane 0
/// keeps the last frame's pixels, so the next dash of the memory bar, the RAM total and the next
/// cell of the boot bar are all that move. The picture is render()'s, frame for frame.
fn changed(ram: u16, boot: u16) void {
    const bar_y = POST_TOP + 10;
    if (post.counter_ram != ram) {
        post.text("-", BAR_X + (post.counter_ram - 1) * 8, bar_y, WHITE, BLACK);
        if (post.counter_ram == 16) {
            post.text("  2048 KB", 8 + 19 * 8, bar_y, WHITE, BLACK);
            post.text("Memory Test Complete.", 8, POST_TOP + 20, BLACK, WHITE);
        }
    }
    if (post.counter_boot != boot) post.text(" ", 8 + (post.counter_boot - 1) * 8, POST_TOP + 30, WHITE, BLACK);
}

// machine/boot.zig's layout: its palette's white and black, the text block's top, the bar's left.
const WHITE: u8 = 7;
const BLACK: u8 = 0;
const POST_TOP: u16 = 74;
const BAR_X: u16 = 8 + 12 * 8;

// Right of the logo (65x60 at 20,10), on its middle row: black on the POST's white.
const VERSION_X: u16 = 104;
const VERSION_Y: u16 = 36;

