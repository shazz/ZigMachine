// A second, independent implementation of NUCLEUS's GfA Punch Raytrace (ST Magazine; the
// listing is in apps/zig/scenes/raytrace/gfa.zig's header), in JavaScript doubles, written
// from the listing and not from the cart's Zig. apps/harness/gfa_punch_headless.mjs compares the
// cart's key-4 picture with it pixel for pixel.
//
// GFA's semantics kept: TRUE = -1 (`truth`, and `--break true` makes it +1), a float passed
// to an integer parameter (a%, b%, c%, x&, z&) is ROUNDED (CINT), INT is the floor, the
// bracketed DIV()/MOD() work in integers, and RAND(10) is 0..9 from the cart's seeded
// generator (GFA's own generator is unknown; the order of its calls is the listing's).
import { readFileSync } from "node:fs";

export const PALETTE = [0x000, 0x100, 0x200, 0x300, 0x400, 0x500, 0x600, 0x700,
    0x710, 0x720, 0x731, 0x741, 0x751, 0x761, 0x771, 0x772];
export const TITLE = " NUCLEUS's GfA Punch Raytrace";
export const SEED = 0x6fa1991;

const FONT = readFileSync(new URL("../../libs/zig/assets/fonts/system_font_atari_1bit.raw", import.meta.url));

// The cart's RAND (gfa.zig Rand): a 32-bit LCG, RAND(n) = the high half scaled to 0..n-1.
export function rand(seed) {
    let s = seed >>> 0;
    return (n) => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return ((s >>> 16) * n) >>> 16; };
}

const cint = (v) => Math.sign(v) * Math.round(Math.abs(v)); // half away from zero
const INT = Math.floor;

// The ST screen as colour indices: the title PRINTed at (0, 0), the rest colour 0.
export function screenWithTitle() {
    const scr = new Uint8Array(320 * 200);
    for (let k = 0; k < TITLE.length; k++) for (let r = 0; r < 8; r++) for (let c = 0; c < 8; c++)
        if (FONT[TITLE.charCodeAt(k) * 64 + r * 8 + c]) scr[r * 320 + k * 8 + c] = 15;
    return scr;
}

// Runs the listing (lines 5..17) on `scr`; `truth` is GFA's TRUE (-1; +1 for the mutant).
export function run(scr, truth = -1, seed = SEED) {
    const R = rand(seed), T = (b) => (b ? truth : 0);
    const fa = (a, b, c, d, e, f, am) => {
        a = cint(a); b = cint(b); c = cint(c);
        return Math.min(1, am + Math.max(0, (a * (80 - d) + b * (80 - e) + c * (-80 - f)) /
            (Math.sqrt(a * a + b * b + c * c) * Math.sqrt((80 - d) ** 2 + (80 - e) ** 2 + (-80 - f) ** 2))));
    };
    const fb = (x, z) => 100 - Math.sqrt(cint(x) ** 2 + (cint(z) - 148) ** 2);
    const fd = (v) => INT(v) - T(Math.abs(v - INT(v)) >= Math.abs(v - INT(v + 1)));
    const fc = (v) => { const d = fd(v * 159); return Math.max(0, Math.trunc(d / 10) + T(R(10) > d % 10)); };
    const pset = (x, y, c) => { scr[y * 320 + x] = c; };
    const ptst = (x, y) => scr[y * 320 + x];
    for (let y = -99; y <= 53; y++) for (let x = -159; x <= 159; x++) {
        const A = x * x + y * y + 22500, B = 300 * y * y - 9000 * x - 2700000;
        const C = 22500 * (x * x + y * y) - 1350000 * x + 300000;
        if (B * B - 4 * A * C > 0) {
            const z = (-B - Math.sqrt(B * B - 4 * A * C)) / 2 / A;
            const px = (x * z) / 150 + x, py = (y * z) / 150 + y;
            pset(x + 159, 99 - y, fc(fa(px - 30, py, -60 + z, px, py, z, 0.15)));
        } else if (y < 0) {
            const z = -14850 / y - 150, px = (x * z) / 150 + x;
            const tex = T(ptst(INT(px / 2 + 10000) % 63, 15 - (INT(z / 2) % 16)) !== 0) * 0.3;
            pset(x + 159, 99 - y, fc(Math.max(0, tex + T(fb(px, z) >= 0) * 0.5 + fa(0, 1, 0, px, -99, z, 0.09))));
        } else if (y > 0 && y <= 24) pset(x + 159, 99 - y, fc(1 - Math.min(22, y) / 22));
    }
    return scr;
}

// ST colour word -> 8 bits a channel, c * 255 / 7 (as the ST ports do).
export const stRgb = (w) => [(w >> 8) & 7, (w >> 4) & 7, w & 7].map((c) => Math.floor((c * 255) / 7));

export function toRgb(scr) {
    const rgb = new Uint8Array(320 * 200 * 3);
    for (let i = 0; i < scr.length; i++) rgb.set(stRgb(PALETTE[scr[i] & 15]), i * 3);
    return rgb;
}
