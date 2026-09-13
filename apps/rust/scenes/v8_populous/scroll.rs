// The screen's two scrollers, as CODEF runs them (lib/codef_scrolltext.js and
// the screen's own scrolltext_horizontal_totor, screen.js:286).
//
// Both are a ring of WIDE+1 = 20 letters, 36 canvas px apart (font tiles are
// 36x30, first char 32), starting just off the right edge at 684 + 36*i. A letter
// that reaches -36 jumps back to the right end and takes the next character.
//
// Each CODEF scroller is drawn TWICE, by two identical instances: once with
// font_v8_b (a white mask) into a canvas that is then filled with ras_d through
// `source-in`, and once with font_v8 (the grey ink) straight on top. The two
// fonts are disjoint, so here one glyph carries both: grey ink indices, MASK
// where the ras colour shows through, 0 where nothing is drawn.

use super::fmath::{ceil, half, sin};

const FONT: &[u8] = include_bytes!("../../assets/screens/v8_populous/font.bin");
const RAS: &[u8] = include_bytes!("../../assets/screens/v8_populous/ras.bin");
const GW: i32 = 18; // one glyph in ST px (36x30 canvas)
const GH: i32 = 15;
const GLYPHS: u8 = 60; // 10x6 sheet, from char 32
const MASK: u8 = 255;
const LETTERS: usize = 20; // wide = ceil(640/36)+1 = 19, letters 0..=19
const RING: f64 = 19.0 * 36.0; // wide * fontw, the re-entry point

pub const W: i32 = 320;
pub const H: i32 = 200;

/// One glyph at ST (x, y). `ras_top` is the ST row where ras_d was drawn into this
/// scroller's mask canvas: `source-in` keeps the mask only where ras_d covers it.
fn glyph(vram: &mut [u8], ch: u8, x: i32, y: i32, ras_top: i32) {
    let g = ch.wrapping_sub(32);
    if g >= GLYPHS {
        return; // past the sheet: drawImage's source rect is empty
    }
    let src = &FONT[g as usize * (GW * GH) as usize..][..(GW * GH) as usize];
    for gy in 0..GH {
        let py = y + gy;
        if !(0..H).contains(&py) {
            continue;
        }
        let ras_row = py - ras_top;
        let ras = if (0..RAS.len() as i32).contains(&ras_row) { RAS[ras_row as usize] } else { 0 };
        for gx in 0..GW {
            let px = x + gx;
            let v = match src[(gy * GW + gx) as usize] {
                MASK => ras,
                v => v,
            };
            if v != 0 && (0..W).contains(&px) {
                vram[(py * W + px) as usize] = v;
            }
        }
    }
}

/// The ring both scroller kinds share: positions, characters, text cursor.
pub struct Ring {
    x: [f64; LETTERS],
    ch: [u8; LETTERS],
    cursor: usize,
    text: &'static [u8],
}

impl Ring {
    pub const fn new(text: &'static [u8]) -> Ring {
        let mut r = Ring { x: [0.0; LETTERS], ch: [0; LETTERS], cursor: LETTERS, text };
        let mut i = 0;
        while i < LETTERS {
            r.x[i] = RING + (i * 36) as f64;
            r.ch[i] = text[i];
            i += 1;
        }
        r
    }

    /// Move every letter; returns how many wrapped (the wave scroller needs it).
    fn advance(&mut self, speed: f64) -> u32 {
        let mut wrapped = 0;
        for i in 0..LETTERS {
            self.x[i] -= speed;
            if self.x[i] <= -36.0 {
                self.x[i] = RING + (self.x[i] + 36.0);
                self.ch[i] = self.text[self.cursor];
                self.cursor += 1;
                if self.cursor > self.text.len() - 1 {
                    self.cursor = 0;
                }
                wrapped += 1;
            }
        }
        wrapped
    }

    /// Letter indices left to right: the ring stays cyclically sorted, so this is
    /// CODEF's `temp.sort(sortPosx)` without the sort.
    fn leftmost(&self) -> usize {
        (0..LETTERS).fold(0, |m, i| if self.x[i] < self.x[m] { i } else { m })
    }
}

/// scrolltext_horizontal with {amp 40, inc 0.8, offset -0.05}, speed 2, posy 110;
/// its mask gets ras_d at canvas y 72.
pub struct Wave {
    ring: Ring,
    value: f64,
}

impl Wave {
    pub const fn new(text: &'static [u8]) -> Wave {
        Wave { ring: Ring::new(text), value: 0.0 }
    }

