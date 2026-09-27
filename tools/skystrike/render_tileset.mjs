// SKYSTRIKE's screen types drawn BY THE GAME, for the level editor's tileset
// (tools/skystrike/levels.py; docs/ports/SKYSTRIKE_LEVELS.md).
//
//   node tools/skystrike/render_tileset.mjs     (from the repo root, after a build)
//
// Each tile is what the cart's own drawing code (listing 1000-1300, from the
// SKYPIC1 / SKYPIC2 sheets and bank 8's scene table) puts on the screen for a
// type: the cart is run to the first frame of play, screen 1's type is POKEd
// (sc9 + 1, through the test door) and the plane flown there with nf = 1, so
// line 40 redraws it; the back screen (no live sprites) is taken, rows 0-175,
// in the colour registers of the moment. Types 18, 19 draw nothing and are
// refused by the importer: they get a crossed-out tile. The two mission
// markers are the game's sprites 1 (the Spitfire: start) and 119 (the HUD's
// "TGT" arrow, 740: target), from sprites.bnk, enlarged onto 64x64 tiles.
// Writes skystrike_screens.png and skystrike_markers.png into
// apps/zig/assets/screens/skystrike/levels/.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { deflateSync, crc32 } from "node:zlib";
import { session, toPlay } from "../../apps/skystrike_session.mjs";

const TW = 320, TH = 176, COLS = 6, COUNT = 36;
const SC9 = (6 << 16) + 32033; // sc9 = start(6) + 32033 (listing line 6)
const REFUSED = [18, 19];
const OUT = "apps/zig/assets/screens/skystrike/levels";

async function renderType(t) {
    const s = await session();
    await toPlay(s);
    s.set("th", 0);
    s.set("y", 20); // up in the sky: no scenery zone under the plane, so no hit, no message
    s.poke(SC9 + 1, t);
    s.set("sx", 1);
    s.set("nf", 1);
    // Line 40 (gosub 1000 : sx = s2) is over once sx is back to 0 with nf = 0:
    // taken then, before the pass goes on to flak, messages or explosions.
    let i = 0;
    for (; i < 400 && !(s.v("nf") === 0 && s.v("sx") === 0); i++) s.vbl(1);
    if (i === 400) throw new Error(`type ${t}: the redraw never finished`);
    const back = s.screen("back").slice(0, TW * TH);
    const regs = new Uint16Array(s.memory.buffer, s.demo.skyTestPtr(4), 16);
    const rgb = [...regs].map((w) => [w >> 8 & 7, w >> 4 & 7, w & 7].map((c) => Math.round(c * 255 / 7)));
    return { back, rgb };
}

function crossed() {
    const back = new Uint8Array(TW * TH);
    for (let y = 0; y < TH; y++) for (let x = 0; x < TW; x++) {
        const d = Math.abs(x * TH - y * TW) < 3 * TW || Math.abs((TW - x) * TH - y * TW) < 3 * TW;
        back[y * TW + x] = d || x < 3 || y < 3 || x >= TW - 3 || y >= TH - 3 ? 1 : 0;
    }
    return { back, rgb: [[40, 0, 0], [255, 60, 60]] };
}

// A STOS bank sprite (1-based n): rows of colour indices, -1 = transparent
// (mask words first, a set bit = transparent; then 4 plane words per 16 px).
function sprite(bank, n) {
    const lo = 4 + bank.readUInt32BE(4), e = lo + (n - 1) * 8;
    const off = lo + bank.readUInt32BE(e), w = bank[e + 4], h = bank[e + 5];
    const rows = [];
    for (let y = 0; y < h; y++) {
        const row = [];
        for (let x = 0; x < w; x++) {
            const m = bank.readUInt16BE(off + (y * w + x) * 2);
            const p = off + w * h * 2 + (y * w + x) * 8;
            for (let bit = 15; bit >= 0; bit--) {
                let c = 0;
                for (let k = 0; k < 4; k++) c |= (bank.readUInt16BE(p + k * 2) >> bit & 1) << k;
                row.push(m >> bit & 1 ? -1 : c);
            }
        }
        rows.push(row);
    }
    return rows;
}

// Marker tiles (RGBA): each sprite scaled up by a whole factor, centred on its 64x64 tile.
async function markers(rgb) {
    const bank = await readFile("apps/zig/assets/screens/skystrike/sprites.bnk");
    const M = 64, out = Buffer.alloc(2 * M * M * 4);
    [1, 119].forEach((n, i) => {
        const rows = sprite(bank, n), k = Math.floor(M / Math.max(rows.length, rows[0].length));
        const ox = i * M + (M - rows[0].length * k >> 1), oy = M - rows.length * k >> 1;
        rows.forEach((row, y) => row.forEach((c, x) => {
            if (c < 0) return;
            for (let d = 0; d < k * k; d++)
                out.set([...rgb[c], 255], ((oy + k * y + Math.floor(d / k)) * 2 * M + ox + k * x + d % k) * 4);
        }));
    });
    return png(2 * M, M, out, 4);
}

function png(w, h, rgb, bpp = 3) {
    const chunk = (type, data) => {
        const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
        const td = Buffer.concat([Buffer.from(type), data]);
        const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td) >>> 0);
        return Buffer.concat([len, td, crc]);
    };
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = bpp === 4 ? 6 : 2;
    const raw = Buffer.alloc(h * (w * bpp + 1));
    for (let y = 0; y < h; y++) rgb.copy(raw, y * (w * bpp + 1) + 1, y * w * bpp, (y + 1) * w * bpp);
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr),
        chunk("IDAT", deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]);
}

const W = COLS * TW, H = COUNT / COLS * TH;
const sheet = Buffer.alloc(W * H * 3);
let playRgb = null;
for (let t = 0; t < COUNT; t++) {
    const { back, rgb } = REFUSED.includes(t) ? crossed() : await renderType(t);
    if (!REFUSED.includes(t)) playRgb = rgb;
    const ox = (t % COLS) * TW, oy = Math.floor(t / COLS) * TH;
    for (let y = 0; y < TH; y++) for (let x = 0; x < TW; x++) {
        const c = rgb[back[y * TW + x]];
        sheet.set(c, ((oy + y) * W + ox + x) * 3);
    }
    process.stdout.write(`${t} `);
}
await mkdir(OUT, { recursive: true });
await writeFile(`${OUT}/skystrike_screens.png`, png(W, H, sheet));
await writeFile(`${OUT}/skystrike_markers.png`, await markers(playRgb));
console.log(`\n${OUT}/skystrike_screens.png: ${W}x${H}, ${COUNT} tiles of ${TW}x${TH}`);
