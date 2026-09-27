// SKYSTRIKE ZIG-mode harness, the other screens' layout (zig_settings.zig,
// zig_screens.zig, zig_intro.zig, zig_scroller.zig, zig_hall.zig): where the
// 320 x 200 screen sits in the 400 x 280 frame, the old 5/4 scaling (the
// hall's picture keeps it; --break intro / hiscore expect it everywhere),
// the scroller's colour, and the buffers ZIG keeps (zig_testapi.zig ptrs).
import { WIN_W } from "./skystrike_zig_session.mjs";

export const SX = 40, SY = 40;             // screen_x, screen_y
export const BAND = 240;                   // the bottom border's first line
export const SCROLL_Y = 251;               // scroller_y
export const CREDITS_Y = SCROLL_Y - 10;    // zig_credits.zig: the music's credits line
export const HUD_MARGIN = 10;              // hud_bottom_margin
export const ZX = 80, ZY = 40, ZW = 176, ZH = 8; // the title's SCROLL 1 zone
export const SHIFT = 393 - 240;            // the scroller's letters, right of the original's
export const KIND = { picture: 0, scene: 1, hall: 2 };
const Y0 = 15, SH = 250, CLEAR = 255;

const gun = (n) => Math.floor((n & 7) * 255 / 7);
export const rgba = (w) => (0xff000000 | gun(w) << 16 | gun(w >> 4) << 8 | gun(w >> 8)) >>> 0;
const hw = (s) => [...new Uint16Array(s.memory.buffer.slice(s.demo.skyTestPtr(4), s.demo.skyTestPtr(4) + 32))];
export const palette = (s) => hw(s).map(rgba);

/// scroller_rgb (0x777) with no channel above the brightest register now.
export function ink(s) {
    let top = 0;
    for (const c of hw(s)) top = Math.max(top, c >> 8 & 7, c >> 4 & 7, c & 7);
    const m = Math.min(7, top);
    return rgba(m << 8 | m << 4 | m);
}

export const buf = (s, p, n) => new Uint8Array(s.memory.buffer, s.demo.skyTestPtr(p), n);
export const zone = (s) => buf(s, 8, ZW * ZH);
export const tiles = (s) => buf(s, 9, WIN_W * BAND);
export const hallPic = (s) => buf(s, 10, 64000);
export const hallText = (s) => buf(s, 11, 64000);

function mostly(p, y) {
    const n = new Array(16).fill(0);
    for (let x = 0; x < 320; x++) n[p[y * 320 + x] & 15]++;
    let best = 0;
    for (let c = 1; c < 16; c++) if (n[c] > n[best]) best = c;
    return best;
}

/// A 320 x 200 picture scaled by 5/4 into the frame, the bands above and
/// below in the colour most of its top / bottom line is (indices).
export function scaled(p) {
    const out = new Uint8Array(WIN_W * 280);
    const top = mostly(p, 0), bottom = mostly(p, 199);
    for (let y = 0; y < 280; y++) for (let x = 0; x < WIN_W; x++) {
        let c;
        if (y < Y0) c = top;
        else if (y >= Y0 + SH) c = bottom;
        else c = p[Math.floor((y - Y0) * 4 / 5) * 320 + Math.floor(x * 4 / 5)];
        out[y * WIN_W + x] = c;
    }
    return out;
}

/// The hall as ZIG draws it: the picture scaled, the text 1:1 where the
/// physic screen holds it (the text scaled with the rest if `broke`).
export function hallFrame(pic, text, physic, broke) {
    if (broke) return scaled(physic);
    const out = scaled(pic);
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const t = text[y * 320 + x];
        if (t !== CLEAR && physic[y * 320 + x] === t) out[(SY + y) * WIN_W + SX + x] = t;
    }
    return out;
}

/// The hall's text is exactly what the game drew over the picture: every
/// text pixel on the physic screen, every changed pixel in the text.
export function textIsTheGames(pic, text, physic) {
    let missing = 0, extra = 0, n = 0;
    for (let i = 0; i < 64000; i++) {
        if (text[i] !== CLEAR) { n++; if (physic[i] !== text[i]) missing++; }
        else if (physic[i] !== pic[i]) extra++;
    }
    return { n, missing, extra };
}

/// Pixels of a frame region (x0..x1, y0..y1) where `f(x, y)` is false.
export function misses(x0, x1, y0, y1, f) {
    let bad = 0, first = null;
    for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) if (!f(x, y)) { bad++; first ??= `x ${x} y ${y}`; }
    return { bad, first, of: (x1 - x0) * (y1 - y0) };
}
