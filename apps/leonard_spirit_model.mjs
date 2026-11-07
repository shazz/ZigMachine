// The model apps/leonard_spirit_headless.mjs holds LEONARD'S SPIRIT to, written
// from the scene's documented maths and show (apps/zig/scenes/leonard_spirit/
// path.zig, show.zig, layout.zig), not from the Zig. Pure functions of the frame.
import { readFileSync } from "node:fs";

export const A = "apps/zig/assets/screens/leonard/";
export const SNAKES = 7, SNAKE_LEN = 312, NB = SNAKES * SNAKE_LEN; // the record
export const WIN_W = 400, WIN_H = 280, BUF_W = 576, PAN_X = 176, PAN_Y = 168, SCROLL_Y = 234;

const back = readFileSync(A + "back.raw"), ball = readFileSync(A + "ball.raw"), font = readFileSync(A + "font.raw");
const SIN = Int16Array.from({ length: 1024 }, (_, i) => Math.round(32767 * Math.sin((i * 2 * Math.PI) / 1024)));
const DEG = Uint32Array.from({ length: 360 }, (_, d) => Number((BigInt(d) << 32n) / 360n));
const sin = (a) => SIN[a >>> 22], cos = (a) => SIN[((a >>> 22) + 256) & 1023];
const STEP = DEG[1]; // t = 1 degree, as in 2005

/** The pan of scroll phase p (0..359): one turn in x, two in y. */
export function pan(p) {
    const a = (p * 2 * Math.PI) / 360;
    return [Math.round(PAN_X / 2 + (PAN_X / 2) * Math.sin(a)), Math.round(PAN_Y / 2 + (PAN_Y / 2) * Math.sin(2 * a + 1))];
}
const [OX, OY] = ((s) => [s[0] + 40, s[1] + 40])(pan(0)); // tile (0,0) at the window's (40,40) on frame 0

// ---- the show: 180 still frames, then sides, bottom, top shake open, then the scroll eases in
const SHAKE = [30, 24, 19, 15, 12, 9, 7, 5, 4, 3, 2, 2, 1, 1, 1, 1];
const SHAKE_LEN = SHAKE.reduce((a, b) => a + b), GAP = 30, STATIC_END = 180;
export const stageStart = (s) => STATIC_END + s * (SHAKE_LEN + GAP); // 0 sides, 1 bottom, 2 top
export const OPEN_END = stageStart(2) + SHAKE_LEN, EASE_START = OPEN_END + GAP, EASE_LEN = 240;
export const CRUISE = EASE_START + EASE_LEN;
// ---- only the record's snake until the scroll starts, then snakes 1..6 fade in under it (Matt,
// 6 Nov: a dissolve, not from black): level n (one every 8 frames) draws n of each ball's 16 rows,
// bit-reversed order, in colours from the picture's blue (entry 1) to the ball's
export const FADE_START = EASE_START, FADE_STEP = 8, FADE_END = FADE_START + 15 * FADE_STEP; // level 16 from FADE_END
export const fadeLevel = (t) => (t < FADE_START ? 0 : Math.min(16, Math.floor((t - FADE_START) / FADE_STEP) + 1));
const ROW_ORDER = [0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15];
export const fadeRows = (level) => ROW_ORDER.slice(0, level).reduce((m, r) => m | (1 << r), 0);
// ---- the scrolltext's fall (scene: leonard_spirit/fall.zig): once the bottom stays open it drops
// from row 234 to 274 (the same 0-pixel gap to the open bottom) and bounces, Q8 integer steps
export const FALL_START = stageStart(1) + SHAKE_LEN, FALL_LOW = WIN_H - 6 - 6; // the letters' 6 rows, then a 6-pixel margin (Matt, 2026-11-01)
export function fallRows(bounce = true) {
    const rows = [];
    let y = SCROLL_Y << 8, v = 0;
    for (;;) {
        v += 48; y += v;
        if (y >= FALL_LOW << 8) {
            y = FALL_LOW << 8;
            v = -((v * 128) >> 8);
            if (!bounce || -v < 64) break;
        }
        rows.push(y >> 8);
    }
    return rows;
}
export const scrollRow = (t, rows) => (t < FALL_START ? SCROLL_Y : t - FALL_START < rows.length ? rows[t - FALL_START] : FALL_LOW);
export function isOpen(s, t) {
    let at = stageStart(s), open = false;
    if (t < at) return false;
    for (const d of SHAKE) { if (t < at + d) return open; at += d; open = !open; }
    return true;
}
export const openMask = (t) => (isOpen(0, t) ? 1 : 0) | (isOpen(1, t) ? 2 : 0) | (isOpen(2, t) ? 4 : 0);
/** Q16 path frames a frame: 0, then (n/EASE_LEN)^2, then 1. `linear` for --break scroll. */
export function speed(t, linear = false) {
    if (t < EASE_START) return 0;
    if (t >= CRUISE) return 65536;
    const n = t - EASE_START;
    return linear ? Math.floor((n * 65536) / EASE_LEN) : Math.floor((n * n * 65536) / (EASE_LEN * EASE_LEN));
}

/** Window positions of the balls of frame f, in drawing order; `extra` balls
 *  appended to the last snake (--break count). */
