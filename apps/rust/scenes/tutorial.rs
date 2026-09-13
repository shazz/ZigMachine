// ---------------------------------------------------------------------------
// tutorial.rs: "your first screen", the Rust version of docs/TUTORIAL.md (step 7).
//
// A sky with a copper bar, a bouncing block, a checkerboard floor, a scroller
// and SNDH music, written straight against the sealed ABI (no_std, no crate):
// palette indices in shared memory and a few registers.
//
// Build: bash apps/rust/build.sh tutorial
// Run:   docs/index.html?demo=demo-rust-tutorial.wasm
// ---------------------------------------------------------------------------
#![no_std]
#![no_main]

use core::panic::PanicInfo;
use core::ptr::addr_of_mut;

// The song bridge. Declaring the module defines the exports the host polls.
#[path = "../zigmachine_music.rs"]
mod zigmachine_music;

// --- the sealed ABI: one import, and offsets from machine/sdk/memmap.zig ---
#[link(wasm_import_module = "env")]
extern "C" {
    fn hwVideoBase() -> i32;
}

const OFF_PAL: usize = 0x0100; // plane 0 palette: 256 x RGBA u32
const OFF_VRAM: usize = 0x1100; // plane 0 framebuffer: 320 x 200 palette indices
const REG_BACKGROUND: usize = 0x04; // u32: the border/background colour
const REG_FB_HBL_ID: usize = 0x20; // u16 per plane: 0 = no HBL
const REG_FB_HBL_POS: usize = 0x28; // u16 per plane: the column the HBL fires at
const W: usize = 320;
const H: usize = 200;

// palette indices
const SKY: u8 = 0;
const FLOOR_DARK: u8 = 1;
const FLOOR_LIGHT: u8 = 2;
const BLOCK: u8 = 3;
const TEXT_INK: u8 = 4;

const FLOOR_Y: usize = 160;
const BLOCK_SIZE: i32 = 24;
const BAR_H: i32 = 16;

// A 5x7 font holding only the letters TEXT uses: one byte per row, bit 4 = left.
const GLYPHS: &[u8] = b"ACEFGHILMNORSTUYZ*";
const FONT: [[u8; 7]; 18] = [
    [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11], // A
    [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E], // C
    [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F], // E
    [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10], // F
    [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F], // G
    [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11], // H
    [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E], // I
    [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F], // L
    [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11], // M
    [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11], // N
    [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E], // O
    [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11], // R
    [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E], // S
    [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04], // T
    [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E], // U
    [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04], // Y
    [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F], // Z
    [0x00, 0x15, 0x0E, 0x1F, 0x0E, 0x15, 0x00], // *
];
const TEXT: &[u8] = b"HELLO FROM RUST * THIS IS YOUR FIRST ZIGMACHINE SCREEN * ";
const SCALE: usize = 2; // each font pixel is drawn 2x2
const ADVANCE: usize = 12; // 5 columns x 2, plus a 2-pixel gap

struct Screen {
    base: usize,
    block_x: i32,
    block_y: i32,
    block_dx: i32,
    block_dy: i32,
    bar_y: i32,
    bar_dy: i32,
    copper: [u32; H], // the SKY colour of each visible line
    scroll_x: usize,
}

static mut SCREEN: Screen = Screen {
    base: 0,
    block_x: 40,
    block_y: 40,
    block_dx: 2,
    block_dy: 1,
    bar_y: 24,
    bar_dy: 2,
    copper: [0; H],
    scroll_x: 0,
};

fn screen() -> &'static mut Screen {
    // SAFETY: a wasm32 cart is single-threaded, and the host never re-enters it.
    unsafe { &mut *addr_of_mut!(SCREEN) }
}

const fn rgba(r: u32, g: u32, b: u32) -> u32 {
    0xFF00_0000 | b << 16 | g << 8 | r
}

