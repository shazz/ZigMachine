// ULM 3615 GEN4 (CODEF screen 539) replayed from screen.js itself, in CANVAS
// units, and sampled the way the scene documents: ST pixel (X, Y) shows canvas
// pixel (2X, 2Y). The images are gen4_3615's halved PNGs (every one doubled on
// the (0,0) grid), so canvas image pixel (u, v) is halved pixel (u >> 1, v >> 1).
//
// Written from the source, not from the scene: screen.js go() (155-167) and
// what it calls, codef_scrolltext.js scrolltext_horizontal (44-174), and the
// canvas semantics the draws rely on (nearest sampling: ctx.imageSmoothingEnabled
// = false; destination-in keeps only the scroll canvas's opaque pixels, over
// the WHOLE canvas; drawImage clips a source rect that leaves the image).
// Validated against the page itself run in Chrome (tools/private_tools/
// gen4_3615_ref.mjs): see the scene's header for the measured match.
//
// break: a sabotage name, so the harness can show its checks fail on a wrong
// replay ("sky": one sky line late, "floor": the floor's source row off by one,
// "fate": the logo's slices one row down, "ulm": the ULM table one entry late).
import { readFile } from "node:fs/promises";

export const ASSETS = "apps/zig/assets/screens/gen4_3615";
export const W = 384, H = 270; // the 768x540 canvas, halved

// screen.js:35-36, 54, 56, 58, 60 — verbatim
const skyColors = "00E.02E.04E.06E.08E.0AE.0CE.2EE.4EE.6EE.8EE.AEE.CEE.CCE.ECE.CCC.EEC.ECC.ECA.EEA.CEA.CE8.AE8.CE6.CE0.EE0.EE4.EE6.EEC.EE6.EE2.EE0.CE0.CE2.AE4.CE6.CEA.EEA.EC8.E88.E66.E40.A20.600.600".split(".");
const vueColors = "E00.C02.A04.806.608.40A.20C.00E.02C.04A.068.086.0A4.0C2.0E0.2E0.4E0.6E0.8E0.AE0.CE0.EE0.EC2.EA4.E86.E68.E4A.E2C.E0E.C2E".split(".");
const damierShadow = [4, 4, 6, 6, 8, 8, 10, 12, 12], damierAmpl = 400, damierWidth = 16, damierSpeed = Math.PI / 250, damierAlpha = 0.8, damierAlphaStep = 0.09;
const fateSpeed = 0.095, fateInc = 0.018, fatePersp = 200;
const ulmHeight = 122, ulmWidth = 284;
const mocheSpeed = 0.04;
const placement = [["minitel", 162, 82], ["minitel", 516, 82], ["gen4", 260, 60], ["bord", 0, 268], ["bord", 728, 268], ["whoelse", 140, 466]];
const vuePos = [0, 506 - 58, 282 - 58];

const css = (c) => [...c].map((n) => parseInt(n, 16) * 17);
const CHECK_DARK = css("045"), CHECK_LIGHT = css("0CE"), SHADOW = [0, 0, 20];

