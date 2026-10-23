// The picture half of the PHENOMENA model (apps/phenomena_model.mjs):
// screen.js's drawing of the frame the model is on, seen through the port's
// mapping (content line r = canvas row 2r+1, canvas column X = plane column
// 80+X, line 0 = physical row 20; borders black except where a bar runs).
import { CHARSET, PAGE1, PAGE2, LINE, lower, word, blend } from "./phenomena_model.mjs";

/// The whole 800x280 raster, RGBA words. `tops` = the cart's strip tops
/// (Q16), held to the doubles separately.
export function picture(M, tops) {
    const A = M.A, v = M.seq.view, out = new Uint32Array(800 * 280).fill(word([0, 0, 0]));
    const put = (X, r, c) => { out[(20 + r) * 800 + 80 + X] = word(c); };
    if (v.phase <= 1) { pages(M, put, v); return out; }
    for (let r = 65; r < 215; r++) for (let X = 0; X < 640; X++) put(X, r, A.panel);
    for (let r = 0; r < 64; r++) for (let X = 0; X < 640; X++) {
        const p = A.logo[r * 640 + X];
        if (!p) continue;
        const c = [A.logoPal[3 * p - 3], A.logoPal[3 * p - 2], A.logoPal[3 * p - 1]];
        put(X, r, v.phase !== 2 ? c : v.level <= 100 ? A.grey[v.level] : blend([255, 255, 255], c, 200 - v.level));
    }
    if (v.phase >= 5) photon(M, put, v);
    if (v.phase === 7) scroller(M, put, v, tops);
    const bar = (first, rowOf, bg, a) => {
        for (let j = 0; j < 6; j++) {
            const c = word(blend(A.bar[rowOf(j)], bg(j), a));
            out.fill(c, (20 + first + j) * 800, (21 + first + j) * 800);
        }
    };
    if (v.phase >= 3) bar(LINE.BAR_TOP, (j) => 2 * j, (j) => (j === 0 ? [0, 0, 0] : A.panel), v.phase === 3 ? v.level : 100);
    if (v.phase >= 4) bar(LINE.BAR_BOTTOM, (j) => 2 * j + 1, () => [0, 0, 0], v.phase === 4 ? v.level : 100);
    return out;
}

function pages(M, put, v) {
    const A = M.A;
    for (const [y, text] of v.phase === 0 ? PAGE1 : PAGE2) {
        for (let j = 0; j < text.length; j++) {
            const g = CHARSET.indexOf(text[j]);
            for (let r = 0; r < 240; r++) {
                const k = Math.floor((2 * r + 1 + 0.5 - y) / 2); // zoom 2, smoothing off
                if (k < 0 || k >= 26) continue;
                for (let X = 48 + 32 * j; X < 80 + 32 * j; X++) {
                    if (!((A.font[g][k] >> ((X - 48 - 32 * j) >> 1)) & 1)) continue;
                    if (v.phase === 1) { put(X, r, A.grey[Math.min(v.level, 100)]); continue; }
                    const src = lower(2 * r + 1 + 0.5 - v.rb2 / 2); // rasterbar.png at rasterbarY
                    const grey = src >= 0 && src < 80 ? A.barIntro[src] : 0;
                    put(X, r, [grey, grey, grey]);
                }
            }
        }
    }
}

function photon(M, put, v) {
    const A = M.A;
    const c = v.phase === 5 ? [255, 255, 255] : v.phase === 6 ? A.redfade[v.level] : A.hue[v.hue % 360];
    for (let r = 0; r < 240; r++) {
        const pr = 2 * r + 1 - v.photon;
        if (pr < 0 || pr >= 15) continue;
        for (let x = 0; x < 70; x++) if (A.photon[pr * 70 + x]) put(285 + x, r, c);
    }
}

/// drawScroller: slice i of cnvFrames (glyph chr[i], frame floor(frm[i]),
/// columns slc*2, slc*2+1) at the strip top, cnvScroller at 156 zoom (2,1.5).
function scroller(M, put, v, tops) {
    const A = M.A;
    for (let i = 0; i < 160; i++) {
        const g = CHARSET.indexOf(M.chr[i]), f = Math.floor(M.frm[i] / 20);
        for (let r = 78; r < 213; r++) {
            if (v.rectW > 4 * i && r >= 187) continue; // under the reveal quad
            const b = lower((2 * r + 1 + 0.5 - 156) / 1.5);
            const R = Math.floor((b * 65536 + 32768 - tops[i]) / 65536);
            if (R < 0 || R >= 33) continue;
            for (let x = 0; x < 4; x++) put(4 * i + x, r, filmstrip(A, g, f, R, M.slc[i] * 2 + (x >> 1)));
        }
    }
}

/// cnvFrames: purple back (cnvFont2 = the font upside down in its 33-row
/// cell, posY 0..31.5 then -33..-2.25), the red bar on rows 12..20, the
/// silver front (posY 33 down to -32.25) on top; 2.25 a frame.
function filmstrip(A, g, f, R, x) {
    const ink = (row) => row >= 0 && row < 26 && (A.font[g][row] >> x) & 1;
    const sTop = 33 - 2.25 * f;
    if (ink(Math.floor(R + 0.5 - sTop))) return A.silver[R];
    if (R >= 12 && R <= 20) return A.red[R - 12];
    const pTop = f < 15 ? 2.25 * f : -33 + 2.25 * (f - 15);
    const c = Math.floor(R + 0.5 - pTop);
    if (c >= 0 && c < 33 && ink(32 - c)) return A.purple[R];
    return A.panel;
}
