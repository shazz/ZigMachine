// --------------------------------------------------------------------------
// demo.wasm entry point (OPEN — the coder's binary).
//
// ZigOS + effects + the selected scene, compiled against sdk/hardware.zig. Runs
// on the main thread sharing ONE WebAssembly.Memory with the sealed
// machine-video.wasm. It writes framebuffers/palettes/registers into the shared
// video region and never touches machine source.
//
// Per-frame host loop:
//   machine.hwClear()  ->  demo.frame(dt)  ->  machine.hwRenderPlane(i) per
//   enabled plane  ->  host blits PFB to canvas[i].
// The machine calls back into demo.hblDispatch() at each HBL point.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos"); // the open ZigOS library (named module)
const ZigOS = zg.ZigOS;
const Console = zg.Console;
// The cart is the menu launcher (demo.wasm) or one scene (demo-<tag>.wasm),
// selected at build time. `cart.zig` (rooted in apps/zig/ so scene @embedFiles
// resolve) picks the scene and exposes it uniformly as `Cart`.
const Cart = @import("cart").Cart;
const BootRom = @import("boot_rom").Boot; // the machine boot ROM (POST screen), HW-ABI only

var want_menu: bool = false; // a scene cart asked to return to the menu
var g_no_tag = [_]u8{0};

const VERSION = "0.2-sealed";

// The ZigMachine boot screen plays for this many frames before the RAM cart is
// inserted (~3s at 60fps). With the boot effect's RAM_STEP=3 slowdown the
// memory-test sequence completes around frame ~153; the rest is a short hold.
const BOOT_FRAMES: u32 = 180;

const Direction = enum(u8) { Up = 0, Down = 1, Left = 2, Right = 3, Null = 4, Fire = 5, Back = 6 };

var zigos: ZigOS = undefined;
var cart: Cart = undefined;
var boot_rom: BootRom = undefined;
var booted: bool = false; // false = boot screen showing; true = cart running
var boot_frames: u32 = 0;

// --------------------------------------------------------------------------
// Boot: ZigOS discovers the machine's video base and sets up its views, then
// the scene initialises its planes/palettes.
// --------------------------------------------------------------------------
export fn boot() void {
    Console.log("ZigMachine demo v.{s}\n", .{VERSION});
    zigos.init();
    boot_rom.init(); // machine boot ROM (POST screen) — HW-ABI only; cart inserted after it
}

// Reset the machine to a clean state and insert & start the selected RAM cart.
fn startCart() void {
    if (booted) return;
    zigos.resetForScene(); // clean machine state (planes/palette/registers/HBL) for the cart
    cart.init(&zigos);
    booted = true;
}

// Compute one frame. While booting, draw the boot screen; when it's done, start
// the selected RAM cart. ESC (see skipBoot) ends the boot screen early.
export fn frame(elapsed_time: f32) void {
    if (!booted) {
        boot_rom.update();
        boot_rom.render();
        boot_frames += 1;
        if (boot_frames >= BOOT_FRAMES) startCart();
        return;
    }
    cart.update(&zigos, elapsed_time);
    cart.render(&zigos, elapsed_time);
}

// Has the RAM cart been inserted and started? The host needs an HONEST readiness
// signal before it hands the cart anything (the FAT listing, say). It used to
// infer this from a scene's sample buffer, which broke the moment that scene
// stopped needing one.
export fn isBooted() bool {
    return booted;
}

// Does the running cart OWN the keyboard?
//
// The host has its own shortcuts — Escape returns to the menu, Space/Enter is
// Fire, WASD and the arrows are movement, 1-7 switch shading. Those are for a
// DEMO scene the viewer is navigating. A GEM-style application is the opposite:
// every key is its own, and a host that quietly keeps Escape means the app can
// never bind it (ST Replay's Esc = stop rebooted the machine instead).
//
// So a cart may declare `ownsKeyboard`, and the host then forwards keys instead
// of interpreting them. Always 0 while the boot ROM is up, so Escape still skips
// the boot screen. Old carts do not declare it and keep the old behaviour.
export fn ownsKeyboard() u32 {
    if (!booted) return 0;
    if (@hasDecl(Cart, "ownsKeyboard")) return cart.ownsKeyboard();
    return 0;
}