export function positions(f, extra = 0) {
    const out = new Int32Array(2 * (NB + extra));
    let n = 0;
    for (let k = 0; k < SNAKES; k++) {
        let a1 = DEG[(3 * f) % 360], a2 = (DEG[(2 * f) % 360] + k * 2 ** 27) >>> 0;
        let b1 = DEG[(360 - f) % 360], b2 = (DEG[(2 * f) % 360] + k * 2 ** 26) >>> 0;
        const len = SNAKE_LEN + (k === SNAKES - 1 ? extra : 0);
        for (let i = 0; i < len; i++, n++) {
            out[2 * n] = 192 + ((96 * (cos(a1) + sin(a2))) >> 15);
            out[2 * n + 1] = 126 + ((63 * (cos(b1) + sin(b2))) >> 15);
            a1 = (a1 + 7 * STEP) >>> 0; a2 = (a2 - 4 * STEP) >>> 0;
            b1 = (b1 + 6 * STEP) >>> 0; b2 = (b2 - 3 * STEP) >>> 0;
        }
    }
    return out;
}

const ink = (c, sx, r) => font[(c.charCodeAt(0) - 32) * 36 + r * 6 + sx] !== 0;

/** The window (400x280 indices) of ball frame f at pan (sx, sy), scroller tick t. */
export function windowPixels(out, f, [sx, sy], t, text, extra = 0, row = SCROLL_Y, level = 16) {
    for (let y = 0; y < WIN_H; y++) {
        const ty = (sy + y + 600 - OY) % 200;
        for (let x = 0; x < WIN_W; x++) out[y * WIN_W + x] = back[ty * 320 + ((sx + x + 640 - OX) % 320)];
    }
    const pos = positions(f, extra), n = pos.length / 2;
    const draw = (i, ink, rows = 0xffff) => {
        const x = pos[2 * i], y = pos[2 * i + 1];
        for (let r = 0; r < 16; r++) if ((rows >> r) & 1) for (let c = 0; c < 16; c++) {
            const v = ball[r * 16 + c];
            if (v) out[(y + r) * WIN_W + x + c] = v + ink;
        }
    };
    if (level > 0) for (let i = SNAKE_LEN; i < n; i++) draw(i, 7, fadeRows(level)); // the fading snakes, under
    for (let i = 0; i < SNAKE_LEN; i++) draw(i, 3); // Leonard's 312 on top
    const s = t * 2, lap = text.length * 6;
    for (let x = 0; x < WIN_W; x++) {
        const p = (s + x) % lap, ch = text[Math.floor(p / 6)];
        for (let r = 0; r < 6; r++) if (ink(ch, p % 6, r)) out[(row + r) * WIN_W + x] = 7;
    }
    return pos;
}

/** The merged palette as the machine stores it (a<<24 | b<<16 | g<<8 | r). */
export function mergedPalette() {
    const word = (f, i) => readFileSync(A + f).readUInt32LE(i * 4);
    return [0, 1, 2, 3].map((i) => word("back_pal.dat", i))
        .concat([1, 2, 3].map((i) => word("ball_pal.dat", i)), [word("font_pal.dat", 1)]);
}
/** The merged palette on a fade level: 8-10 from the picture's entry 1 to the ball's shades,
 *  (from * (16 - level) + to * level) >> 4 per channel (the ball's alpha kept). */
export function fadedPalette(base, level) {
    const p = base.slice(), from = base[1];
    for (let i = 0; i < 3; i++) {
        const c = base[4 + i], ch = (sh) => ((((from >>> sh) & 255) * (16 - level) + ((c >>> sh) & 255) * level) >> 4) << sh;
        p[8 + i] = ((c & 0xff000000) | ch(16) | ch(8) | ch(0)) >>> 0;
    }
    return p;
}

export const TEXT_2005 = "HI EVERYBODY ! ULTRA OPTIMISATION RULES, EVEN FOR STUPID RECORD ! I NEVER THOUGH I COULD DISPLAY 312 SPRITES ONE YEAR AGO !  I TOTALLY REWRITE MY PC DATABUILDER TO IMPLEMENT NEW STUFF. THEN, I CHANGE THE CLEARING DATA FORMAT TO GET SOME MEMORY LEFT AND THAT IS !THAT DISK SHOULD (I HOPE) RUN ON 520-STF,MEGASTE,TT,FALCON AND EVEN CT60. GREETINGS ARE SENT TO PHANTOM, GUNSTICK AND SOTE. YOU ALL ARE COOL OPTIMIZERS !  LEONARD/OXYGENE, 17.03.2005";
export const TEXT = " ".repeat(92) + TEXT_2005 + `      ...AND THE STUPID RECORD STRIKES BACK ! ${NB} SPRITES = ${SNAKES} TIMES 312, ALL OF THEM DRAWN EVERY FRAME, FULLSCREEN WITH EVERY BORDER OPEN AND THE BACKGROUND ON THE HARDWARE SCROLL, 60 FPS ON ZIGGY. SAME SPIRIT AS 2005 : THE DATABUILDER DOES THE THINKING, THE PLAYER JUST RUNS. EACH BALL IS GENERATED CODE, 72 MOVES AND NOT ONE MASK, ONE PLANE, NOTHING COMPUTED TWICE. WHO WANTS TO BEAT IT ?  ULTRA OPTIMISATION STILL RULES !`;