/// screen.js initDistort (379-460), verbatim.
export function ulmDistTable() {
    const ulmDistTable = [];
    let pos = 242;
    const trans = (increment, nb) => { for (let i = 0; i < nb; i++) { ulmDistTable.push(pos); pos += increment; } };
    function sinus(amplitude, nb_steps, nb, translate) {
        const step = 2 * Math.PI / nb_steps;
        if (nb_steps < 0) nb_steps *= -1;
        if (undefined == translate) translate = 0;
        for (let j = 0; j < nb; j++) for (let i = 0, a = 0; i < nb_steps; i++, a += step) { ulmDistTable.push(~~(pos + amplitude * Math.sin(a))); pos += translate; }
    }
    function halfsinus(amplitude, nb_steps, nb) {
        const step = Math.PI / nb_steps;
        if (nb_steps < 0) nb_steps *= -1;
        for (let j = 0; j < nb; j++) for (let i = 0, a = 0; i < nb_steps; i++, a += step) ulmDistTable.push(~~(pos + amplitude * Math.sin(a)));
    }
    const stay = (nbTimes) => { for (let k = 0; k < nbTimes; k++) ulmDistTable.push(pos); };
    stay(ulmHeight); sinus(128, 200, 2); sinus(50, 164, 2); sinus(10, 44, 8); sinus(8, 30, 8); sinus(4, 10, 8); sinus(2, 8, 50);
    trans(1, 164); trans(-1, 164); sinus(2, 8, 20); trans(-1, 164); trans(1, 164); sinus(2, 8, 20);
    sinus(242, 150, 3); stay(ulmHeight); sinus(242, -150, 3); stay(ulmHeight);
    sinus(140, 104, 1); sinus(140, 180, 2); sinus(240, 180, 2); sinus(140, 180, 1);
    halfsinus(242, 92, 5); halfsinus(242, -92, 5); sinus(140, 180, 1); halfsinus(140, 180, 3); sinus(140, 180, 1); halfsinus(140, -180, 3);
    sinus(50, 180, 2, 0.5); sinus(50, 180, 4, -0.5); sinus(50, 180, 2, 0.5); halfsinus(140, 180, 3); halfsinus(140, -180, 3);
    sinus(40, 40, 3, 1); sinus(40, 40, 6, -1); sinus(40, 40, 3, 1); sinus(40, 104, 5); halfsinus(20, 20, 15); halfsinus(20, -20, 15);
    stay(ulmHeight);
    return ulmDistTable;
}

/// screen.js init (115-128), verbatim.
export function mocheDistTable() {
    const mocheDist = [];
    let i, j, a;
    for (i = 0; i < 64; i++) mocheDist.push(0);
    for (i = 0; i < 5; i++) for (j = 0, a = 0; j < 50; j++, a += 2 * Math.PI / 50) mocheDist.push((16 - 16 * Math.cos(a)) % 24);
    for (i = 0; i < 24 * 6; i++) mocheDist.push(i % 24);
    for (i = 24 * 6; i > 0; i--) mocheDist.push(i % 24);
    for (i = 0; i < 32; i++) mocheDist.push(0);
    return mocheDist;
}

export async function loadAssets() {
    const art = new Uint8Array(await readFile(`${ASSETS}/art.bin`));
    const pal = new Uint8Array(await readFile(`${ASSETS}/pal.dat`));
    const font = new Uint8Array(await readFile(`${ASSETS}/font.bin`));
    let at = 0;
    const take = (w, h) => { const img = { px: art.subarray(at, at + w * h), w, h }; at += w * h; return img; };
    const A = { bord: take(12, 95), minitel: take(39, 16), gen4: take(118, 36), whoelse: take(236, 32), ulm: take(142, 61), fate: take(160, 56), moche: take(12, 12) };
    if (at !== art.length) throw new Error(`art.bin is ${art.length} bytes, layout says ${at}`);
    return { A, pal, font, text: await readFile(`${ASSETS}/scrolltext.txt`, "latin1") };
}

export class Replay {
    /// vol(k, n): YM voice k's volume register (0..15) on go() call n.
    constructor(assets, vol = () => 0, broke = "") {
        Object.assign(this, assets);
        this.vol = vol;
        this.broke = broke;
        this.ulmDist = ulmDistTable();
        this.mocheDist = mocheDistTable();
        this.n = 0;
        this.damierCtr = 0;
        this.showFate = false; this.fateWave = 0; this.fateCtr = 0;
        this.ulmCtr = 0;
        this.mocheCtr = 0; this.mocheDistCtr = 0;
        this.levels = [0, 0, 0]; this.lastVol = [0, 0, 0];
        this.events = [];
        // scrolltext_horizontal.init(scrollCan 704 wide, font 192x178, 12)
        this.wide = Math.ceil(704 / 192) + 1;
        this.letters = [];
        this.scroffset = 0;
        for (let i = 0; i <= this.wide; i++) this.letters.push({ posx: Math.ceil(this.wide * 192 + i * 192), ltr: this.text.charCodeAt(this.scroffset++) });
    }

