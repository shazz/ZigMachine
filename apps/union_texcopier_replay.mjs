// The Union Demo TEX COPIER (screens/texcopier/screen.js), replayed in JS for
// apps/union_texcopier_headless.mjs. It follows screen.js, not the scene.
//
// update() (screen.js:168-205): the counters, the raster window reset every 104
// frames, selectTexture (244-299) and selectText (301-330), then the keys.
// draw() (212-242) in CANVAS units (640x400):
//   - fill black; six raster windows drawPart(0, rastersPos[i], 0, rasterScrollY-4i,
//     640, 32) once timeToRaster (the `== false` at 177 is a no-op: never reset);
//   - display.png at (160,74);
//   - the text line: the texture at (scrollerRastersPos, 0) on a 640x14 canvas,
//     the font's black field printed over it, the canvas at (0,360).
// Chrome resamples the two fractional draws (a source y of k*2.5 - 4i, an x of
// k*0.5) bilinearly: a pixel between two texels is their 50/50 mix, each channel
// (a+b)>>1, transparent counting as 0 over the black canvas. This replay matched
// the remake running in Chrome on EVERY pixel of canvas column 0 and of the text
// line's even rows over frames 1..1000 (Space at 700), and full frames at even
// coordinates.
//
// The ST pixel (X,Y) is the canvas pixel (2X,2Y).
//
// It reads the converted assets (texcopier.bin, pal.dat); the conversion was
// checked against Chrome running the remake's own PNGs.

export const POS = [225, 192, 160, 128, 96, 64]; // rastersPos (screen.js:66)
const FADE_TIMES = [5, 10, 15, 20, 25, 30, 35, 40]; // screen.js:65
const TEXT = [ // screen.js:78-110; text[29] is missing in the remake
    "    COPY-PROGRAM BY 6719 AND MAD MAX     ", "        PRESS SPACE TO START COPY        ",
    "WHAT DO YOU THINK ABOUT THIS LITTLE COPY ", "    IT'S THE FIRST ONE WITH RASTERS,     ",
    "        AND MUZAK WHILE COPYING          ", "   AND IT TELLS YOU A LOT OF CRAP TALK   ",
    "   EXCUSE US FOR NOT USING ANY BORDER    ", "   OR FOR ABSENCE OF TRACKING-SPRITES    ",
    " BUT WE WANTED TO READ A WHOLE DISK-SIDE ", "             INTO HALF-A-MEG             ",
    " AND THIS MEANS, THAT WE NEED MEMORY !!! ", "DO YOU THINK THIS COPY IS A BIT TOO SLOW ",
    "REMEMBER, THIS DISC CONTAINS 900 KB DATA ", "          PRETTY MUCH ? YES !!           ",
    "   WE ARE USING A VERY SPECIAL FORMAT    ", "AND THAT TAKES IT'S TIME TO FORMAT WRITE ",
    "              AND VERIFY !!              ", "  AND, AFTER ALL, YOU SHALL HEAR THAT    ",
    "    FANTASTIC SOUNDTRACK COMPLETELY !    ", "  AND NOW SOME OF THE LATEST TEX-NEWS:   ",
    " SOME PEOPLE OF TEX ARE NOW PROFESSIONAL ", "             GAME-DESIGNERS              ",
    " OF COURSE WE WON'T SAY AT WHICH COMPANY ", "BUT WE ARE SURE YOU'LL RECOGNIZE US..... ",
    "      JUST SEE AND HEAR IF YOU'RE        ", "     BUYING NEW GAMES KNOWING THIS       ",
    "    YOU WON'T BE SURPRISED TO HEAR:      ", "  TEX WON'T CRACK ANY GAMES NO MORE!     ",
    " BUT DON'T WORRY: IF WE HAVE THE TIME,   ", undefined,
    " WE'LL CONTINUE TO MAKE DEMOS BIT BY BIT ", "  OK GUYS, NO MORE SPACE FOR TEXT LEFT.  ",
    "   LET'S START ANEW.  BYE, BYE FOLKS!!   ", "                                         ",
];
const COPY0 = " PLEASE INSERT WRT-PROTECTED SOURCE-DISK "; // copy[0], the only one ever shown

/// Frames compared pixel for pixel: the raster reset (104/105), a half-pixel
/// texture step, text 1's fade out and in, Space, the orange fade-in, a later
/// raster image, and the missing text[29].
export const SHOTS = [1, 2, 60, 104, 105, 107, 150, 209, 421, 430, 461, 700, 720, 741, 761, 1000, 12650];
export const SPACE_AT = 700; // the update that sees Space pressed

