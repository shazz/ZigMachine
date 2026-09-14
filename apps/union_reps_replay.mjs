// screens/reps/screen.js (update 143-225, draw 232-286), codef_core.js
// image.draw/drawTile and codef_scrolltext.js (44-174) replayed in CANVAS units,
// from the source and not from the scene, then halved the way the scene
// documents: ST pixel (X, Y) shows canvas pixel (2X+1, 2Y+1). The images are
// reps.bin's halved PNGs, so canvas image pixel (u, v) is halved pixel (u>>1, v>>1).
//
// The sprites are the one place the port picks: screen.js:235 resets the canvas,
// so Chrome draws them smoothed at fractional positions. The replay takes the
// texel whose centre is nearest the sample point, floor(2X+1 + 0.5 - x).
//
// --break raster|speed|sprites replays a wrong raster sample row, speed table or
// sprite increment, so the harness can show that it fails.
import { readFile } from "node:fs/promises";

export const ASSETS = "apps/zig/assets/screens/union_reps";
const BLACK = 1, RED = 2, BLUE = 3, BLEND_BASE = 8, UNDER = [4, 5, 6, 7, RED, BLUE];
const LETTERS = "THE REPLICANTS";

export async function loadAssets() {
    const bin = new Uint8Array(await readFile(`${ASSETS}/reps.bin`));
    const pal = new Uint8Array(await readFile(`${ASSETS}/pal.dat`));
    const text = await readFile("apps/zig/assets/screens/union_demo/scrolltext.txt", "latin1");
    let at = 0;
    const take = (w, h) => { const img = { px: bin.subarray(at, at + w * h), w, h }; at += w * h; return img; };
    const A = {
        overlay: take(320, 200), mask: take(320, 54), theunion: take(320, 43), font: take(512, 128),
        sprites: Object.fromEntries([..."THERPLICANS"].map((l) => [l, take(16, 16)])),
        rasters: take(84, 1).px, pink: take(14, 1).px, green: take(14, 1).px, brown: take(15, 1).px,
    };
    if (at !== bin.length) throw new Error(`reps.bin is ${bin.length} bytes, layout says ${at}`);
    return { A, pal, text };
}

function scroller(text) { // scrolltext_horizontal.init(canvas 640x64, font, 4, undefined, 0, mainscrollerPos 0)
    const wide = Math.ceil(640 / 64) + 1, letters = [];
    let scroffset = 0;
    for (let i = 0; i <= wide; i++) letters.push({ posx: Math.ceil(wide * 64 + i * 64), ltr: text.charCodeAt(scroffset++) });
    return {
        letters,
        move(speed) { // codef_scrolltext.js:105-134 (the text has no '^' codes)
            for (const l of letters) {
                l.posx -= speed;
                if (l.posx <= -64) {
                    l.posx = wide * 64 + (l.posx + 64);
                    l.ltr = text.charCodeAt(scroffset);
                    scroffset++;
                    if (scroffset > text.length - 1) scroffset = 0;
                }
            }
        },
    };
}