// Skip the boot screen (ESC in the loader): jump straight to the RAM cart.
export fn skipBoot() void {
    startCart();
}

// The sealed machine routes each HBL point here (integer ids only).
export fn hblDispatch(id: u32, plane: u32, line: u32, x: u32) void {
    zigos.dispatchHBL(id, plane, line, x);
}

// The host gates blits on this (the machine renders a plane unconditionally).
export fn isPlaneEnabled(id: u8) bool {
    if (!booted) return id == 0; // boot ROM draws on plane 0 only
    return zigos.lfbs[id].is_enabled;
}

// Optional per-scene shading/mode switch (keys 1-4 in sealed-loader.js). Only
// scenes that declare setShadeMode react; others ignore it (compile-time guard).
// Returns whether the running scene consumed the mode switch. The host falls
// back to its audio shortcuts (keys 1/2/3 = MOD/YM/sample) when it didn't.
export fn setShadeMode(mode: u32) bool {
    if (booted and @hasDecl(Cart, "setShadeMode")) {
        cart.setShadeMode(mode);
        return true;
    }
    return false;
}

// Pointer state from the host (mouse over the canvas), in 320x200 visible coords.
// Only scenes that declare pointer() react (e.g. the GEM windowing app).
export fn pointer(x: i32, y: i32, buttons: u32) void {
    if (booted and @hasDecl(Cart, "pointer")) cart.pointer(x, y, buttons);
}

// The host reports whether an app-disk is inserted (e.g. GEM booted for the ST
// Replay data disk) and fills the FAT listing shown in GEM's FLOPPY window.
export fn insertDisk(present: u32) void {
    if (booted and @hasDecl(Cart, "insertDisk")) cart.insertDisk(present);
}
export fn diskDirPtr() [*]u8 {
    if (booted and @hasDecl(Cart, "diskDirPtr")) return cart.diskDirPtr();
    return &g_no_tag;
}
export fn setDiskFileCount(n: u32) void {
    if (booted and @hasDecl(Cart, "setDiskFileCount")) cart.setDiskFileCount(n);
}

// Sample-buffer bridge: a scene (e.g. ST Replay) that declares sampleBuf() lets
// the host copy a real sample into it for display. Scenes without it report len 0.
var g_no_sample: [1]u8 = .{0};
export fn getSampleBufPtr() [*]u8 {
    if (booted and @hasDecl(Cart, "sampleBuf")) return cart.sampleBuf();
    return &g_no_sample;
}
// How many bytes the loaded sample really is; the display buffer above is only a
// downsampled view of it, so the app cannot infer the count from its own length.
export fn setSampleBytes(n: u32, hz: u32) void {
    if (booted and @hasDecl(Cart, "setSampleBytes")) cart.setSampleBytes(n, hz);
}
export fn getSampleBufLen() u32 {
    if (booted and @hasDecl(Cart, "sampleBuf")) return @intCast(Cart.sampleLen());
    return 0;
}

// Song-request bridge (by NAME — the host holds no playlists). A scene calls
// zigos.requestSong("<file under docs/music/>"); the host polls this each frame
// (1 = a new request is pending), reads the filename from songName*, and plays
// it by extension. (Union main autoplays its first track + switches on keys 1-6;
// Music Debug maps keys 1/2/3 — both via setShadeMode → zigos.requestSong.)
export fn pollSongRequest() u32 {
    return if (booted and zg.takeSongRequest()) 1 else 0;
}
export fn songNamePtr() [*]u8 {
    return zg.songNamePtr();
}
export fn songNameLen() u32 {
    return @intCast(zg.songNameLen());
}
// Which subtune of a multi-song image to start; counts from 1, 0 = the image's
// own default. Read by the host alongside the name.
export fn songTune() u32 {
    return zg.songTune();
}

