// The Union Demo DELTA FORCE screen (screens/deltaforce/screen.js), replayed in
// JS at 320x200 for apps/union_deltaforce_headless.mjs, plus the YM volume path
// both that harness and the Chrome reference capture drive it with.
//
// The state follows screen.js line by line (update 140-313, draw 320-434), not
// the scene, with ONE deliberate deviation the port makes (Matt, 2026-09-14): the
// scrolltext's RESET also restores the band speed, the effect and the letter ring,
// so the screen loops instead of never scrolling again (see draw, FX.RESET).
// Drawing goes through the canvas chain in canvas units and is halved
// by the rules the port documents:
//   - a draw at canvas (x, y) with y rounded (Math.round) lands on ST floor(y/2);
//   - questfont is used as its two area halvings (parity of the canvas row the
//     text canvas starts on), gold_backdrop/floor/logos/balls as exact 2x halves;
//   - a vertically scaled draw about canvas row C shows, on ST row Y, the source
//     row under canvas row 2Y+1: C_src/2 + (2Y+1-C)/scale, halved;
//   - a text pixel of alpha level l over gold colour g is floor(GOLD_RGB[g] * l / 8).
// It reads the converted assets (deltaforce.bin, pal.dat, scrolltext.txt).
import { readFileSync } from "node:fs";

export const ASSETS = "apps/zig/assets/screens/union_deltaforce";

/// The YM volume registers 8, 9, 10 before screen update `frame` (0 = the first
/// update). A changes every 8 frames; B about every 6 with its envelope bit
/// flipping every 512; C bursts for 3 frames in 23 then holds, with bit 5 (masked
/// off by ym.js) toggling. Self-contained: the reference capture serialises it.
export function regsAt(frame) {
    if (frame === 0) return [0, 0, 0];
    const a = (frame >> 3) & 15;
    const b = (((frame * 5) >> 5) & 15) | (((frame >> 9) & 1) << 4);
    const c = (frame % 23 < 3 ? frame & 15 : 9) | (((frame >> 6) & 1) << 5);
    return [a, b, c];
}

// gold_backdrop.png's palette, indices 0..6
const GOLD_RGB = [[0, 0, 0], [64, 32, 0], [96, 64, 0], [128, 96, 0], [160, 128, 0], [213, 165, 0], [224, 192, 0]];
const LEVELS = 8;

// screen.js:89-103, transcribed separately from the scene
const INTRO_EFFECTS = [
    ["MEGA DEMO!", "          ", 42], ["MEGA DEMO!", "CODING BY:", 42], ["-NEW MODE-", "CODING BY:", 42],
    ["-NEW MODE-", "GRAPHIX BY", 42], ["  -SLIME- ", "GRAPHIX BY", 42], ["  -SLIME- ", "   AND    ", 42],
    ["QUESTLORD!", "   AND    ", 42], ["QUESTLORD!", "MUZAK BY: ", 42], [" MAD MAX  ", "MUZAK BY: ", 42],
    [" MAD MAX  ", "          ", 42], ["  HELLO   ", "          ", 4], ["  HELLO   ", "          ", 4],
];
const FX = { TWIST: 0, LETTER_SINEWAVE: 1, GLOBAL_SINEWAVE: 2, INVERSE: 3, REVERSE: 4, RESET: 5, NO_EFFECT: 6 };
export const FX_NAMES = Object.fromEntries(Object.entries(FX).map(([k, v]) => [v, k]));

export function loadAssets() {
    const bin = new Uint8Array(readFileSync(`${ASSETS}/deltaforce.bin`));
    const pal = new Uint8Array(readFileSync(`${ASSETS}/pal.dat`));
    const text = readFileSync(`${ASSETS}/scrolltext.txt`, "latin1");
    let at = 0;
    const take = (w, h) => { const px = bin.subarray(at, at + w * h); at += w * h; return { px, w, h }; };
    const A = {
        floor: take(298, 31), logos: take(320, 128), balls: take(768, 57), gold: take(320, 59),
        font: [take(320, 7 * 16), take(320, 7 * 17)], pal, text,
    };
    if (at !== bin.length) throw new Error(`deltaforce.bin is ${bin.length} bytes, layout says ${at}`);
    return A;
}

