// The Union Demo remake's screens/L16/screen.js, replayed from its own numbers in
// canvas units and sampled on the port's grid: plane pixel (X, Y) = canvas
// (2X + 16, 2Y + 6). Written from the source, not from the scene, so the headless
// check (union_l16_headless.mjs) catches any drift in a table, step or rounding.
//
// Canvas resampling, as libs/zig/effects/chrome_draw.zig, measured against Chrome
// running screen.js (tools/chrome_capture.mjs; 0 px wrong at 36 frames): y is a
// float32 first; an unscaled drawImage at a fractional y draws the rows whose
// centre is inside, fy < r+0.5 <= fy+h; row r blends source rows floor(r-fy) and
// +1 (from the part's first row, clamped to the whole image) with the fraction
// truncated to 16ths, (a*(16-w) + b*w) >> 4 per premultiplied channel.
export const W = 400, H = 280, CROP_X = 16, CROP_Y = 6;
const FONT_W = 256, FONT_H = 128, BOB_W = 16, BOB_H = 17;

/// l16.bin's layout (union_l16_assets.py); curve.txt; the scrolltext.
export function loadAssets(bin, palPicture, palFont, curveTxt, text) {
    let at = 0;
    const take = (n) => { const s = bin.subarray(at, at + n); at += n; return s; };
    const A = {
        picture: take(W * H), bob: take(BOB_W * BOB_H), font: take(FONT_W * FONT_H),
        raster: take(304 * 3), water: take(408 * 3), palPicture, palFont, text,
    };
    if (at !== bin.length) throw new Error(`l16.bin is ${bin.length} bytes, layout says ${at}`);
    const table = (name) => curveTxt.split("\n").find((l) => l.startsWith(name + " = ")).slice(name.length + 3).split(",").map(Number);
    A.curveX = table("spritePosX"); A.curveY = table("spritePosY");
    return A;
}

// the tap: which source rows canvas row r shows of rows [py0, py0+ph) of an image ih tall drawn at y
function tap(r, y, py0, ph, ih) {
    const fy = Math.fround(y);
    if (!(fy < r + 0.5 && r + 0.5 <= fy + ph)) return null;
    const v = r - fy, v0 = Math.floor(v);
    const clamp = (s) => Math.min(Math.max(s, 0), ih - 1);
    return { a: clamp(py0 + v0), b: clamp(py0 + v0 + 1), w: Math.floor((v - v0) * 16) };
}
const mix = (ca, cb, w) => [0, 1, 2].map((k) => (ca[k] * (16 - w) + cb[k] * w) >> 4);

export function makeOriginal(A, mainscrollerPos = 0) {
    // init() + onResetEvent(): scrolltext.init(..., jsApp.mainscrollerPos)
    const wide = Math.ceil(572 / 32) + 1;
    let scroffset = mainscrollerPos;
    const letters = [];
    for (let i = 0; i <= wide; i++) letters.push({ posy: Math.ceil(wide * 32 + i * 32), ltr: A.text.charCodeAt(scroffset++ % A.text.length) });
    scroffset %= A.text.length;
    const st = { spritePos: 0, rasterpos: 165, waterrasterpos: 190 - 204, frames: 0 };
    st.scroffset = () => scroffset; // what update() copies into jsApp.mainscrollerPos

    // update(), then the move at the top of scrolltext.draw()
    st.step = () => {
        st.spritePos++;
        st.waterrasterpos += 1.5;
        if (st.waterrasterpos > 190) st.waterrasterpos = 190 - 204;
        st.rasterpos -= 1.8;
        if (st.rasterpos < 165 - 304 / 2) st.rasterpos = 165;
        for (const l of letters) {
            l.posy -= 1.8;
            if (l.posy <= -32) {
                l.posy = wide * 32 + (l.posy + 32);
                l.ltr = A.text.charCodeAt(scroffset);
                scroffset++;
                if (scroffset > A.text.length - 1) scroffset = 0;
            }
        }
        st.frames++;
    };

    const gradient = (rows, r, y) => {
        const t = tap(r, y, 0, rows.length / 3, rows.length / 3);
        return t ? mix(rows.subarray(t.a * 3, t.a * 3 + 3), rows.subarray(t.b * 3, t.b * 3 + 3), t.w) : [0, 0, 0];
    };
    const ink = (i) => [A.palFont[i * 4], A.palFont[i * 4 + 1], A.palFont[i * 4 + 2]];

    // draw(): the frame as RGB, W x H
    st.draw = () => {
        const out = new Uint8Array(W * H * 3);
        const bx = 70 + 2 * A.curveX[st.spritePos % A.curveX.length] - 16;
        const by = 20 + 2 * A.curveY[st.spritePos % A.curveY.length] - 16;
        for (let y = 0; y < H; y++) {
            const r = 2 * y + CROP_Y;
            const raster = gradient(A.raster, r, st.rasterpos), water = gradient(A.water, r, st.waterrasterpos);
            for (let x = 0; x < W; x++) {
                const cx = 2 * x + CROP_X;
                let c;
                const bc = cx - bx, br = r - by;
                const bi = bc >= 0 && bc < 32 && br >= 0 && br < 33 ? A.bob[(br / 2) * BOB_W + bc / 2] : 0;
                const pi = bi || A.picture[y * W + x];
                if (pi) c = [A.palPicture[pi * 4], A.palPicture[pi * 4 + 1], A.palPicture[pi * 4 + 2]];
                else if (cx >= 736 && cx < 768) c = scroller(r, cx - 736);
                else if (cx >= 340 && cx < 500) c = raster;
                else if (cx >= 20 && cx < 100) c = water;
                else c = [0, 0, 0];
                out.set(c, (y * W + x) * 3);
            }
        }
        return out;
    };

    function scroller(r, c) {
        for (const l of letters) {
            const nb = l.ltr - 32;
            const t = tap(r, l.posy, Math.floor(nb / 16) * 32, 32, FONT_H);
            if (!t) continue;
            const sx = (nb % 16) * 16 + c / 2;
            return mix(ink(A.font[t.a * FONT_W + sx]), ink(A.font[t.b * FONT_W + sx]), t.w);
        }
        return [0, 0, 0];
    }
    return st;
}
