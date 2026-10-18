// The rectangles drawn over fond_v8 this frame, put back from it next frame.
//
// Why: go() redraws fond_v8 under everything every frame (screen.js:221), and
// copying its 64,000 bytes into the plane cost ~0.96 Mcycles a frame on the
// board, where every store is a blocking DDR write. Only the letters and the logo
// rows ever cover it, so the frame restores just what they covered (the ST's
// save-under), in aligned 32-bit words: ~13 KB instead of 64. Every frame still
// starts from a whole fond_v8, so the picture is the same byte for byte.

use super::scroll::{H, W};

const CAP: usize = 128; // 20 + 20 letters and 70 logo rows a frame
const FOND_LEN: usize = (W * H) as usize;

/// fond.bin, 4-aligned so a row's words can be read as u32.
#[repr(C, align(4))]
struct Aligned([u8; FOND_LEN]);
static FOND: Aligned = Aligned(*include_bytes!("../../assets/screens/v8_populous/fond.bin"));

#[derive(Clone, Copy)]
struct Rect {
    x0: u16, // 4-aligned
    x1: u16, // 4-aligned, exclusive
    y0: u16,
    y1: u16,
}

pub struct Dirty {
    rects: [Rect; CAP],
    n: usize,
    whole: bool, // the next restore copies all of fond_v8 (first frame, or overflow)
}

impl Dirty {
    pub const fn new() -> Dirty {
        Dirty { rects: [Rect { x0: 0, x1: 0, y0: 0, y1: 0 }; CAP], n: 0, whole: true }
    }

    /// The w x h rectangle at (x, y), clipped to the plane, widened to whole words.
    pub fn add(&mut self, x: i32, y: i32, w: i32, h: i32) {
        let (x0, x1) = (x.max(0) & !3, ((x + w).min(W) + 3) & !3);
        let (y0, y1) = (y.max(0), (y + h).min(H));
        if x0 >= x1 || y0 >= y1 {
            return;
        }
        if self.n == CAP {
            self.whole = true;
            return;
        }
        self.rects[self.n] = Rect { x0: x0 as u16, x1: x1 as u16, y0: y0 as u16, y1: y1 as u16 };
        self.n += 1;
    }

    /// Put fond_v8 back wherever the last frame drew (all of it the first time).
    pub fn restore(&mut self, vram: &mut [u8]) {
        if self.whole {
            vram.copy_from_slice(&FOND.0);
        } else {
            for r in &self.rects[..self.n] {
                for y in r.y0 as usize..r.y1 as usize {
                    let at = y * W as usize;
                    copy_words(vram, at + r.x0 as usize, at + r.x1 as usize);
                }
            }
        }
        self.n = 0;
        self.whole = false;
    }
}

/// vram[a..b] = fond[a..b], a and b multiples of 4.
fn copy_words(vram: &mut [u8], a: usize, b: usize) {
    let src = &FOND.0[a..b];
    let dst = &mut vram[a..b];
    // SAFETY: FOND is 4-aligned and so is the plane (the video region's VRAM
    // offset is), a and b are multiples of 4, and both ranges are in bounds
    // (the slices above checked them).
    unsafe {
        let s = src.as_ptr() as *const u32;
        let d = dst.as_mut_ptr() as *mut u32;
        // volatile: LLVM would turn a plain loop back into a memcpy (picolibc
        // on the board, ~60 cycles a word against one ~27-cycle store)
        for i in 0..(b - a) / 4 {
            d.add(i).write_volatile(*s.add(i));
        }
    }
}