/// `brk` deliberately gets one number wrong, so the harness can prove it fails.
export function makeReplay(A, brk = null) {
    const TEXT = A.text;
    const GOLD_STEP = brk === "gold" ? 12 : 6; // a wrong step must stay even: goldY/2 indexes the halved texture
    const TWIST_STEP = brk === "twist" ? 0.11 : 0.1;
    const WAVE_INC = brk === "wave" ? 0.0041 : 0.004;
    const FLASH = brk === "voices" ? 6 : 7;
    const S = {
        logoHeight: 1, logoSize: 0.035, logoTile: 0, logoCounter: 0, goldY: 0,
        cur: [0, 0, 0], last: [0, 0, 0],
        fx: FX.REVERSE, twist: 0, sine: 0, introTime: 0,
        effect: 0, pos: -640, speed: 14, stop: 0, introValue: 10,
        letters: [], scroffset: 0, updates: 0,
    };
    // scrolltext.init(scrollcanvas 640x32, font initTile(64,34,32), 10)
    const wide = Math.ceil(640 / 64) + 1;
    function initScrolltext() {
        S.letters = [];
        S.scroffset = 0;
        for (let i = 0; i <= wide; i++) S.letters.push({ posx: Math.ceil(wide * 64 + i * 64), ltr: TEXT.charCodeAt(S.scroffset++) });
    }
    initScrolltext();

    function introStep() {
        S.pos += S.speed;
        if (S.pos >= 0) {
            S.stop++;
            if (S.stop === INTRO_EFFECTS[S.effect][2]) {
                S.speed = -S.speed; S.effect++; S.stop = 0;
                if (S.effect >= INTRO_EFFECTS.length - 1) S.introTime = 1;
            } else S.pos = 0;
        } else if (S.pos <= -640) {
            S.stop++;
            if (S.stop === INTRO_EFFECTS[S.effect][2]) { S.speed = -S.speed; S.effect++; S.stop = 0; }
            else S.pos = -640;
        }
    }

    const MARKERS = { a: FX.LETTER_SINEWAVE, b: FX.TWIST, c: FX.INVERSE, d: FX.REVERSE, e: FX.GLOBAL_SINEWAVE, f: FX.NO_EFFECT, g: FX.RESET };

    S.update = (regs) => {
        S.logoHeight -= S.logoSize;
        if (S.logoHeight <= 0) { S.logoSize = -0.035; S.logoTile = 1 - S.logoTile; }
        else if (S.logoHeight >= 1) { S.logoSize = 0.00; if (S.logoCounter++ === 45 * 3) { S.logoSize = 0.035; S.logoCounter = 0; } }
        S.goldY += GOLD_STEP;
        if (S.goldY >= 118) S.goldY = 0;
        for (let k = 0; k < 3; k++) {
            const vol = regs[k] & 31; // ym.js writeRegisters: registers[8..10] &= 31
            if (S.last[k] !== vol) S.cur[k] = FLASH;
            else if (S.cur[k]-- < 1) S.cur[k] = 0;
            S.last[k] = vol;
        }
        if (S.introTime === 0 || S.introTime === 1) introStep();
        if (S.introTime === 1 && S.pos <= -640) S.introTime = 2;
        if (S.introTime === 1 || S.introTime === 2) {
            const m = MARKERS[TEXT.charAt(S.scroffset)];
            if (m !== undefined) { S.fx = m; S.scroffset++; }
        }
        S.updates++;
    };

    /// draw(); returns a 320x200 RGB frame when `render`, else only moves the state.
    S.draw = (render) => {
        const map = render ? new Uint8Array(320 * 200 * 3) : null; // fill('#000000')
        if (render) drawStage(map);
        if (S.introTime === 1 || S.introTime === 2) {
            for (const l of S.letters) { // scrolltext.draw(0), speed 10, no '^' codes in this text
                l.posx -= 10;
                if (l.posx <= -64) {
                    l.posx = wide * 64 + (l.posx + 64);
                    l.ltr = TEXT.charCodeAt(S.scroffset++);
                    if (S.scroffset > TEXT.length - 1) S.scroffset = 0;
                }
            }
            let posy = null;
            switch (S.fx) {
                case FX.INVERSE: S.twist += TWIST_STEP; if (S.twist >= Math.PI) S.twist = Math.PI; posy = 110 / 2 - 16; break;
                case FX.NO_EFFECT: S.twist = 0.0; posy = 110 / 2 - 16; break;
                case FX.REVERSE: S.twist += TWIST_STEP; if (S.twist >= 2 * Math.PI) S.twist = 2 * Math.PI; posy = 110 / 2 - 16; break;
                case FX.GLOBAL_SINEWAVE: S.twist = 0.0; S.sine += 0.1; posy = (110 / 2) - 24 + (30 * Math.sin(S.sine)); break;
                case FX.RESET:
                    S.twist = 0.0; S.sine = 0.0; S.introTime = 0; S.effect = 0; S.scroffset = 0; S.pos = -640; S.stop = 0;
                    // The port's deliberate deviation (Matt, 2026-09-14): the whole
                    // screen restarts, so the scroller loops. --break reset replays
                    // screen.js as written (speed, fx and letters left as they are).
                    if (brk !== "reset") { S.speed = 14; S.fx = FX.REVERSE; initScrolltext(); }
                    break;
                default: throw new Error(`the text selected ${FX_NAMES[S.fx]}, which the replay does not model`);
            }
            if (render && posy !== null) {
                const glyphs = S.letters.map((l) => ({ x: l.posx, ch: l.ltr }));
                const ys = new Array(640).fill(Math.round(posy)); // scrollfx_noFX: prov = sin(0)*0
                band(map, glyphs, 640, ys, 0, 300 + 110 / 2, Math.cos(S.twist));
            }
        }
        if (S.introTime === 0 || S.introTime === 1) {
            const words = INTRO_EFFECTS[S.effect];
            if (words === undefined) throw new Error(`introEffects[${S.effect}] read: the original throws here`);
            const value = S.introValue; // scrollfx_intro.siny(0, (110/2) - 16)
            if (render) {
                const glyphs = [];
                for (let i = 0; i < 10; i++) {
                    glyphs.push({ x: i * 64, ch: words[0].charCodeAt(i) }, { x: 640 + i * 64, ch: words[1].charCodeAt(i) });
                }
                const ys = [];
                let v = value;
                for (let i = 0; i < 1280; i++) {
                    let prov = 0;
                    prov += Math.sin(v) * 30;
                    ys.push(Math.round(prov + (110 / 2 - 16)));
                    v += WAVE_INC;
                }
                band(map, glyphs, 1280, ys, S.pos, 280 + 110 / 2, Math.cos(S.twist));
            }
            S.introValue = value + -0.09;
        }
        return map;
    };

    const rgb = (map, x, y, r, g, b) => {
        if (x < 0 || x >= 320 || y < 0 || y >= 200) return;
        map.set([r, g, b], (y * 320 + x) * 3);
    };
    const pic = (map, x, y, idx) => rgb(map, x, y, A.pal[idx * 4], A.pal[idx * 4 + 1], A.pal[idx * 4 + 2]);

    function drawStage(map) {
        for (let r = 0; r < 31; r++) for (let c = 0; c < 298; c++) { // slab.draw(main, 6, 192)
            const p = A.floor.px[r * 298 + c];
            if (p) pic(map, 3 + c, 96 + r, p);
        }
        // logo.drawTile(main, logoTile, 320, 65, 1, 0, 1, logoHeight), mid-handled 640x128 tile
        for (let y = 0; y < 200; y++) {
            const v = 64 + (2 * y + 1 - 65) / S.logoHeight;
            if (!(v >= 0 && v < 128)) continue;
            const row = (S.logoTile * 64 + Math.floor(v / 2)) * 320;
            for (let x = 0; x < 320; x++) pic(map, x, y, A.logos.px[row + x]);
        }
        for (let k = 0; k < 3; k++) { // balls.drawPart(main, 160+96k, 140, (15-v)*96, 0, 96, 114)
            const frame = 15 - S.cur[k];
            for (let r = 0; r < 57; r++) for (let c = 0; c < 48; c++) {
                const p = A.balls.px[r * 768 + frame * 48 + c];
                if (p) pic(map, 80 + 48 * k + c, 70 + r, p);
            }
        }
    }

    /// print into the text canvas, siny into the 110-row merge canvas at canvas
    /// y = ys[column], gold 'source-atop', then drawPart(main, dx + w/2, centre, ...,
    /// 1, scale) mid-handled.
    function band(map, glyphs, canvasW, ys, dxCanvas, centre, scale) {
        const w = canvasW / 2;
        const strips = [new Uint8Array(w * 17), new Uint8Array(w * 17)];
        for (const { x, ch } of glyphs) {
            const nb = ch - 32;
            if (nb < 0 || nb >= 70) continue;
            for (let p = 0; p < 2; p++) {
                const rows = p ? 17 : 16;
                for (let r = 0; r < rows; r++) for (let c = 0; c < 32; c++) {
                    const X = x / 2 + c;
                    if (X >= 0 && X < w) strips[p][r * w + X] = A.font[p].px[(Math.floor(nb / 10) * rows + r) * 320 + (nb % 10) * 32 + c];
                }
            }
        }
        const merge = new Uint8Array(w * 55);
        for (let X = 0; X < w; X++) {
            const y0 = ys[2 * X], p = y0 & 1, top = Math.floor(y0 / 2);
            for (let k = 0; k < 17; k++) {
                const m = top + k;
                if (m >= 0 && m < 55) merge[m * w + X] = strips[p][k * w + X];
            }
        }
        const shift = S.goldY / 2;
        for (let y = 0; y < 200; y++) {
            const v = 55 + (2 * y + 1 - centre) / scale;
            if (!(v >= 0 && v < 110)) continue;
            const h = Math.floor(v / 2), gr = (h - shift + 59) % 59;
            for (let X = 0; X < w; X++) {
                const level = merge[h * w + X];
                if (!level) continue;
                const g = A.gold.px[gr * 320 + (X % 320)], c = GOLD_RGB[g];
                rgb(map, dxCanvas / 2 + X, y, (c[0] * level) >> 3, (c[1] * level) >> 3, (c[2] * level) >> 3);
            }
        }
    }
    return S;
}
