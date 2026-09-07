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
    }
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