    /// One go() call: advance exactly as screen.js does, keeping what it DRAWS.
    step() {
        this.n++;
        // damier()
        this.tx = ~~(-damierAmpl - damierAmpl * Math.cos(this.damierCtr));
        this.ty = ~~(-damierAmpl - damierAmpl * Math.sin(2 * this.damierCtr));
        this.damierCtr += damierSpeed;
        // dancingFate()
        this.slices = this.showFate ? this.fateSlices() : [];
        if (this.showFate) this.fateCtr += fateSpeed;
        // scroller(): scrolltext.draw(0) moves first
        this.scroll();
        // vueMeters(): sc68_vumeter.js getVolumeVoiceN, then the -6 fall
        for (let k = 0; k < 3; k++) {
            const reg = this.vol(k + 1, this.n) & 0xf;
            this.lastVol[k] = Math.max(reg * 100 / 0xf, this.lastVol[k] * 0.9);
        }
        [3, 2, 1].forEach((voice, id) => {
            const v = ~~(this.lastVol[voice - 1] * 1.8);
            this.levels[id] = this.levels[id] < v ? v : this.levels[id] - 6;
            this.levels[id] = this.levels[id] < 0 ? 0 : this.levels[id];
        });
        // dancingUlm()
        this.ulmDrawn = this.ulmCtr;
        this.ulmCtr += 2;
        if (this.ulmCtr > this.ulmDist.length - ulmHeight) this.ulmCtr = 0;
        // motifMoche()
        this.mocheY = (84 + 84 * Math.sin(this.mocheCtr)) % 24;
        this.mocheDrawn = this.mocheDistCtr;
        this.mocheCtr += mocheSpeed;
        this.mocheDistCtr++;
        if (this.mocheDistCtr > this.mocheDist.length - 32) this.mocheDistCtr = 0;
    }

    scroll() { // codef_scrolltext.js:98-134, the text has only ^C codes
        for (const l of this.letters) {
            l.posx -= 12;
            if (l.posx <= -192) {
                if (this.text.charAt(this.scroffset) === "^") {
                    const end = this.text.indexOf(";", this.scroffset + 2);
                    const fn = this.text.substring(this.scroffset + 2, end);
                    this.events.push([fn, this.n]);
                    if (fn === "LogoFate") { this.showFate = true; this.fateWave = 0; }
                    else if (fn === "LogoWaveform") { if (++this.fateWave > 5) this.fateWave = 0; }
                    else throw new Error(`unknown scroller command ${fn}`);
                    this.scroffset += (end - this.scroffset) + 1;
                } else {
                    l.posx = this.wide * 192 + (l.posx + 192);
                    l.ltr = this.text.charCodeAt(this.scroffset);
                    this.scroffset++;
                    if (this.scroffset > this.text.length - 1) this.scroffset = 0;
                }
            }
        }
    }

