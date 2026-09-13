// ---------------------------------------------------------------------------
// ZigMachine "hello world" — written in Rust (no_std), compiled to a sealed
// -machine app. Same sealed machine-video.wasm, same memory-mapped ABI as the
// Zig demo and the C prototype: two imports, raw 8-bit indices into the shared
// video region.
//
// Build: see apps/rust/build.sh (rustc + bundled rust-lld). Output: docs/demo-rust.wasm
// Run:   docs/sealed.html?demo=demo-rust.wasm
// ---------------------------------------------------------------------------
#![no_std]
#![no_main]

use core::panic::PanicInfo;

// The song bridge (apps/rust/zigmachine_music.rs). Declaring it exports the four
// symbols the host polls; hello requests nothing, so the host never plays a
// tune. A screen with music would call, in boot():
//     zigmachine_music::request_song("sos.sndh");            // default subtune
//     zigmachine_music::request_song_tune("leavin_teramis.sndh", 9);
mod zigmachine_music;

// --- ABI geometry (mirror of hw/sdk/memmap.zig) ---
const REG_BACKGROUND: usize = 0x04; // u32 RGBA
const OFF_PAL: usize = 0x0100; // palette 0: 256 x RGBA u32
const OFF_VRAM: usize = 0x1100; // plane 0 framebuffer (reset FB_BASE)
const WIDTH: usize = 320;
const HEIGHT: usize = 200;

// --- imports resolved by the loader against the machine / JS "env" module ---
#[link(wasm_import_module = "env")]
extern "C" {
    fn hwVideoBase() -> i32;
    fn consoleLogJS(ptr: *const u8, len: i32);
}

// --- the ROM chip: GEM, called from Rust (rom/sdk/rom.zig) ---
// The same flat ABI the C app uses: only numbers cross — a u32 handle,
// coordinates, a (pointer, length) for text. The ROM reads plane 0's
// framebuffer out of the video registers itself, so no Zig type is needed.
#[link(wasm_import_module = "env")]
extern "C" {
    fn guiOpenPlane(plane: u32, w: i32, h: i32) -> u32;
    fn romInstallPalettePlane(plane: u32);
    fn guiRect(gui: u32, x: i32, y: i32, w: i32, h: i32, color: u32);
    fn guiFrame(gui: u32, x: i32, y: i32, w: i32, h: i32, color: u32);
    fn guiText(gui: u32, ptr: *const u8, len: u32, x: i32, y: i32, ink: u32, paper: u32);
}

const GEM_BLACK: u32 = 0;
const GEM_WHITE: u32 = 1;

static mut GUI: u32 = 0; // the ROM handle; 0 = no context
static mut VIDEO_BASE: usize = 0;
static mut TRI: [u8; 256] = [0; 256]; // triangle-wave LUT (libm-free "sine")
static mut PLANE0_ON: bool = false;
static mut FRAME: u32 = 0;

#[panic_handler]
fn panic(_: &PanicInfo) -> ! {
    loop {}
}

// HSV(h,1,1) -> RGB via integer sextants; fills palette 0 with a rainbow.
unsafe fn build_rainbow(base: usize) {
    let p = (base + OFF_PAL) as *mut u8;
    for i in 0..256usize {
        let seg = i / 43;
        let rem = ((i - seg * 43) * 6) as i32;
        let (q, t) = (255 - rem, rem);
        let (r, g, b) = match seg {
            0 => (255, t, 0),
            1 => (q, 255, 0),
            2 => (0, 255, t),
            3 => (0, q, 255),
            4 => (t, 0, 255),
            _ => (255, 0, q),
        };
        p.add(i * 4).write(r as u8);
        p.add(i * 4 + 1).write(g as u8);
        p.add(i * 4 + 2).write(b as u8);
        p.add(i * 4 + 3).write(255); // ALPHA 255 = opaque
    }
}

