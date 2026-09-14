// The Union Demo TNT1 screen (screens/tnt1/screen.js), replayed in JS at 320x200
// for apps/union_tnt1_headless.mjs. It follows the remake's code, not the scene:
//
//   draw() (screen.js:160-190)   fill #000040; logo at canvas (224,8); ballfield
//                                pass 1 in blue on top; then logo + scroller (row
//                                384) as a mask that ballfield pass 2, in red,
//                                lands 'source-atop' on.
//   ballfield (codef_bobfield.js) new ballfield(ballcanvas, n, 2.0, 640,400,
//                                320,200, 60, 0,0, balls, 17), Math.random fed
//                                by xorshift32 from SEED (the scene's generator).
//                                Each draw() steps it TWICE (screen.js:174, 184).
//   scrolltext_horizontal        speed 3, 32x16 tiles from ' ', 22 letters
//                                (codef_scrolltext.js:44-174, no sinparam).
//
// Canvas coordinates halve to the nearest ST pixel, Math.round(c / 2): a ball
// at canvas x 101.7 lands on ST column 51. Chrome draws the balls bilinearly at
// their fractional positions, which no 256-colour plane can show; against the
// remake in Chrome with the same seed this snap has a mean error of 0.32-0.38
// per channel (floor(c/2): 0.66-0.77) at frames 2, 60, 200 and 1000, and frame
// 1 (logo, no balls) is exact.

export const SEED = 0x1d872b41;
export const KEYS = { "1": 100, "2": 150, "3": 200, "4": 250, "5": 300, "6": 350, "7": 400, "8": 450, "9": 500, "0": 550 };

const W = 320, H = 200;
const LOGO = { w: 78, h: 40, x: 112, y: 4 }; // logo.draw(maincanvas, 224, 8)
const FONT_W = 256, GLYPH_W = 16, GLYPH_H = 8, SCROLL_Y = 192; // scrollcanvas at (0, 384)
const SHEET_W = 272, TILE = 16, TILES = 17;
const BG = 1, INK = 2, RED_FIRST = 11;

export function xorshift32(seed) {
    let s = seed >>> 0;
    return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
}

/// codef_bobfield.js, line for line (w 640, h 400, centre 320,200, ratio 60, speed 2).
function makeBallfield(n, random) {
    const w = 640, h = 400, centx = 320, centy = 200, speed = 2.0, ratio = 60;
    const x = Math.round(w / 2), y = Math.round(h / 2), z = (w + h) / 2;
    const ball = [];
    for (let i = 0; i < n; i++)
        ball.push([random() * w * 2 - x * 2 + 10, random() * h * 2 - y * 2 + 10, Math.round(random() * z), 0, 0]);
    // one draw(): the list of [canvas x, canvas y, tile] it draws, in order
    return () => {
        const out = [];
        for (const b of ball) {
            let test = true;
            const sx = b[3], sy = b[4];
            b[0] += (centx - x) >> 4; if (b[0] > x << 1) { b[0] -= w << 1; test = false; } if (b[0] < -x << 1) { b[0] += w << 1; test = false; }
            b[1] += (centy - y) >> 4; if (b[1] > y << 1) { b[1] -= h << 1; test = false; } if (b[1] < -y << 1) { b[1] += h << 1; test = false; }
            b[2] -= speed; if (b[2] > z) { b[2] -= z; test = false; } if (b[2] < 0) { b[2] += z; test = false; }
            b[3] = x + (b[0] / b[2]) * ratio;
            b[4] = y + (b[1] / b[2]) * ratio;
            if (sx > 0 && sx < w && sy > 0 && sy < h && test) out.push([sx, sy, Math.round(b[2] / (((w + h) / 2) / TILES))]);
        }
        return out;
    };
}

/// `bin` = tnt1.bin (logo | font | balls | ballsRed), `text` = jsApp.scrolltext.
/// opts.halve and opts.passes exist to prove the harness fails on a wrong port.
export function makeReplay(bin, text, opts = {}) {
    const halve = opts.halve ?? ((c) => Math.round(c / 2));
    const passes = opts.passes ?? 2;
    let at = 0;
    const take = (n) => bin.subarray(at, (at += n));
    const logo = take(LOGO.w * LOGO.h), font = take(FONT_W * 32), blue = take(SHEET_W * TILE), red = take(SHEET_W * TILE);
    if (at !== bin.length) throw new Error(`tnt1.bin is ${bin.length} bytes, its layout says ${at}`);

    const random = xorshift32(SEED);
    let balls = 60, field = makeBallfield(balls, random);
    // scrolltext.init(scrollcanvas, font, 3, undefined, 0, 0): wide = 21, letters 0..21
    const letters = [];
    let offset = opts.scroll ?? 0; // scrolltext.init(..., jsApp.mainscrollerPos)
    for (let i = 0; i <= 21; i++) letters.push({ posx: 21 * 32 + i * 32, ltr: text.charCodeAt(offset++) });

    const isMask = (v) => v === INK || v >= RED_FIRST;
    return {
        /// jsApp.mainscrollerPos after the draws so far (screen.js:74)
        scroffset: () => offset,
        /// update(): a number key rebuilds the field with its count (screen.js:82-150)
        key(k) {
            if (KEYS[k] && KEYS[k] !== balls) { balls = KEYS[k]; field = makeBallfield(balls, random); }
        },
        draw() {
            const map = new Uint8Array(W * H).fill(BG);
            const put = (x, y, v, keep) => { if (x >= 0 && x < W && y >= 0 && y < H && keep(map[y * W + x])) map[y * W + x] = v; };
            const any = () => true;
            for (let r = 0; r < LOGO.h; r++) for (let c = 0; c < LOGO.w; c++) if (logo[r * LOGO.w + c]) put(LOGO.x + c, LOGO.y + r, INK, any);
            for (const l of letters) {
                l.posx -= 3;
                if (l.posx <= -32) {
                    l.posx = 21 * 32 + (l.posx + 32);
                    l.ltr = text.charCodeAt(offset++);
                    if (offset > text.length - 1) offset = 0;
                }
            }
            for (const l of letters) {
                const g = l.ltr - 32, gx = (g % 16) * GLYPH_W, gy = Math.floor(g / 16) * GLYPH_H, dx = halve(l.posx);
                for (let r = 0; r < GLYPH_H; r++) for (let c = 0; c < GLYPH_W; c++)
                    if (font[(gy + r) * FONT_W + gx + c]) put(dx + c, SCROLL_Y + r, INK, any);
            }
            const tiles = (sheet, keep) => (list) => {
                for (const [cx, cy, t] of list) {
                    if (t >= TILES) continue; // drawTile(17): a source rect below the sheet draws nothing
                    const dx = halve(cx), dy = halve(cy);
                    for (let r = 0; r < TILE; r++) for (let c = 0; c < TILE; c++) {
                        const v = sheet[r * SHEET_W + t * TILE + c];
                        if (v) put(dx + c, dy + r, v, keep);
                    }
                }
            };
            tiles(blue, (d) => !isMask(d))(field());
            if (passes === 2) tiles(red, isMask)(field());
            return map;
        },
    };
}