impl Screen {
    fn vram(&self) -> &'static mut [u8] {
        // SAFETY: plane 0's framebuffer, inside the machine's video region.
        unsafe { core::slice::from_raw_parts_mut((self.base + OFF_VRAM) as *mut u8, W * H) }
    }

    fn palette(&self) -> &'static mut [u32] {
        // SAFETY: plane 0's 256-entry palette, inside the machine's video region.
        unsafe { core::slice::from_raw_parts_mut((self.base + OFF_PAL) as *mut u32, 256) }
    }

    fn fill_rect(&self, x: usize, y: usize, w: usize, h: usize, index: u8) {
        let vram = self.vram();
        for row in y..y + h {
            vram[row * W + x..row * W + x + w].fill(index);
        }
    }

    fn draw_floor(&self) {
        let vram = self.vram();
        for y in FLOOR_Y..H {
            for x in 0..W {
                vram[y * W + x] = if (x / 20 + y / 10) & 1 == 1 { FLOOR_LIGHT } else { FLOOR_DARK };
            }
        }
    }

    fn move_block(&mut self) {
        self.block_x += self.block_dx;
        self.block_y += self.block_dy;
        if self.block_x <= 0 || self.block_x >= W as i32 - BLOCK_SIZE {
            self.block_dx = -self.block_dx;
        }
        if self.block_y <= 28 || self.block_y >= FLOOR_Y as i32 - BLOCK_SIZE {
            self.block_dy = -self.block_dy;
        }
    }

    // One colour per line: a sky gradient, with a copper bar over it.
    fn build_copper(&mut self) {
        for line in 0..H as i32 {
            let d = line - self.bar_y;
            self.copper[line as usize] = if (0..BAR_H).contains(&d) {
                let k = (if d < BAR_H / 2 { d + 1 } else { BAR_H - d }) as u32; // 1..8..1
                rgba(k * 31, k * 24, k * 8)
            } else {
                rgba(0, line as u32 / 4, 40 + line as u32 / 2)
            };
        }
        self.bar_y += self.bar_dy;
        if self.bar_y <= 24 || self.bar_y >= FLOOR_Y as i32 - BAR_H {
            self.bar_dy = -self.bar_dy;
        }
    }

    fn draw_char(&self, c: u8, x: i32, y: usize) {
        // a space, or a letter the font lacks, draws nothing
        let Some(g) = GLYPHS.iter().position(|&l| l == c) else { return };
        let vram = self.vram();
        for (row, bits) in FONT[g].iter().enumerate() {
            for col in 0..5 {
                if bits & (0x10 >> col) == 0 {
                    continue;
                }
                for sy in 0..SCALE {
                    for sx in 0..SCALE {
                        let px = x + (col * SCALE + sx) as i32;
                        if (0..W as i32).contains(&px) {
                            vram[(y + row * SCALE + sy) * W + px as usize] = TEXT_INK;
                        }
                    }
                }
            }
        }
    }

    fn draw_scroller(&mut self) {
        let mut i = 0;
        loop {
            let x = (i * ADVANCE) as i32 - self.scroll_x as i32;
            if x >= W as i32 {
                break;
            }
            if x > -(ADVANCE as i32) {
                self.draw_char(TEXT[i % TEXT.len()], x, 8);
            }
            i += 1;
        }
        self.scroll_x = (self.scroll_x + 2) % (TEXT.len() * ADVANCE);
    }
}

#[panic_handler]
fn panic(_: &PanicInfo) -> ! {
    loop {}
}

#[no_mangle]
pub extern "C" fn boot() {
    zigmachine_music::request_song("sos.sndh"); // a file under docs/music/

    let s = screen();
    // SAFETY: a plain import from the machine; it returns the video region's base.
    s.base = unsafe { hwVideoBase() } as usize;
    // SAFETY: REG_BACKGROUND is a u32 register inside the video region.
    unsafe { ((s.base + REG_BACKGROUND) as *mut u32).write(rgba(0, 0, 0)) };

    let pal = s.palette();
    pal[SKY as usize] = rgba(0, 0, 40);
    pal[FLOOR_DARK as usize] = rgba(60, 20, 90);
    pal[FLOOR_LIGHT as usize] = rgba(140, 60, 180);
    pal[BLOCK as usize] = rgba(255, 210, 0);
    pal[TEXT_INK as usize] = rgba(255, 255, 255);

    s.fill_rect(0, 0, W, H, SKY);
    s.draw_floor();
    s.copper = [pal[SKY as usize]; H];

    // Arm plane 0's HBL: any non-zero id, fired at column 0 of every line.
    // SAFETY: plane 0's u16 HBL registers, inside the video region.
    unsafe {
        ((s.base + REG_FB_HBL_ID) as *mut u16).write(1);
        ((s.base + REG_FB_HBL_POS) as *mut u16).write(0);
    }
}

#[no_mangle]
pub extern "C" fn frame(_elapsed_ms: f32) {
    let s = screen();
    s.fill_rect(0, 0, W, FLOOR_Y, SKY); // wipe last frame's sky
    s.move_block();
    let size = BLOCK_SIZE as usize;
    s.fill_rect(s.block_x as usize, s.block_y as usize, size, size, BLOCK);
    s.build_copper();
    s.draw_scroller();
}

#[no_mangle]
pub extern "C" fn isPlaneEnabled(id: i32) -> i32 {
    (id == 0) as i32
}

// The machine calls this before it draws each line of plane 0. `line` is the
// LOGICAL line, 0..199, on a normal plane.
#[no_mangle]
pub extern "C" fn hblDispatch(_id: u32, _plane: u32, line: u32, _x: u32) {
    let s = screen();
    s.palette()[SKY as usize] = s.copper[line as usize];
}

// The host calls these too. Stubs, so no call ever hits a missing export.
#[no_mangle]
pub extern "C" fn skipBoot() {}
#[no_mangle]
pub extern "C" fn setShadeMode(_m: u32) {}
#[no_mangle]
pub extern "C" fn pointer(_x: i32, _y: i32, _b: u32) {}
#[no_mangle]
pub extern "C" fn input(_dir: u8) {}