#[no_mangle]
pub extern "C" fn boot() {
    const MSG: &[u8] = b"Hello, world - from Rust on ZigMachine!";
    unsafe {
        consoleLogJS(MSG.as_ptr(), MSG.len() as i32);
        let base = hwVideoBase() as usize;
        VIDEO_BASE = base;
        ((base + REG_BACKGROUND) as *mut u32).write(0xFF00_0000u32); // opaque black
        build_rainbow(base);
        for i in 0..256usize {
            TRI[i] = if i < 128 { (i * 2) as u8 } else { ((255 - i) * 2) as u8 };
        }
        PLANE0_ON = true;
        // SAFETY: guiOpenPlane only reads plane 0's registers from the shared
        // video region; a 0 handle means "no context" and every draw is skipped.
        GUI = guiOpenPlane(0, WIDTH as i32, HEIGHT as i32);
        let note: &[u8] = if GUI != 0 {
            // GEM draws palette INDICES 0/1: let the ROM install just its own
            // entries so the panel is black/white and the plasma keeps the rest.
            romInstallPalettePlane(0);
            b"Rust app opened a GEM context from the ROM chip"
        } else {
            b"Rust app could NOT open a GEM context"
        };
        consoleLogJS(note.as_ptr(), note.len() as i32);
    }
}

// A GEM panel drawn BY THE ROM over this program's plasma: the fills, GEM's
// double border and the 8x8 system font all come from rom.wasm. Same geometry
// as the C app, which is what apps/verify.mjs reads back.
unsafe fn draw_rom_panel() {
    if GUI == 0 {
        return;
    }
    let (x, y, w, h) = (40, 68, 240, 64);
    let text = |s: &[u8], ty: i32, ink: u32, paper: u32| {
        // SAFETY: (ptr, len) names a 'static byte string; the ROM copies nothing past len.
        unsafe { guiText(GUI, s.as_ptr(), s.len() as u32, x + 8, ty, ink, paper) }
    };
    guiRect(GUI, x, y, w, h, GEM_WHITE); // panel face
    guiFrame(GUI, x, y, w, h, GEM_BLACK); // GEM's double border
    guiFrame(GUI, x + 1, y + 1, w - 2, h - 2, GEM_BLACK);
    guiRect(GUI, x + 3, y + 3, w - 6, 10, GEM_BLACK); // title bar, inverse
    text(b"GEM FROM RUST", y + 4, GEM_WHITE, GEM_BLACK);
    text(b"rom.wasm drew this panel", y + 22, GEM_BLACK, GEM_WHITE);
    text(b"and this text, for Rust", y + 34, GEM_BLACK, GEM_WHITE);
}

#[no_mangle]
pub extern "C" fn frame(_elapsed_ms: f32) {
    unsafe {
        FRAME = FRAME.wrapping_add(1);
        let t = FRAME as usize;
        let fb = (VIDEO_BASE + OFF_VRAM) as *mut u8;
        for y in 0..HEIGHT {
            for x in 0..WIDTH {
                let v = TRI[(x + t) & 255] as u32
                    + TRI[(y * 2 + t) & 255] as u32
                    + TRI[(x + y + 2 * t) & 255] as u32;
                fb.add(y * WIDTH + x).write(((v >> 2) & 255) as u8);
            }
        }
        draw_rom_panel(); // ...then let the ROM draw GEM over the top
    }
}

#[no_mangle]
pub extern "C" fn isPlaneEnabled(id: i32) -> i32 {
    unsafe { (id == 0 && PLANE0_ON) as i32 }
}

// Optional ABI surface — no-op stubs so a keypress/HBL never hits a missing export.
#[no_mangle]
pub extern "C" fn hblDispatch(_id: u32, _plane: u32, _line: u32, _x: u32) {}
#[no_mangle]
pub extern "C" fn skipBoot() {}
#[no_mangle]
pub extern "C" fn setShadeMode(_m: u32) {}
#[no_mangle]
pub extern "C" fn pointer(_x: i32, _y: i32, _b: u32) {}
#[no_mangle]
pub extern "C" fn input(_dir: u8) {}
