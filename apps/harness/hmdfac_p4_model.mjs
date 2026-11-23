// The HMDFAC harness's model of phase 4 (cart 105), from the 68000 code
// ($1119a: $111aa, $10d66, $10e48, $13a74) and the RAM rips, not from the Zig:
// two ST pages in their own planar layout, the dot figure's ring, the wave
// scroller's slabs. Pinned to the original's drawn pages (hmdfac_original.json).
import { readFile } from "node:fs/promises";

const A = "apps/zig/assets/screens/hmdfac/";
const u16s = async (f) => { const b = await readFile(A + f); return Array.from({ length: b.length / 2 }, (_, i) => b.readUInt16LE(2 * i)); };
const T = await u16s("rows.raw"), WAVE = await u16s("wave.raw");
const FONT = await readFile(A + "font_machine.bin"), CMAP = await readFile(A + "charmap.bin"), TEXT = await readFile(A + "text.raw");
const PAGE = 32000;

export function create() {
    const s = {
        pages: [new Uint8Array(PAGE), new Uint8Array(PAGE)], drawn: 0,
        ring: new Uint16Array(8002), head: 0, stream: 0, plane: 0, toggle: 0,
        slabs: new Uint8Array(4 * 0x540), steps: new Uint16Array(42), wi: 0, last: 100, base: 0,
        shift: 16, glyph: CMAP[0x20] * 64, col: 0, slab: 0, half: 0, ci: 0,
    };
    s.ring[4000] = 0x7d00;
    for (let i = 0; i < 0xc81; i++) insert(s);
    return s;
}
function insert(s) {
    if (s.stream >= 5040) s.stream = 0;
    const d = (T[s.stream++] * 160) & 0xffff;
    if (s.head === 0) s.head = 4000;
    s.head--;
    s.ring[s.head + 4000] = d; s.ring[s.head] = d;
    s.ring[s.head + 4001] = (s.ring[s.head + 4001] - d) & 0xffff;
    s.ring[s.head + 1] = (s.ring[s.head + 1] - d) & 0xffff;
}
function clearBox(s, pg) {
    s.toggle ^= 1;
    if (!s.toggle) s.plane = (s.plane + 2) % 8;
    for (let y = 0; y < 200; y++) for (let g = y ? 4 : 5; g <= 16; g++) { const a = y * 160 + g * 8 + s.plane; pg[a] = 0; pg[a + 1] = 0; }
}
function wave(s) {
    s.steps.copyWithin(1, 0, 41);
    s.wi = s.wi + 1 >= 189 ? 0 : s.wi + 1;
    const now = WAVE[s.wi], d1 = (s.last - now + 100) & 0xffff;
    s.last = now;
    s.steps[0] = (d1 * 160 - 0x3e7c) & 0xffff;
    s.base = now * 160 - 0x320;
}
const sx = (v) => (v & 0x8000 ? v - 0x10000 : v);
function scroller(s, pg) {
    let at = s.slab * 0x540 + s.col;
    for (let r = 0; r < 16; r++, at += 0x54) {
        const w = (FONT[s.glyph + 2 * r] << 8) | FONT[s.glyph + 2 * r + 1];
        const lo = s.shift < 16 ? w >> s.shift : 0, hi = (w << (16 - s.shift)) & 0xffff;
        for (const o of [0, 0x2a]) { s.slabs[at + o] |= lo >> 8; s.slabs[at + o + 1] |= lo & 255; s.slabs[at + o + 2] = hi >> 8; s.slabs[at + o + 3] = hi & 255; }
    }
    const put = (a, v) => { if (a >= 0 && a < PAGE) pg[a] = v; };
    const column = (a, src) => {
        put(a - 160, 0); put(a - 320, 0);
        for (let k = 0; k < 16; k++) put(a + k * 160, s.slabs[src + k * 0x54]);
        put(a + 2560, 0); put(a + 2720, 0);
    };
    let a5 = 0x142 + s.base, src = s.slab * 0x540 + 4 + s.col;
    for (let j = 0; j < 20; j++, src += 2) {
        column(a5, src); a5 += sx(s.steps[2 * j]);
        column(a5 - 3, src + 1); a5 += sx(s.steps[2 * j + 1]);
    }
    s.slab++; s.shift -= 4;
    if (s.shift > 0) return;
    s.shift = 16; s.slab = 0; s.col = s.col + 2 === 0x2a ? 0 : s.col + 2;
    s.half ^= 0xffff;
    if (s.half) { s.glyph += 0x20; return; }
    const c = TEXT[++s.ci];
    if (c === 0xff) s.ci = 0;
    s.glyph = CMAP[c] * 64;
}
function plot(s, pg) {
    insert(s);
    let a0 = s.plane + 0x20;
    for (let i = 0; i < 0xc81; i++) {
        a0 += sx(s.ring[s.head + i]);
        const x = T[i], a = a0 + (x >> 4) * 8 + ((x & 15) >> 3);
        if (a >= 0 && a < PAGE) pg[a] |= 0x80 >> (x & 7);
    }
}
/// One $1119a frame; returns the page drawn.
export function step(s) {
    const pg = s.pages[s.drawn];
    clearBox(s, pg); wave(s); scroller(s, pg); plot(s, pg);
    s.drawn ^= 1;
    return pg;
}
/// A planar page (rows 0..199) -> 320x200 palette indices.
export function chunky(pg) {
    const out = new Uint8Array(320 * 200);
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const a = y * 160 + (x >> 4) * 8 + ((x >> 3) & 1), bit = 0x80 >> (x & 7);
        out[y * 320 + x] = (pg[a] & bit ? 1 : 0) | (pg[a + 2] & bit ? 2 : 0) | (pg[a + 4] & bit ? 4 : 0) | (pg[a + 6] & bit ? 8 : 0);
    }
    return out;
}
