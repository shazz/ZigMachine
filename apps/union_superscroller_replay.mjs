// The Union Demo TCB2 SUPERSCROLLER (screens/superscroller/screen.js), replayed
// in JS at 320x200 for apps/union_superscroller_headless.mjs. It follows
// screen.js and codef_scrolltext.js, not the scene, and reads only the converted
// assets (superscroller.bin, see tools/private_tools/union_superscroller_assets.py).
//
// Per frame, as melonJS runs it: update(), then draw().
//   update  posVertScrollY1 -= 3.35, back to 0 once <= -399; Y2 = Y1 + 398,
//           Y3 = Y2 + 398; each of the 5 raster copies -= 2, to 668 once <= -167
//   draw    black; back.png at Y1, Y2, Y3; the scroller (speed 7, 384x380 tiles,
//           4 letters) into a 640x374 canvas, 'source-atop' rasters.png at the 5
//           copies, that canvas at (0, 14); overlay.png at Y1, Y2
//
// The ST screen shows canvas pixel (2x, 2y). Y1 is fractional, and Chrome draws
// a fractional-y image the legacy Skia way, measured on the remake's own frames
// (0 px off on 29 Chrome frames): the translate is a float32; canvas row cy is
// drawn only when its centre is inside (fy < cy + 0.5 <= fy + h); it samples
// rows floor(cy - fy) and the next, clamped to the image, weighted by the top 4
// bits of the fraction, (a*(16-w) + b*w) >> 4 on premultiplied colour; src-over
// is s + (d * (256 - sa)) >> 8.
export const W = 320, H = 200;
export const SPEED = 7, TILE_W = 384, SCROLL_H = 374, SCROLL_Y = 14;
export const GLYPHS = 60, FIRST_CHAR = 32, SAMPLED_ROWS = 187;
export const RASTER_ROWS = 168, RASTER_COPIES = 5, RASTER_STEP = 167;
export const BACK_H = 400, BACK_STEP = 398, BACK_SPEED = 3.35;
const LETTERS = Math.ceil(640 / TILE_W) + 1 + 1; // wide + 1: letters 0..wide

/// superscroller.bin, split the way the asset script wrote it.
export function parseBin(bin) {
    let at = 0;
    const take = (n) => { const v = bin.subarray(at, at + n); at += n; return v; };
    const rgb = (n) => { const c = take(3 * n); return Array.from({ length: n }, (_, i) => [c[3 * i], c[3 * i + 1], c[3 * i + 2]]); };
    const a = { back: take(W * H), overlay: take(W * H), rasters: take(RASTER_ROWS) };
    a.backRgb = rgb(4); a.overRgb = rgb(4); a.rasRgb = rgb(42); a.ink = rgb(1)[0];
    a.rowIds = take(GLYPHS * SAMPLED_ROWS);
    const rows = Math.max(...a.rowIds) + 1;
    const u16 = (b, i) => b[2 * i] | (b[2 * i + 1] << 8);
    const firstB = take(2 * (rows + 1));
    a.first = Array.from({ length: rows + 1 }, (_, i) => u16(firstB, i));
    const spanB = take(4 * a.first[rows]);
    a.spans = Array.from({ length: a.first[rows] }, (_, i) => [u16(spanB, 2 * i), u16(spanB, 2 * i + 1)]);
    if (at !== bin.length) throw new Error(`superscroller.bin is ${bin.length} bytes, layout says ${at}`);
    return a;
}

/// Which image rows canvas row cy shows from a copy at y (h rows tall), or null.
/// `snap` draws at whole rows instead (the break that proves the filtering matters).
export function tapRows(y, h, cy, snap = false) {
    const fy = snap ? Math.floor(y) : Math.fround(y);
    if (!(fy < cy + 0.5 && cy + 0.5 <= fy + h)) return null;
    const v = cy - fy, top = Math.floor(v);
    const clamp = (r) => Math.min(Math.max(r, 0), h - 1);
    return { ta: clamp(top), tb: clamp(top + 1), w: Math.floor((v - top) * 16) };
}