export function makeReplay(bin, pal, opts = {}) {
    const mix = opts.mix ?? ((a, b) => (a + b) >> 1);
    const period = opts.rasterPeriod ?? 104;
    let at = 0;
    const take = (n) => { const v = bin.subarray(at, at + n); at += n; return v; };
    const display = take(160 * 87), font = take(160 * 21);
    const tex = { blue: take(1280 * 7), orange: take(1280 * 7) };
    const rasters = take(8 * 16 * 3);
    if (at !== bin.length) throw new Error(`texcopier.bin is ${bin.length} bytes, layout says ${at}`);
    const rgb = (i) => [pal[i * 4], pal[i * 4 + 1], pal[i * 4 + 2]];
    const BASE = { blue: 15, orange: 22 };

    const s = {
        globalTime: 0, time: 0, textureTime: 0, isCopying: false, askToCopy: 0, fadeOutCompleted: true,
        currentText: 0, nextText: 0, rasterScrollY: 0, scrollerRastersPos: -640, rasterTexture: 0, timeToRaster: false,
        texture: { set: "blue", level: 0 }, frames: 0,
    };

    function selectTexture() {
        const k = FADE_TIMES.filter((t) => t <= s.textureTime).length;
        const set = s.isCopying ? "orange" : "blue";
        if (k < 8) s.texture = { set, level: s.fadeOutCompleted ? 7 - k : k };
        else if (!s.fadeOutCompleted) s.fadeOutCompleted = true;
    }
    function selectText() {
        if (s.isCopying) return;
        const index = Math.floor(s.time / (7 * 60));
        if (index !== s.nextText || s.askToCopy === 1) {
            s.textureTime = 0; s.nextText = index; s.fadeOutCompleted = false;
            if (s.askToCopy === 1) s.askToCopy = 2;
        }
        if (s.fadeOutCompleted && s.currentText !== s.nextText) { s.textureTime = 0; s.currentText = s.nextText; }
        if (index > TEXT.length - 1) s.time = 0;
        if (s.askToCopy === 2 && s.fadeOutCompleted) { s.isCopying = true; s.textureTime = 0; s.currentText = s.nextText = 0; }
    }
    function update(space) {
        s.globalTime++; s.time++; s.textureTime++;
        s.rasterScrollY += 2.5;
        s.scrollerRastersPos += 0.5;
        if (s.scrollerRastersPos >= 0) s.scrollerRastersPos = -640;
        if (s.globalTime % period === 0) { s.timeToRaster = true; s.rasterScrollY = 0; s.rasterTexture++; }
        selectTexture();
        selectText();
        if (space) { s.time = 0; s.askToCopy = 1; }
        s.frames++;
    }

    // ---- draw, canvas units -------------------------------------------------
    const rasterRow = (r) => { // raster image row r: its colour, or null
        if (r < 32 || r >= 64) return null;
        const o = ((s.rasterTexture % 8) * 16 + ((r - 32) >> 1)) * 3;
        return [rasters[o], rasters[o + 1], rasters[o + 2]];
    };
    const blend = (a, b) => [0, 1, 2].map((c) => mix(a ? a[c] : 0, b ? b[c] : 0));
    const sample = (get, v) => { // bilinear at texel coordinate v (a multiple of 0.5)
        const i = Math.floor(v);
        return v === i ? get(i) : blend(get(i), get(i + 1));
    };
    const BLACK = [0, 0, 0];
    function rasterPixel(d) {
        if (!s.timeToRaster) return BLACK;
        for (let i = 0; i < 6; i++) {
            if (d < POS[i] || d >= POS[i] + 32) continue;
            return sample(rasterRow, s.rasterScrollY - 4 * i + (d - POS[i])) ?? BLACK;
        }
        return BLACK;
    }
    function textPixel(c, r) { // r even
        const line = s.isCopying ? COPY0 : TEXT[s.currentText];
        if (line === undefined) return BLACK; // font.print(undefined) throws before the text canvas is drawn
        const ch = line.charCodeAt(Math.floor(c / 16)) - 32;
        if (font[((Math.floor(ch / 20) * 7) + (r >> 1)) * 160 + (ch % 20) * 8 + (Math.floor(c / 2) % 8)]) return BLACK;
        const removed = s.texture.set === "blue" ? s.texture.level : Math.min(s.texture.level, 6);
        const texel = (t) => {
            const id = tex[s.texture.set][(r >> 1) * 1280 + t];
            return id > removed ? rgb(BASE[s.texture.set] + id - 1) : null;
        };
        return sample(texel, c - s.scrollerRastersPos) ?? BLACK;
    }
    function canvasPixel(c, d) {
        if (d >= 360 && d < 374) return textPixel(c, d - 360);
        if (c >= 160 && c < 480 && d >= 74 && d < 74 + 174) return rgb(display[((d - 74) >> 1) * 160 + ((c - 160) >> 1)]);
        return rasterPixel(d);
    }
    function st() {
        const img = new Uint8Array(320 * 200 * 3);
        for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) img.set(canvasPixel(2 * x, 2 * y), (y * 320 + x) * 3);
        return img;
    }
    return { state: s, update, rasterPixel, textPixel, canvasPixel, st };
}
