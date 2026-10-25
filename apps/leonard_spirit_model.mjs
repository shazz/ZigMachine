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
export function windowPixels(out, f, [sx, sy], t, text, extra = 0) {
    for (let y = 0; y < WIN_H; y++) {
        const ty = (sy + y + 600 - OY) % 200;
        for (let x = 0; x < WIN_W; x++) out[y * WIN_W + x] = back[ty * 320 + ((sx + x + 640 - OX) % 320)];
    }
    const pos = positions(f, extra);
    for (let i = 0; i < pos.length / 2; i++) {
        const x = pos[2 * i], y = pos[2 * i + 1];
        for (let r = 0; r < 16; r++) for (let c = 0; c < 16; c++) {
            const v = ball[r * 16 + c];
            if (v) out[(y + r) * WIN_W + x + c] = v + 3;
        }
    }
    const s = t * 2, lap = text.length * 6;
    for (let x = 0; x < WIN_W; x++) {
        const p = (s + x) % lap, ch = text[Math.floor(p / 6)];
        for (let r = 0; r < 6; r++) if (ink(ch, p % 6, r)) out[(SCROLL_Y + r) * WIN_W + x] = 7;
    }
    return pos;
}

/** The merged palette as the machine stores it (a<<24 | b<<16 | g<<8 | r). */
export function mergedPalette() {
    const word = (f, i) => readFileSync(A + f).readUInt32LE(i * 4);
    return [0, 1, 2, 3].map((i) => word("back_pal.dat", i))
        .concat([1, 2, 3].map((i) => word("ball_pal.dat", i)), [word("font_pal.dat", 1)]);
}

export const TEXT_2005 = "HI EVERYBODY ! ULTRA OPTIMISATION RULES, EVEN FOR STUPID RECORD ! I NEVER THOUGH I COULD DISPLAY 312 SPRITES ONE YEAR AGO !  I TOTALLY REWRITE MY PC DATABUILDER TO IMPLEMENT NEW STUFF. THEN, I CHANGE THE CLEARING DATA FORMAT TO GET SOME MEMORY LEFT AND THAT IS !THAT DISK SHOULD (I HOPE) RUN ON 520-STF,MEGASTE,TT,FALCON AND EVEN CT60. GREETINGS ARE SENT TO PHANTOM, GUNSTICK AND SOTE. YOU ALL ARE COOL OPTIMIZERS !  LEONARD/OXYGENE, 17.03.2005";
export const TEXT = " ".repeat(92) + TEXT_2005 + `      ...AND THE STUPID RECORD STRIKES BACK ! ${NB} SPRITES = ${SNAKES} TIMES 312, ALL OF THEM DRAWN EVERY FRAME, FULLSCREEN WITH EVERY BORDER OPEN AND THE BACKGROUND ON THE HARDWARE SCROLL, 60 FPS ON ZIGGY. SAME SPIRIT AS 2005 : THE DATABUILDER DOES THE THINKING, THE PLAYER JUST RUNS. EACH BALL IS GENERATED CODE, 72 MOVES AND NOT ONE MASK, ONE PLANE, NOTHING COMPUTED TWICE. WHO WANTS TO BEAT IT ?  ULTRA OPTIMISATION STILL RULES !`;
