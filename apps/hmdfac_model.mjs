// The HMDFAC harness's own model of the original machine (cart 105), written
// from the 68000 code and the RAM rips, not from the Zig: the cube's exact
// projection, the $1047e edge walk and $bc08 span fill (checked against the
// original's drawn pages: hmdfac_original.json), the Timer B chain's laser
// lines and split palette, the opening's screen-address bob; phase 4 is
// hmdfac_p4_model.mjs. apps/hmdfac_headless.mjs drives it.
import { readFile } from "node:fs/promises";

const A = "apps/zig/assets/screens/hmdfac/";
const raw = (f) => readFile(A + f);
const words = async (f) => { const b = await raw(f); return Array.from({ length: b.length / 2 }, (_, i) => b.readUInt16LE(2 * i)); };
export const R = {
    logo: await raw("logo.raw"), bandA: await raw("band_a.raw"), bandB: await raw("band_b.raw"),
    SINE: await words("sine.blob"), QUEUE: await words("queue.raw"),
    BOOT: await words("boot_pal.raw"), ART: await words("art_pal.raw"), PAL4: await words("pal4.raw"),
    BAND: await words("band_pal.raw"), LASER: await words("laser.raw"), BOB: await words("bob.raw"),
};
const gun = (n) => ((((n & 7) << 1) | ((n >> 3) & 1)) * 16);
export const st = (w) => (0xFF000000 | (gun(w) << 16) | (gun(w >> 4) << 8) | gun(w >> 8)) >>> 0;

// ---------------- timeline (frames from the first loop VBL) ------------------
export const OPEN_END = 193, FLASH_END = 205, HOLD_END = 209;
export const CUBE1_END = 329, CUBE2_END = 579, CUBE_END = 707, P4_START = 724;
const FLASH_C0 = [0x777, 0xeee, 0x666, 0xddd, 0x555, 0xccc];
export const laserCount = (f) => (f < OPEN_END ? f : f < HOLD_END ? OPEN_END : OPEN_END + f - HOLD_END);
export const bobLines = (f) => (f < OPEN_END ? R.BOB[f < 192 ? f : 0] / 160 : 0);

// ---------------- 68k word maths and the cube ---------------------------------
const s16 = (v) => { const u = ((v % 65536) + 65536) % 65536; return u >= 32768 ? u - 65536 : u; };
const asr = (v, n) => Math.floor(v / 2 ** n);
const divs = (a, b) => { if (b === 0) return [a, false]; const q = Math.trunc(a / b); return q < -32768 || q > 32767 ? [a, false] : [q, true]; };
const VERTS = [[-136, -136, 120], [-136, 120, 120], [120, 120, 120], [120, -136, 120], [-56, 40, -56], [40, 40, -56], [40, -56, -56], [-56, -56, -56]];
const FACES = [[[6, 5, 4, 7], 15], [[0, 1, 2, 3], 2], [[3, 2, 5, 6], 13], [[7, 4, 1, 0], 14], [[1, 4, 5, 2], 7], [[7, 0, 3, 6], 6]];
export function project(w) {
    const sw = (c, o) => s16(R.SINE[(c >> 1) + o]);
    const coA = sw(w.ca, 0), sA = sw(w.ca, 360), coB = sw(w.cb, 0), sB = sw(w.cb, 360), coC = sw(w.cc, 0), sC = sw(w.cc, 360);
    const t4 = asr(coC * sB, 9), t7 = asr(sC * sB, 9);
    const m = [-sB, asr(coB * sA, 9), asr(coB * coA, 9), asr(coC * coB, 9), asr(t4 * sA, 9) - asr(sC * coA, 9),
        asr(t4 * coA, 9) + asr(sC * sA, 9), asr(sC * coB, 9), asr(t7 * sA, 9) + asr(coC * coA, 9), asr(t7 * coA, 9) - asr(coC * sA, 9)].map(s16);
    return VERTS.map(([x, y, z]) => {
        const dist = s16((w.camera & 0xffff) - s16(-asr(x * m[0] + y * m[1] + z * m[2], 8)));
        return [s16(divs(x * m[3] + y * m[4] + z * m[5], dist)[0] + w.qx), s16(divs(x * m[6] + y * m[7] + z * m[8], dist)[0] + w.qy)];
    });
}
// $1047e: b = (x0, y0), a = (x1, y1); x*8 in a split 16.16 register, addx with X = 1 at entry.
function edge(T, x0, y0, x1, y1) {
    if (y1 === y0) return;
    let rows = T.l;
    if (y1 < y0) { [x0, y0, x1, y1] = [x1, y1, x0, y0]; rows = T.r; }
    if (y0 > 199) return;
    if (y0 < 0) { if (y1 < 0) return; x0 = s16(-(s16(divs((x1 - x0) * y1, y1 - y0)[0]) - x1)); y0 = 0; }
    if (y1 >= 199) { x1 = s16(divs((x1 - x0) * (199 - y0), y1 - y0)[0] + x0); y1 = 199; }
    x0 = s16(x0 * 8); x1 = s16(x1 * 8);
    const dx = s16(x1 - x0), dy = y1 - y0;
    if (dy <= 0) return;
    const d4 = Number(BigInt.asUintN(32, BigInt(s16(divs(dx * 32, dy)[0])) * 2048n));
    const frac = d4 & 0xffff, ip = d4 >>> 16;
    if (!frac) { let v = x0; for (let y = y0; y < y1; y++) { rows[y] = v; v = s16(v + s16(ip)); } return; }
    let d0 = ((((frac + 0x8000) & 0xffff) << 16) | (x0 & 0xffff)) >>> 0, X = 1;
    const add = ((frac << 16) | ip) >>> 0;
    for (let y = y0; y < y1; y++) { rows[y] = s16(d0 & 0xffff); const r = d0 + add + X; X = r >= 2 ** 32 ? 1 : 0; d0 = r % 2 ** 32; }
}
export function drawCube(page, p, T) {
    for (const [q, ink] of FACES) {
        const [a, b, c] = [p[q[0]], p[q[1]], p[q[2]]];
        if ((b[1] - a[1]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[1] - a[1]) >= 0) continue;
        for (let i = 0; i < 4; i++) { const va = p[q[i]], vb = p[q[(i + 1) % 4]]; edge(T, vb[0], vb[1], va[0], va[1]); }
        const ys = q.map((v) => p[v][1]);
        const ylo = Math.max(Math.min(...ys, 200), 0), yhi = Math.min(Math.max(...ys, 0), 199);
        if (ylo > 198 || yhi < 1) continue;
        for (let y = ylo; y < yhi; y++) {
            const xl = T.l[y] >> 3, xr = T.r[y] >> 3;
            if ((xr >> 4) < (xl >> 4)) break;
            for (let x = Math.max(xl, 0); x < Math.min(xr, 320); x++) page[y * 320 + x] = ink;
        }
    }
}

