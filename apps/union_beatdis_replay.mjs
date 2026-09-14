// The Union Demo TCB1 BEAT DIS, replayed from the remake's JS in CANVAS units
// (640x400), for apps/union_beatdis_headless.mjs. Written from the sources,
// not from the scene:
//   screen.js:72-128 / screen2.js:103-166  update() and draw()
//   codef_scrolltext.js:44-174             the letter ring (no sinparam)
//   codef_core.js:243-302                  image.draw / drawTile at integer x, y
// The PNGs are read back from beatdis.bin, doubled: every picture is an exact
// 2x grid except fonts2.png's '!', whose odd canvas columns come from the
// extra tile the asset script keeps (its odd ROWS are never on an even canvas
// row, the only rows an ST pixel shows).
import { readFile } from "node:fs/promises";

export const ASSETS = "apps/zig/assets/screens/union_beatdis";
export const CW = 640, CH = 400;
export const INK = 1, BLACK = 2; // pal.dat

export async function loadAssets() {
    const bin = new Uint8Array(await readFile(`${ASSETS}/beatdis.bin`));
    let at = 0;
    const take = (w, h) => { const img = { px: bin.subarray(at, at + w * h), w, h }; at += w * h; return img; };
    const A = {
        background: take(320, 200), beatdis: take(320, 200), frame: take(320, 50), scrollback: take(576, 16),
        font: take(480, 350), sprites: take(112, 16), bangOdd: take(48, 50),
    };
    if (at !== bin.length) throw new Error(`beatdis.bin is ${bin.length} bytes, layout says ${at}`);
    A.pal = new Uint8Array(await readFile(`${ASSETS}/pal.dat`));
    A.text = await readFile(`${ASSETS}/scrolltext.txt`, "latin1");
    A.panel = (await readFile(`${ASSETS}/loader_beatdis.txt`, "latin1")).split("\n")
        .filter((l) => l.startsWith('"')).map((l) => l.slice(1, l.lastIndexOf('"')));
    A.loaderFont = new Uint8Array(await readFile("libs/zig/depackers/tex_loader/loader.raw"));
    const curve = await readFile("apps/zig/scenes/union_beatdis/curve.zig", "utf8");
    const table = (n) => curve.match(new RegExp(`pub const ${n} = \\[_\\]u16\\{([^}]*)\\}`))[1].split(",").map((v) => v.trim()).filter(Boolean).map(Number);
    A.curveX = table("X");
    A.curveY = table("Y");
    return A;
}

// A picture as the canvas holds it: canvas pixel (u, v) of a 2x-doubled image.
const doubled = (img) => ({ w: img.w * 2, h: img.h * 2, at: (u, v) => img.px[(v >> 1) * img.w + (u >> 1)] });

function glyph(A, nb) {
    const col = (nb % 10) * 48, row = Math.floor(nb / 10) * 50;
    return {
        w: 96, h: 100,
        at: (u, v) => nb === 1 && (u & 1)
            ? A.bangOdd.px[(v >> 1) * 48 + (u >> 1)]
            : A.font.px[(row + (v >> 1)) * 480 + col + (u >> 1)],
    };
}

// drawImage(pic, x, y) into the 640x400 map, clipped to [x0,x1)x[y0,y1); index 0 is transparent.
function drawImage(map, pic, x, y, clip = [0, 0, CW, CH]) {
    const [x0, y0, x1, y1] = clip;
    for (let v = Math.max(0, y0 - y); v < pic.h && y + v < Math.min(y1, CH); v++)
        for (let u = Math.max(0, x0 - x); u < pic.w && x + u < Math.min(x1, CW); u++) {
            const p = pic.at(u, v);
            if (p) map[(y + v) * CW + x + u] = p;
        }
}

const SPRITE_ORDER = ["T", "H", "E", null, "U", "N", "I", "O", "N"]; // screen2.js:28-36
const SHEET = { T: 0, H: 1, E: 2, U: 3, N: 4, I: 5, O: 6 };
const SPRITE_W = { T: 32, H: 32, E: 32, U: 32, N: 32, I: 24, O: 32 };