    fateSlices() { // screen.js dancingFate (242-338)
        const fatePos = [];
        let a, b, i;
        const fateCtr = this.fateCtr;
        switch (this.fateWave) {
            case 0: for (i = 112, a = fateCtr; i >= 0; i--, a += fateInc) fatePos[i] = { i, y: 40 + 40 * Math.cos(a), z: 10 * Math.sin(a) }; break;
            case 1: for (i = 112, a = fateCtr * 1.5, b = fateCtr / 2; i >= 0; i--, a += fateInc * 5, b += fateInc / 2) fatePos[i] = { i, y: i, z: 20 + 5 * Math.cos(a) + 12 * Math.cos(b) }; break;
            case 2: {
                a = fateCtr / 1.5;
                let pa = { y: 50 + 30 * Math.cos(a), z: 20 * Math.sin(a) };
                const pb = { y: 50 + 30 * Math.cos(a + Math.PI), z: 20 * Math.sin(a + Math.PI) };
                const pi = { y: (pb.y - pa.y) / 112, z: (pb.z - pa.z) / 112 };
                for (i = 0; i <= 112; i++) { fatePos[i] = { i, y: pa.y, z: pa.z }; pa = { y: pa.y + pi.y, z: pa.z + pi.z }; }
                break;
            }
            case 3: for (i = 112, a = fateCtr / 2, b = fateCtr / 5; i >= 0; i--, a += fateInc, b += fateInc / 5) fatePos[i] = { i, y: 50 + 50 * Math.cos(a), z: 20 + 20 * Math.sin(a - 2 * Math.PI / 3) }; break;
            case 4: for (i = 112, a = fateCtr; i >= 0; i--, a += fateInc * 2) fatePos[i] = { i: 112 - i, y: 70 + 20 * Math.cos(a) - i / 3, z: (112 - i) / 10 }; break;
            case 5: for (i = 112, a = fateCtr / 2; i >= 0; i--, a += fateInc) fatePos[i] = { i, y: 50 + 60 * Math.cos(a), z: (112 - i) / 10 }; break;
        }
        fatePos.sort((p, q) => p.z - q.z);
        return fatePos.map((p) => ({
            i: p.i,
            x: ~~(600 * fatePersp / (p.z + fatePersp) - 357),
            y: 286 + ~~(p.y * fatePersp / (p.z + fatePersp)) + (this.broke === "fate" ? 1 : 0),
            l: ~~(264 + 5.6 * p.z),
        }));
    }

    rgb(i) { return i === 0 ? null : [this.pal[i * 4], this.pal[i * 4 + 1], this.pal[i * 4 + 2]]; }
    art(img, u, v) { return img.px[(v >> 1) * img.w + (u >> 1)]; }

    /// The frame go() call n leaves on the canvas, halved: RGB, black where transparent.
    render() {
        const out = new Uint8Array(W * H * 3);
        const put = (X, Y, c) => { if (c) out.set(c, (Y * W + X) * 3); };
        this.renderScroller(put);
        this.renderVu(put);
        this.renderUlm(put);
        this.renderMoche(put);
        for (const [name, x, y] of placement) {
            const img = this.A[name];
            for (let v = 0; v < img.h; v++) for (let u = 0; u < img.w; u++) put(x / 2 + u, y / 2 + v, this.rgb(img.px[v * img.w + u]));
        }
        return out;
    }

    /// damier() + dancingFate(), then scroller()'s destination-in: only the
    /// glyphs of the 704x176 scroll canvas at (24, 268) keep anything.
    renderScroller(put) {
        const corr = [];
        for (let y = 0, c = 10; y < 90; y++, c -= 0.051) corr.push(c); // damier():198, the float walk kept
        for (let Y = 134; Y < 222; Y++) {
            const cy = 2 * Y, sy = cy - 268;
            for (let X = 12; X < 364; X++) {
                const cx = 2 * X, sx = cx - 24;
                if (!this.glyphAt(sx, sy)) continue;
                put(X, Y, this.fateAt(cx, cy) ?? this.floorAt(cx, cy, corr));
            }
        }
    }

    glyphAt(sx, sy) {
        for (const l of this.letters) {
            const gx = sx - l.posx;
            if (gx < 0 || gx >= 192 || sy >= 178) continue;
            const g = l.ltr - 32, bit = (g * 89 + (sy >> 1)) * 96 + (gx >> 1);
            return (this.font[bit >> 3] >> (7 - (bit & 7))) & 1;
        }
        return 0;
    }