export function makeReplay({ A, text }, brk = null) {
    const s = {
        y1: -168, y2: 0, top: [94, 124, 154], topDir: [2, 2, 2], bottom: [204, 234, 264], bottomDir: [-2, -2, -2],
        counter: Array.from({ length: 14 }, (_, i) => i * 0.5), px: [], py: [], scrollspeed: 1, speed: 4,
    };
    const inc = brk === "sprites" ? 0.07 : 0.08;
    const speeds = brk === "speed" ? [2, 6, 8, 16, 32] : [2, 4, 8, 16, 32];
    const red = scroller(text), blue = scroller(text);

    // update() then the letter walk of scrolltextRed/Blue.draw(0); held is "left", "right" or null
    function step(held) {
        s.y1 += 1; if (s.y1 >= 168) s.y1 = -168;
        s.y2 += 1; if (s.y2 >= 168) s.y2 = -168;
        for (let i = 0; i < 3; i++) {
            s.top[i] += s.topDir[i];
            if (s.top[i] < 94 || s.top[i] > 160) s.topDir[i] = -s.topDir[i];
            s.bottom[i] += s.bottomDir[i];
            if (s.bottom[i] < 204 || s.bottom[i] > 270) s.bottomDir[i] = -s.bottomDir[i];
        }
        for (let i = 0; i < 14; i++) {
            s.counter[i] += inc;
            s.px[i] = (40 + (i * 40)) + (30 * Math.cos(s.counter[i]));
            s.py[i] = 180 + (30 * Math.sin(s.counter[i]));
        }
        if (held === "left") { if (s.scrollspeed < 4.0) s.scrollspeed += 0.025; }
        else if (held === "right") { if (s.scrollspeed > 0.0) s.scrollspeed -= 0.025; }
        const r = Math.round(s.scrollspeed);
        s.speed = r >= 0 && r <= 4 ? speeds[r] : 4;
        red.move(s.speed);
        blue.move(s.speed);
    }

    function render() {
        const map = new Uint8Array(320 * 200).fill(BLACK);
        const sample = (c) => 2 * c + 1;
        // image.draw(maincanvas, dx, dy) of (part of) a halved image; ink(p, X, Y) -> index, 0 = skip
        const draw = (img, dx, dy, ink, part = { sx: 0, sy: 0, w: img.w, h: img.h }) => {
            for (let Y = Math.max(0, Math.ceil((dy - 1) / 2)); Y < 200; Y++) {
                const v = sample(Y) - dy;
                if (v >= 2 * part.h) break;
                for (let X = Math.max(0, Math.ceil((dx - 1) / 2)); X < 320; X++) {
                    const u = sample(X) - dx;
                    if (u >= 2 * part.w) break;
                    const p = img.px[(part.sy + (v >> 1)) * img.w + part.sx + (u >> 1)];
                    const o = p ? ink(p, X, Y) : 0;
                    if (o) map[Y * 320 + X] = o;
                }
            }
        };
        const copy = (p) => p;
        const bars = [[A.pink, s.top[0]], [A.green, s.top[1]], [A.brown, s.top[2]], [A.brown, s.bottom[0]], [A.green, s.bottom[1]], [A.pink, s.bottom[2]]];
        for (const [rows, y] of bars) draw({ px: Uint8Array.from({ length: 320 * rows.length }, (_, i) => rows[(i / 320) | 0]), w: 320, h: rows.length }, 0, y, copy);
        draw(A.overlay, 0, 0, copy);
        for (const [sc, dy, colour] of [[red, 14, RED], [blue, 326, BLUE]])
            for (const l of sc.letters) {
                const nb = l.ltr - 32;
                draw(A.font, l.posx, dy, () => colour, { sx: (nb % 16) * 32, sy: (nb >> 4) * 32, w: 32, h: 32 });
            }
        draw(A.mask, 0, 146, (p, X, Y) => { // source-atop rasters at y1, then y2
            const row = sample(Y) - 146 - (brk === "raster" ? 1 : 0);
            const r2 = row - s.y2, r1 = row - s.y1;
            const r = r2 >= 0 && r2 < 168 ? r2 : r1 >= 0 && r1 < 168 ? r1 : -1;
            return r < 0 ? 0 : A.rasters[r >> 1];
        });
        for (let i = 0; i < 14; i++) {
            if (LETTERS[i] === " ") continue;
            const img = A.sprites[LETTERS[i]];
            for (let Y = 0; Y < 200; Y++) {
                const v = Math.floor(sample(Y) + 0.5 - s.py[i]);
                if (v < 0 || v >= 32) continue;
                for (let X = 0; X < 320; X++) {
                    const u = Math.floor(sample(X) + 0.5 - s.px[i]);
                    if (u < 0 || u >= 32) continue;
                    const p = img.px[(v >> 1) * 16 + (u >> 1)];
                    if (p) map[Y * 320 + X] = p;
                }
            }
        }
        for (const dy of [0, 312]) draw(A.theunion, 0, dy, (p, X, Y) => {
            if (p < BLEND_BASE || p >= BLEND_BASE + 18) return p;
            const k = UNDER.indexOf(map[Y * 320 + X]);
            if (k < 0) throw new Error(`theunion soft edge over index ${map[Y * 320 + X]} at ${X},${Y}`);
            return p + k;
        });
        return map;
    }
    return { step, render, state: s };
}