export function makeReplay(A, version) {
    const st = { posScrollerX: 0, posVertScrollY1: 400, posVertScrollY2: 800, spritePos: 0, scroffset: 0, letters: [] };
    // scrolltext.init(scrolltextcanvas 576x150, bitmapfont 96x100, 7, undefined, 0, mainscrollerPos = 0)
    const wide = Math.ceil(576 / 96) + 1;
    for (let i = 0; i <= wide; i++) st.letters.push({ posx: Math.ceil(wide * 96 + i * 96), ltr: A.text.charCodeAt(st.scroffset++) });
    const sprites = SPRITE_ORDER.map((k) => k && {
        w: SPRITE_W[k], h: 32,
        at: (u, v) => A.sprites.px[(v >> 1) * 112 + SHEET[k] * 16 + (u >> 1)],
    });

    // update(), then the move half of scrolltext.draw(0)
    st.update = () => {
        st.posScrollerX -= 3;
        if (st.posScrollerX < -446) st.posScrollerX = 0;
        st.posVertScrollY1 -= 4;
        if (st.posVertScrollY1 <= -400) st.posVertScrollY1 = 400;
        st.posVertScrollY2 -= 4;
        if (st.posVertScrollY2 <= -400) st.posVertScrollY2 = 400;
        st.spritePos++;
        for (const l of st.letters) {
            l.posx -= 7;
            if (l.posx <= -96) {
                l.posx = wide * 96 + (l.posx + 96);
                l.ltr = A.text.charCodeAt(st.scroffset);
                st.scroffset++;
                if (st.scroffset > A.text.length - 1) st.scroffset = 0;
            }
        }
    };

    st.paint = () => {
        const map = new Uint8Array(CW * CH).fill(BLACK); // maincanvas.fill('#000000')
        drawImage(map, doubled(A.background), 0, 0);
        drawImage(map, doubled(A.frame), 0, 302);
        const vert = [0, 0, 640, 300]; // vertscrollcanvas
        drawImage(map, doubled(A.beatdis), 0, st.posVertScrollY1, vert);
        drawImage(map, doubled(A.beatdis), 0, st.posVertScrollY2, vert);
        drawImage(map, doubled(A.scrollback), 32 + st.posScrollerX, 334, [32, 334, 32 + 576, 334 + 32]);
        const order = st.letters.map((l, j) => ({ j, posx: l.posx })).sort((a, b) => a.posx - b.posx);
        for (const { j } of order)
            drawImage(map, glyph(A, st.letters[j].ltr - 32), 32 + st.letters[j].posx, 300, [32, 300, 32 + 576, 300 + 150]);
        if (version === "512") for (let i = sprites.length - 1; i >= 0; i--) {
            const k = (st.spritePos - i * 5) % A.curveX.length; // negative: array[k] is undefined, drawImage(NaN) draws nothing
            if (k < 0 || !sprites[i]) continue;
            drawImage(map, sprites[i], A.curveX[k] * 2, A.curveY[k] * 2);
        }
        return map;
    };
    return st;
}

// The loader's last frame, halved: the panel with every letter landed
// (tex_loader.zig, checked by apps/tex_loader_fx_headless.mjs) and loader.js's
// question under it (loaderfont.print, mid-handled 16x16 glyphs).
export function promptMap(A) {
    const map = new Uint8Array(320 * 200).fill(BLACK);
    const put = (c, x, y) => {
        const g = c.charCodeAt(0) - 32;
        for (let gy = 0; gy < 8; gy++) for (let gx = 0; gx < 8; gx++)
            if (A.loaderFont[((Math.floor(g / 10) * 8) + gy) * 80 + (g % 10) * 8 + gx]) map[(y + gy) * 320 + x + gx] = INK;
    };
    A.panel.forEach((row, r) => [...row].forEach((c, col) => put(c, 80 + 8 * col, 184 - 8 * (A.panel.length - 1 - r))));
    const lines = ["ONE MEG AND DOUBLE SIDED DRIVE FOUND", "PRESS RETURN FOR THE 1/2 MEG VERSION", "ANY OTHER TO GO ON", ""];
    lines.forEach((line, i) => [...line].forEach((c, k) => {
        const cx = 328 - (16 * line.length) / 2 + k * 16, cy = 408 - 16 * (lines.length + 1) + i * 16;
        put(c, (cx - 8) / 2, (cy - 8) / 2);
    }));
    return map;
}