    floorAt(cx, cy, corr) {
        if (cy >= 270 && cy < 360) { // the sky pattern, anchored at the canvas origin
            const row = (this.broke === "sky" ? cy - 2 : cy) % 90;
            return css(skyColors[row >> 1]);
        }
        if (cy < 360 || cy >= 450) return null;
        const y = cy - 360;
        // drawPart(main, -16y, 360+y, 0, y*corr, 704, 1, 1, 0, 1+0.04y, 1)
        const x0 = 0 - y * 16, zoom = 1 + y * 0.04;
        const u = Math.floor((cx + 0.5 - x0) / zoom);
        let c = null; // row 0 of the floor ends at x 704, short of the scroll canvas
        if (u >= 0 && u < 704) {
            const v = Math.floor(y * corr[y] + 0.5) + (this.broke === "floor" ? 1 : 0);
            const light = (((u - this.tx) & 31) < 16) === (((v - this.ty) & 127) < 64);
            c = light ? CHECK_LIGHT : CHECK_DARK;
        }
        // the far shadow bands
        let top = 360, alpha = damierAlpha;
        for (const h of damierShadow) {
            if (cy >= top && cy < top + h) { c = blend(c, SHADOW, alpha); break; }
            top += h;
            alpha -= damierAlphaStep;
        }
        return c;
    }

    fateAt(cx, cy) {
        let hit = null;
        for (const s of this.slices) { // later slices are drawn over earlier ones
            const row = s.i + (cy - s.y);
            if (cy < s.y || cy > s.y + 1 || row >= 112) continue;
            if (cx < s.x || cx >= s.x + s.l) continue;
            // Chrome's nearest-neighbour scale steps a 16.16 source x from half a
            // step, the step truncated: exact floor((d + 0.5) * 320 / l) misses 41
            // pixels of the six reference frames, this misses 3 (all on exact
            // .0 boundaries, which Chrome resolves some other way)
            const step = Math.floor(320 * 65536 / s.l);
            const u = (Math.floor(step / 2) + (cx - s.x) * step) >> 16;
            hit = this.rgb(this.art(this.A.fate, u, row));
        }
        return hit;
    }

    renderVu(put) { // the 640x180 meter canvas at (58, 82); bars at vuPos, colours by row
        for (let id = 0; id < 3; id++) {
            for (let Y = 41; Y < 131; Y++) {
                const r = 2 * Y - 82;
                if (r < 180 - this.levels[id] || r % 6 >= 4) continue;
                const c = css(vueColors[Math.floor(r / 6)]);
                for (let X = (58 + vuePos[id]) / 2; X < (58 + vuePos[id] + 192) / 2; X++) put(X, Y, c);
            }
        }
    }

    renderUlm(put) { // row r of the logo at y 140 + r, x = ulmDistTable[ulmCtr + r]; row 0 and 122 never drawn
        for (let Y = 71; Y <= 130; Y++) {
            const r = 2 * Y - 140;
            const x = this.ulmDist[this.ulmDrawn + r + (this.broke === "ulm" ? 1 : 0)];
            for (let X = 0; X < W; X++) {
                const u = 2 * X - x;
                if (u >= 0 && u < ulmWidth) put(X, Y, this.rgb(this.art(this.A.ulm, u, r)));
            }
        }
    }

    renderMoche(put) { // 32 two-row strips of the 24x24 tiled pattern at (140, 466)
        for (let k = 0; k < 32; k++) {
            const x = this.mocheDist[this.mocheDrawn + 32 - k];
            const v = Math.floor(this.mocheY + 2 * k + 0.5);
            for (let X = 70; X < 70 + 236; X++) {
                const u = Math.floor(x + 2 * X - 140 + 0.5);
                put(X, 233 + k, this.rgb(this.art(this.A.moche, u % 24, v % 24)));
            }
        }
    }
}

/// fillRect(rgba(0,0,20,alpha)) over an opaque pixel, as Chrome's raster
/// rounds it (fitted to all 36 shaded colours of a reference frame): an 8-bit
/// alpha, the source premultiplied and rounded, the destination scaled by
/// (256 - A) / 256 and truncated. Over a transparent pixel (d = null) it leaves
/// the premultiplied source, which is what shows over the page's black.
export function blend(c, s, a) {
    const A = Math.round(a * 255);
    return s.map((v, i) => Math.round(v * A / 255) + (c ? Math.floor(c[i] * (256 - A) / 256) : 0));
}