// ---------------- the plate pages -------------------------------------------
export function artPage(withBandA) {
    const page = new Uint8Array(320 * 249);
    page.set(R.logo);
    if (withBandA) page.set(R.bandA, 194 * 320);
    return page;
}
/// Phase 4's plate: band B from page row 199, over it the planar page's
/// rows 0..198 as indices (null = the precalc frames: band B alone).
export function p4Page(ch) {
    const page = new Uint8Array(320 * 249);
    page.set(R.bandB.subarray(0, 320 * 50), 199 * 320); // band B's last row lies below the plate
    if (ch) page.set(ch.subarray(0, 320 * 199));
    return page;
}

// ---------------- the composite ------------------------------------------------
const PW = 400, PH = 280, BUF_H = 312, AX = 40, AY = 15;
const stripe = (lead, n, base) => Array.from({ length: PW }, (_, x) => base + Math.min(Math.floor((x + lead) / 12), n));
const TOP = stripe(43, 37, 16), BOT = stripe(47, 36, 60);
/// The frame as the machine composites it: page = the plate's 320x249 indices,
/// st = { f, popped }. Bottom border rows below the plate show colour 0.
export function composite(page, { f, popped }) {
    const off = bobLines(f), band = f >= CUBE_END;
    const buf = new Uint8Array(PW * BUF_H);
    for (let y = 0; y < 249; y++) buf.set(page.subarray(y * 320, y * 320 + 320), (AY + y) * PW + AX);
    if (band) buf.set(R.bandB.subarray(320 * 50), (AY + 249) * PW + AX);
    const lay = (row, s) => { for (let x = 0; x < PW; x++) if (!buf[(off + row) * PW + x]) buf[(off + row) * PW + x] = s[x]; };
    lay(AY + 2, TOP); lay(AY + 196, BOT);
    if (!buf[(off + AY + 3) * PW]) buf[(off + AY + 3) * PW] = 100;
    const flash = f >= OPEN_END && f < HOLD_END;
    const c0 = flash ? (f < FLASH_END ? FLASH_C0[(f - OPEN_END) >> 1] : 0xccc) : null;
    const [T, B] = flash ? [R.ART, R.ART] : f < CUBE1_END ? [R.ART, R.BOOT] : f < CUBE_END ? [R.ART, R.ART] : [R.PAL4, R.BAND];
    const pal = (w, pop) => { const p = w.map(st); if (c0 !== null) p[0] = st(c0); if (pop) p[0] = st(0x711); return p; };
    const first = pal(B, popped && !flash), top = pal(T), bot = pal(B);
    const ext = new Uint32Array(256);
    const n = laserCount(f), t = n % 86, b = (n + 39) % 86;
    for (let k = 1; k <= 37; k++) ext[16 + k] = st(c0 ?? R.LASER[t + k - 1]);
    for (let k = 1; k <= 36; k++) ext[60 + k] = st(c0 ?? R.LASER[b + k - 1]);
    ext[100] = st(c0 ?? 0);
    const out = new Uint32Array(PW * 2 * PH);
    for (let y = 0; y < PH; y++) {
        const p = y < AY + 3 ? first : y < AY + 197 ? top : bot;
        for (let x = 0; x < PW; x++) {
            const i = buf[(y + off) * PW + x], c = i < 16 ? p[i] : ext[i];
            out[y * 800 + 2 * x] = c; out[y * 800 + 2 * x + 1] = c;
        }
    }
    return out;
}
export const fnv = (bytes) => { let h = 0x811c9dc5; for (const v of bytes) h = Math.imul(h ^ v, 0x01000193) >>> 0; return "0x" + h.toString(16).padStart(8, "0"); };