    pub fn draw(&mut self, vram: &mut [u8]) {
        // A wrapping letter carries the phase along (oldvalue += inc), so the wave
        // sticks to the text; otherwise it drifts back by `offset` each frame.
        let mut base = self.value;
        for _ in 0..self.ring.advance(2.0) {
            base += 0.8;
        }
        let first = self.ring.leftmost();
        self.value = base;
        for k in 0..LETTERS {
            let i = (first + k) % LETTERS;
            let y = 110.0 + sin(self.value) * 40.0;
            glyph(vram, self.ring.ch[i], half(self.ring.x[i]), half(y), 36);
            self.value += 0.8;
        }
        self.value = base + -0.05;
    }
}

/// scrolltext_horizontal_totor, speed 1.4, posy 140; its mask gets ras_d at 216.
/// The y of a letter is SCROLLPOS[ceil(x)], a table indexed by screen column. A
/// column outside the table (x <= -1, or x > 617) is `undefined` in JS, the y
/// becomes NaN and drawImage draws nothing: letters pop out at the left edge and
/// pop in 22 canvas px before the right one. That is the original's behaviour.
pub struct Totor {
    ring: Ring,
}

impl Totor {
    pub const fn new(text: &'static [u8]) -> Totor {
        Totor { ring: Ring::new(text) }
    }

    pub fn draw(&mut self, vram: &mut [u8]) {
        self.ring.advance(1.4);
        for i in 0..LETTERS {
            let col = ceil(self.ring.x[i]);
            if let Some(&dy) = usize::try_from(col).ok().and_then(|c| SCROLLPOS.get(c)) {
                let y = half(f64::from(dy) + 140.0);
                glyph(vram, self.ring.ch[i], half(self.ring.x[i]), y, 108);
            }
        }
    }
}

// screen.js:285, verbatim (618 entries, canvas px).
#[rustfmt::skip]
static SCROLLPOS: [u8; 618] = [
    152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,
    152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,
    152,152,152,152,152,152,152,152,152,152,149,148,148,148,148,148,148,148,147,146,146,146,146,146,145,144,144,144,144,144,144,144,
    143,142,142,142,138,138,138,138,138,134,130,130,128,128,126,126,124,124,122,120,120,120,110,110,110,110,110,110,100,100,100,100,
    100,100,100,100,100,90,90,80,80,80,80,80,80,80,80,80,80,80,80,80,80,80,80,80,80,80,80,80,80,80,80,80,
    80,80,80,80,80,80,80,80,80,80,80,84,84,84,84,84,84,84,84,84,84,84,84,80,80,80,80,80,80,80,80,80,
    80,80,80,84,84,84,84,84,84,84,84,84,84,84,84,80,80,80,80,80,80,80,80,80,80,80,80,84,84,84,84,84,
    84,84,84,84,84,84,84,80,80,80,80,80,80,80,80,80,80,80,80,84,84,84,84,84,84,84,84,84,84,84,84,80,
    80,80,80,80,80,80,80,80,80,80,80,84,84,84,84,84,84,84,84,84,84,84,84,80,80,80,80,80,80,80,80,80,
    80,80,80,84,84,84,84,84,84,84,84,84,84,84,84,80,80,80,80,80,80,80,80,80,80,80,80,84,84,84,84,84,
    84,84,84,84,84,84,84,80,80,80,80,80,80,80,80,80,80,80,80,84,84,84,84,84,84,84,84,84,84,84,84,80,
    80,80,80,80,80,80,80,80,80,80,80,84,84,84,84,84,84,84,84,84,84,84,84,80,80,80,80,80,80,80,80,80,
    80,80,80,84,84,84,84,84,84,84,84,84,84,84,84,80,80,80,80,80,80,80,80,80,80,80,80,84,84,84,84,84,
    84,84,84,84,84,84,84,80,80,80,80,80,80,80,80,80,80,80,80,84,84,84,84,84,84,84,84,84,84,84,84,80,
    80,80,80,80,80,80,80,80,80,80,80,84,84,84,84,84,84,84,84,84,84,84,84,80,80,80,80,80,80,80,80,80,
    80,80,80,90,90,100,100,100,100,100,100,100,100,100,110,110,110,110,110,110,120,120,120,122,124,124,126,128,126,128,130,130,
    134,138,138,138,138,138,142,142,142,143,144,144,144,144,144,144,144,145,146,146,146,146,146,147,148,148,148,148,148,148,148,149,
    152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,
    152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,152,
    152,152,152,152,152,152,152,152,152,152,
];
