// The JOCHEN HIPPEL MUSIC DEMO screen, modelled from the original's code
// (prototypes/hippel_musicdisk_re/NOTES.md) over its ripped data only:
// tables.bin ($0678: grey, top table, bottom table, the nibble-swapped text) and
// font.bin ($1286). Used by apps/hippel_musicdisk_headless.mjs. Frame p is the
// original's frame count: the 400x280 picture as RGBA words (a<<24|b<<16|g<<8|r),
// physical row = Amiga line - 24, x = Amiga low-res hpos - $59.
import { readFileSync } from "node:fs";

const A = "apps/zig/assets/screens/hippel_musicdisk/";
const W = 400, H = 280, LINE0 = 24, TEXT_X = 72;

// $0168: control bytes $0A newline, $0B mode, $0C position; mode 0/4 = 8 px
// wide (4 = double height), 1/2 = each bit doubled (2 = double height)
function printBitmap(tables, font) {
    const text = Array.from(tables.subarray(0x60), (b) => ((b >> 4) | (b << 4)) & 255);
    const bm = new Uint8Array(0x1900);
    let mode = 2, at = 0, i = 0;
    while (text[i]) {
        const c = text[i++];
        if (c === 0x0A) { for (let k = 0; k < (mode & 6 ? 2 : 1); k++) at = ((at + 0x20) & 0xFFE0) + 0x100; continue; }
        if (c === 0x0B) { mode = text[i++]; continue; }
        if (c === 0x0C) { at = (text[i + 1] << 8) | text[i]; i += 2; continue; }
        const g = (r) => font[(c - 0x20) * 8 + r];
        if (mode === 0 || mode === 4) {
            let a = at;
            for (let r = 0; r < 8; r++) for (let k = 0; k < (mode & 4 ? 2 : 1); k++, a += 32) bm[a] = g(r);
            at += 1;
        } else {
            at = (at + 1) & ~1;
            let a = at;
            for (let r = 0; r < 8; r++) {
                let w = 0;
                for (let b = 7; b >= 0; b--) w = (w << 2) | ((g(r) >> b) & 1 ? 3 : 0);
                for (let k = 0; k < (mode & 2 ? 2 : 1); k++, a += 32) { bm[a] = w >> 8; bm[a + 1] = w & 255; }
            }
            at += 2;
        }
    }
    return (row, x) => row >= 0 && row < 200 && x >= 0 && x < 256 && ((bm[row * 32 + (x >> 3)] >> (7 - (x & 7))) & 1) === 1;
}

// $0372 x 12: 192 copper rows of 32 COLOR01 moves, base+0..15 then base+15..0
function copperRows() {
    const rows = [];
    for (let rep = 0; rep < 3; rep++)
        for (const [start, step] of [[0x000, 0x100], [0xF00, 0x010], [0xFF0, -0x100], [0x0F0, -0x010]]) {
            let base = start;
            for (let l = 0; l < 16; l++, base += step) {
                const row = [];
                for (let k = 0; k < 16; k++) row.push(base + k);
                for (let k = 15; k >= 0; k--) row.push(base + k);
                rows.push(row);
            }
        }
    return rows;
}

const rgba = (v) => (0xFF000000 | ((v & 15) * 17) << 16 | (((v >> 4) & 15) * 17) << 8 | ((v >> 8) & 15) * 17) >>> 0;

export function screenModel({ lead = 1 } = {}) {
    const tables = readFileSync(A + "tables.bin"), font = readFileSync(A + "font.bin");
    const word = (i) => tables.readUInt16BE(2 * i);
    const bit = printBitmap(tables, font);
    const rows = copperRows();
    const grey = Array.from({ length: 16 }, (_, j) => word(j));
    // $025E: per channel max(0, table - grey)
    const shade = (t, g) => [0xF00, 0x0F0, 0x00F].reduce((v, m) => v | Math.max(0, (t & m) - (g & m)), 0);
    const bar = (first, rot) => Array.from({ length: 16 }, (_, j) => rgba(shade(word(first + (((j + rot) % 16) + 16) % 16), grey[j])));
    const img = new Uint32Array(W * H);
    return {
        frame(p) {
            const top = bar(16, (p - 1) % 16), bot = bar(32, -(p % 16)); // $0298 left (a frame behind), $02AC right
            const tail = rows[(191 + p) % 192][31];
            for (let y = 0; y < H; y++) {
                const L = y + LINE0, n = L - 0x40;
                const bg = L >= 0x2F && L <= 0x3E ? top[L - 0x2F] : L >= 0x108 && L <= 0x117 ? bot[L - 0x108] : rgba(0);
                const cols = n < 192 ? rows[(n + p) % 192] : null;
                for (let x = 0; x < W; x++) {
                    let c = bg;
                    const tx = x - TEXT_X;
                    if (n >= 0 && n < 199 && tx >= 0 && tx <= 256) {
                        if (bit(n + 1, tx)) c = rgba(cols ? cols[Math.min(31, (tx + lead) >> 3)] : tail);
                        else if (bit(n, tx - 1)) c = rgba(0x888);
                    }
                    img[y * W + x] = c;
                }
            }
            return img;
        },
    };
}