/// `opts.speed` and `opts.snap` exist to prove the harness fails on a wrong port.
export function makeReplay(bin, text, opts = {}) {
    const A = parseBin(bin), speed = opts.speed ?? SPEED, snap = !!opts.snap;
    const st = { y1: 0, ras: Array.from({ length: RASTER_COPIES }, (_, i) => RASTER_STEP * i), offset: 0 };
    const nextChar = () => { const c = text.charCodeAt(st.offset++); if (st.offset > text.length - 1) st.offset = 0; return c; };
    const letters = Array.from({ length: LETTERS }, (_, i) => ({ posx: Math.ceil((LETTERS - 1) * TILE_W + i * TILE_W), ltr: 0 }));
    for (const l of letters) { l.ltr = text.charCodeAt(st.offset); st.offset++; }

    function update() {
        st.y1 -= BACK_SPEED;
        if (st.y1 <= -399) st.y1 = 0;
        for (let i = 0; i < RASTER_COPIES; i++) {
            st.ras[i] -= 2;
            if (st.ras[i] <= -RASTER_STEP) st.ras[i] = RASTER_STEP * 4;
        }
    }
    function moveLetters() { // scrolltext.draw(0): no '^' codes in this text
        for (const l of letters) {
            l.posx -= speed;
            if (l.posx <= -TILE_W) { l.posx = (LETTERS - 1) * TILE_W + (l.posx + TILE_W); l.ltr = nextChar(); }
        }
    }
    const inkAt = (s, cx) => {
        for (const l of letters) {
            const gx = cx - l.posx, nb = l.ltr - FIRST_CHAR;
            if (gx < 0 || gx >= TILE_W || nb < 0 || nb >= GLYPHS) continue;
            const row = A.rowIds[nb * SAMPLED_ROWS + s / 2];
            for (let k = A.first[row]; k < A.first[row + 1]; k++) if (A.spans[k][0] <= gx && gx < A.spans[k][1]) return true;
        }
        return false;
    };
    const rasterAt = (s) => { // later copies are drawn over earlier ones
        let c = A.ink;
        for (let i = 0; i < RASTER_COPIES; i++) { const r = s - st.ras[i]; if (r >= 0 && r < RASTER_ROWS) c = A.rasRgb[A.rasters[r]]; }
        return c;
    };

    /// update() and the letters' move in draw(): one frame's motion.
    function step() {
        update();
        moveLetters();
    }

    /// The rest of draw(): the frame as it stands, as 320x200 RGB.
    function draw() {
        const y2 = st.y1 + BACK_STEP, y3 = y2 + BACK_STEP;
        const rgb = new Uint8Array(W * H * 3);
        for (let sy = 0; sy < H; sy++) {
            const cy = 2 * sy, s = cy - SCROLL_Y;
            let back = null;
            for (const y of [st.y1, y2, y3]) back = tapRows(y, BACK_H, cy, snap) ?? back;
            const overs = [st.y1, y2].map((y) => tapRows(y, BACK_H, cy, snap)).filter((t) => t);
            const scroll = s >= 0 && s < SCROLL_H, raster = scroll ? rasterAt(s) : null;
            for (let sx = 0; sx < W; sx++) {
                let d = [0, 0, 0];
                if (back) {
                    const a = A.backRgb[A.back[(back.ta >> 1) * W + sx]], b = A.backRgb[A.back[(back.tb >> 1) * W + sx]];
                    d = a.map((v, i) => (v * (16 - back.w) + b[i] * back.w) >> 4);
                }
                if (scroll && inkAt(s, 2 * sx)) d = raster;
                for (const o of overs) {
                    const oa = A.overlay[(o.ta >> 1) * W + sx], ob = A.overlay[(o.tb >> 1) * W + sx];
                    const sa = ((oa ? 255 : 0) * (16 - o.w) + (ob ? 255 : 0) * o.w) >> 4;
                    if (sa === 0) continue;
                    const ca = oa ? A.overRgb[oa - 1] : [0, 0, 0], cb = ob ? A.overRgb[ob - 1] : [0, 0, 0];
                    d = d.map((v, i) => ((ca[i] * (16 - o.w) + cb[i] * o.w) >> 4) + ((v * (256 - sa)) >> 8));
                }
                rgb.set(d, (sy * W + sx) * 3);
            }
        }
        return rgb;
    }

    return { step, draw };
}
