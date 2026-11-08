// The two FULLSCREEN parts of NATRIUM's ZIG mode (the dot tunnel, the chrome twister),
// re-derived for apps/rno_natrium_zig_full.mjs from the ripped assets and fixtrig only,
// never from the cart's own tables. Window pixel (x, y) of the 400x280 overscan plane.
import { W, H, OX, OY, asset, fsin } from "./rno_natrium_zig_model.mjs";

const DOT = asset("dot_tex.bin"), CHROME = asset("chrome.bin"), GREET = asset("greet.bin");
const mulsh16 = (a, b) => Math.floor((a * b) / 65536);

// ---- dots (zig_dots.zig) ---------------------------------------------------------
/** The dot map's (u, v) by the original table's formula, in float: U8 = 128 + angle
 *  128/pi (0 to the left), V8 = 128.75 + 2048 / r px; u = U8 & 15, v = V8 + the octant
 *  term ((U8 >> 4) & 7) * 8 ($C2DC). Both U8 roundings are returned when U8 is near a
 *  half-integer, so a sector edge may go either way. null in the hole (r < 16 px). */
export function dotUV(x, y) {
    const dx = x + 0.5 - W / 2, dy = y + 0.5 - H / 2, r = Math.hypot(dx, dy);
    if (r < 16) return null;
    const u8 = ((128 + Math.atan2(dy, dx) * 128 / Math.PI) % 256 + 256) % 256, v8 = 128.75 + 2048 / r;
    const cands = new Set([Math.floor(u8 + 0.5) & 255, Math.floor(u8 + 0.4) & 255, Math.floor(u8 + 0.6) & 255]);
    return [...cands].map((u) => [u & 15, ((v8 + ((u >> 4) & 7) * 8) % 32 + 32) % 32]);
}

/** Texel (u, vq) of the 32x128 dot texture: columns 16..31 the blob inverted. */
export const dotTexel = (u, vq) => (DOT[(vq >> 2) * 16 + (u & 15)] & 1) ^ (u >= 16 ? 1 : 0);

/** The scroll at time t (Q10 VBLs): f & 31 in quarter texels. */
export const dotVoff = (t) => (t >> 8) & 127;

/** The ST line a window line shows: the window's own, or lines 0/1 (198/199) carried
 *  out across the top (bottom) border by parity; columns clamp likewise. */
export const stLine = (y) => (y < OY ? y & 1 : y >= OY + 200 ? 198 + (y & 1) : y - OY);
export const stCol = (x) => Math.min(Math.max(x - OX, 0), 319);

// ---- twister (zig_twist.zig) ----------------------------------------------------------
export const BAR = 90, CENTRE = 95, AMP = 82, GREET_X = 88, GREET_Y = [1, H - 9];
const IDX = 4194304;
const STRIP = new Uint8Array(512 * 64);
for (let r = 0; r < 64; r++)
    for (let x = 0; x < 512; x++) {
        let pen = 0;
        for (let p = 0; p < 4; p++) pen |= ((CHROME[r * 256 + p * 64 + (x >> 3)] >> (7 - (x & 7))) & 1) << p;
        STRIP[r * 512 + x] = pen;
    }

export const twistTop = (t) => CENTRE + mulsh16(fsin(t * (4 << 12)), AMP);

/** The strip column of every window column at time t: 100 groups of 4 px, group k the
 *  original's i = k - 10, angle g for 2 px and g + pass - 3 for the next 2. */
export function twistColumns(t) {
    const cols = new Int32Array(W);
    for (let k = 0; k < W / 4; k++) {
        const i = k - 10, a1 = t * (7 << 11) + 2 * i * IDX;
        const a = fsin(a1) >> 8, b = fsin(a1 + IDX) >> 8, c = fsin(-t * (2 << 12) + i * IDX) >> 8;
        const g = (a + c) & 63, g2 = (g + ((b - a + 3) & 7) - 3 + 64) & 63;
        for (let p = 0; p < 4; p++) cols[4 * k + p] = (p < 2 ? g : g2) * 8 + ((4 * k + p) & 7);
    }
    return cols;
}

/** The greeting pixel of slot n at (gx, row r): 1 = colour 15, 0 = colour 0. */
const greetBit = (n, r, gx) => (GREET[(n & 15) * 0xe0 + r * 28 + (gx >> 3)] >> (7 - (gx & 7))) & 1;

/** The window at time t and `counter`: a function (x, y) -> pen. */
export function twistModel(t, counter) {
    const top = twistTop(t), cols = twistColumns(t), n = Math.floor((counter - 0x1200) / 0x60);
    const shown = [n - (n & 1), n - 1 + (n & 1)]; // the last even slot on top, the last odd at the bottom
    return (x, y) => {
        if (y >= top && y < top + BAR) return STRIP[Math.floor(((y - top) * 64) / BAR) * 512 + cols[x]];
        for (const e of [0, 1]) {
            const r = y - GREET_Y[e];
            if (r >= 0 && r < 8 && x >= GREET_X && x < GREET_X + 224 && shown[e] >= 0) return greetBit(shown[e], r, x - GREET_X) ? 15 : 0;
        }
        return 15;
    };
}