// Directional / action input from the host. Forwarded to scenes that declare
// input() (e.g. the effects menu: arrows move, Fire launches, Back returns).
export fn input(dir: Direction) void {
    if (booted and @hasDecl(Cart, "input")) cart.input(@intFromEnum(dir));
    // A scene cart (no launcher) returns to the menu on Back (joystick/Back key).
    if (dir == .Back and !@hasDecl(Cart, "pollCart")) want_menu = true;
}

// Character keyboard input (printable + 8=Backspace, 13=Enter). For text entry
// like GEM rename. Forwarded to scenes that declare key() (e.g. the desktop).
// The ST keyboard's ESCAPE. The host FORWARDS it like any other key and no longer
// decides what it means — it used to eat Escape for "back to the menu", so a
// screen could never bind it (ST Replay's Esc = stop rebooted the machine).
const K_ESC: u32 = 0xE012;

export fn key(cp: u32) void {
    // The boot ROM's own way out, while it is the thing on screen.
    if (!booted) {
        if (cp == K_ESC) skipBoot();
        return;
    }
    // A screen that handles keys owns EVERY key, Escape included. It decides how
    // (and whether) to leave — see gem_desktop.zig / st_replay.zig.
    if (@hasDecl(Cart, "key")) return cart.key(cp);
    // A screen that handles no keys at all still needs a way out, and for a plain
    // scene cart that is the menu it was launched from. A launcher cart (one with
    // pollCart) has nowhere to go back TO, so Escape does nothing there.
    if (cp == K_ESC and !@hasDecl(Cart, "pollCart")) want_menu = true;
}

// Cartridge swap. The host polls this each frame and, on a request, swaps the
// demo module over the shared memory (see sealed-loader.js).
//   1  = load the tag from getCartTag* as a scene DISK (demo-<tag>.zmd)
//   2  = chainload this disk's cart (format v2 boot sector, host-side)
//   3  = RUN A PROGRAM off the mounted disk: getCartTag* is a FILENAME in its
//        FAT. This is GEM launching an app the way TOS does — the program is a
//        file on the floppy, not something linked into the desktop.
//   4  = return to the OS: reload the system disk's desktop, disk still mounted.
//        An app quitting goes here, NOT to -1: it was launched from GEM and GEM
//        is where it belongs. -1 would drop the user at the menu instead.
//  -1  = load the menu disk
//   0  = no request
export fn pollCartRequest() i32 {
    if (!booted) return 0;
    if (@hasDecl(Cart, "pollCart")) return cart.pollCart(); // menu launcher
    if (want_menu) {
        want_menu = false;
        return -1;
    }
    if (@hasField(Cart, "wants_quit") and cart.wants_quit) return -1;
    return 0;
}
// The scene tag the launcher wants booted (host maps tag -> demo-<tag>.zmd).
export fn getCartTagPtr() [*]const u8 {
    if (booted and @hasDecl(Cart, "cartTag")) return cart.cartTag().ptr;
    return &g_no_tag;
}
export fn getCartTagLen() u32 {
    if (booted and @hasDecl(Cart, "cartTag")) return @intCast(cart.cartTag().len);
    return 0;
}

// --------------------------------------------------------------------------
// Audio mirror surface — JS copies the audio thread's YM registers, active
// player mode, and per-channel scopes into these ZigOS fields each frame so the
// music scene can visualise the chip. (Audio itself is still the standalone
// audio.wasm module; splitting it into machine-audio.wasm + ZigOS players is the
// next step of the seal.)
// --------------------------------------------------------------------------
export fn getYmRegsPointer() [*]u8 {
    return @ptrCast(&zigos.ym_regs);
}
export fn getAudioModePointer() [*]u8 {
    return @ptrCast(&zigos.audio_mode);
}
export fn getSongMsPointer() [*]u32 {
    return @ptrCast(&zigos.song_ms);
}
export fn getScopesPointer() [*]f32 {
    return @ptrCast(&zigos.scopes);
}
