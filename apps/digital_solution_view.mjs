// The Digital Solution as pixels, and the two DECLARED BLIND SPOTS of the
// picture check — split out of apps/digital_solution_headless.mjs so that
// harness stays inside the 200-line rule.
//
// An exclusion with nothing behind it is how a bug hides, so each of the two
// has its compensating check here beside it: the scrolltext band (readBand /
// shadow, in digital_solution_band.mjs) and the cycling TEXT (walkCycle).
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { BAND_ROWS, BAND_H, CW, CH, LEFT, TOP, DIGITAL_BAND_Y, pixelsOf, atPlane, readBand } from "./digital_solution_band.mjs";

export const TEXT = 130;   // the one appended index that is not grey: every character
const CYCLE_W = 32, CYCLE_H = 5; // one cycle.raw tile, halved
/// A.DIGITAL_CYCLE_STEP. The text cycles SLOWER than the jukebox's bands
/// (Matt); the exact increment is not known and this half-speed is provisional,
/// so it is mirrored from the scene here rather than hard-coded twice.
export const CYCLE_STEP = readStep();
function readStep() {
    const m = /pub const DIGITAL_CYCLE_STEP: f64 = ([\d.]+);/.exec(
        readFileSync("apps/zig/scenes/big/assets.zig", "utf8"));
    if (!m) throw new Error("big/assets.zig has no DIGITAL_CYCLE_STEP");
    return +m[1];
}

/// The text's cycle tile after `n` frames inside the Digital Solution,
/// accumulated in DOUBLE exactly as the scene does it. An integer
/// floor(step*n) is NOT the same sequence — the drift is the effect.
export function tileAt(n) {
    let acc = 0;
    for (let k = 0; k < n; k++) acc += CYCLE_STEP;
    return Math.floor(acc) % 8;
}

/// The colour that tile paints, read out of cycle.raw itself rather than a
/// table copied from it — the first pixel of tile t, which walks 9..16.
export const cycleColour = (bigPal, cyc, tile) => {
    const i = cyc[tile * CYCLE_H * CYCLE_W] * 4;
    return [bigPal[i], bigPal[i + 1], bigPal[i + 2]];
};

/// The Digital Solution as pixels, against its own reference.
///
/// TWO things are skipped and each is paid for. Rows BAND_ROWS are the
/// scrolltext (see above). And the TEXT pixels do not have a fixed colour —
/// every character on this screen is one palette entry and it CYCLES — so
/// hashStill() leaves them out and diff() checks them against the colour the
/// cycle should be on, which is a stronger check than a constant would be:
/// it proves the cycle lands on exactly the right pixels and nowhere else.
export function view(memory, machine, raw, pal) {
    const inBand = (y) => y >= BAND_ROWS[0] && y < BAND_ROWS[1];
    const buf = () => pixelsOf(memory, machine);
    const first = raw.indexOf(TEXT); // some character's first pixel
    return {
        /// What the text is actually painted in, right now.
        textRGB() {
            const g = atPlane(buf(), machine.hwPhysWidth(), first % CW, TOP + Math.floor(first / CW));
            return [g[0], g[1], g[2]];
        },
        band: () => readBand(memory, machine, DIGITAL_BAND_Y),
        /// The still part, TEXT pixels excluded: unchanged frame to frame.
        hashStill() {
            const b = buf(), PW = machine.hwPhysWidth(), h = createHash("sha256");
            for (let y = 0; y < CH; y++) if (!inBand(y)) for (let x = 0; x < CW; x++)
                if (raw[y * CW + x] !== TEXT) h.update(atPlane(b, PW, x, TOP + y));
            return h.digest("hex");
        },
        /// "" when every still pixel is screen.raw through pal.dat, with the
        /// TEXT pixels at `textRGB` — the cycle colour for this frame.
        diff(textRGB) {
            const b = buf(), PW = machine.hwPhysWidth();
            let wrong = 0, where = null, text = 0;
            for (let y = 0; y < CH; y++) if (!inBand(y)) for (let x = 0; x < CW; x++) {
                const ix = raw[y * CW + x], g = atPlane(b, PW, x, TOP + y);
                const w = ix === TEXT ? [...textRGB, 255] : [pal[ix * 4], pal[ix * 4 + 1], pal[ix * 4 + 2], pal[ix * 4 + 3]];
                if (ix === TEXT) text++;
                if (g[0] === w[0] && g[1] === w[1] && g[2] === w[2] && g[3] === w[3]) continue;
                wrong++; where ??= `(${x},${y})${ix === TEXT ? " [text]" : ""} is rgba(${g}) not rgba(${w})`;
            }
            if (!text) return "screen.raw has no TEXT pixels: the cycle check is vacuous";
            return wrong ? `${wrong} of ${CW * (CH - BAND_H)} still px differ from screen.raw: first ${where}` : "";
        },
    };
}

/// The reference files, and the one measurement that justifies treating the
/// text as a cycle colour at all.
///
/// The capture's text is #8d12e9 and cycle.raw's tile 4 is #8000e0: two
/// different palettes (an emulator's ladder and the remake's), the same ST
/// levels (4,0,7). If that equality ever stopped holding, the text would be a
/// colour of its own and the whole cycle would be an invention — so it is
/// measured here rather than asserted in a comment.
export async function refs(art) {
    const rd = async (f) => new Uint8Array(await readFile(f));
    const r = {
        raw: await rd(`${art}/screen.raw`), pal: await rd(`${art}/pal.dat`),
        bigPal: await rd("apps/zig/assets/screens/big_demo/pal.dat"),
        cyc: await rd("apps/zig/assets/screens/big_demo/cycle.raw"),
        errors: [],
    };
    if (r.raw.length !== CW * CH) r.errors.push(`screen.raw is ${r.raw.length} bytes, not 320x200`);
    const level = (v, lo, hi) => Math.round(((v - lo) / (hi - lo)) * 7);
    const cap = [...r.pal.slice(TEXT * 4, TEXT * 4 + 3)].map((v) => level(v, 0x11, 0xe9));
    const cy = cycleColour(r.bigPal, r.cyc, 4).map((v) => level(v, 0x00, 0xe0));
    if (cap.join() !== cy.join())
        r.errors.push(`the capture's text colour is ST ${cap.join()} but cycle tile 4 is ST ${cy.join()}: the text is NOT a cycle colour`);
    return r;
}

/// The band must be a real scroller, not a rectangle: many colours, and every
/// one of them either the panel it sits on or a colour the JUKEBOX's font can
/// paint (big_demo's palette below `base`, where this screen's own colours are
/// appended). A band drawn from a second, re-ripped font would fail this.
export function bandColourErrors(b0, bigPal, pal, base, panelIndex) {
    const errors = [];
    const shared = new Set();
    for (let i = 0; i < base; i++) shared.add(`${bigPal[i * 4]},${bigPal[i * 4 + 1]},${bigPal[i * 4 + 2]}`);
    const panel = `${pal[panelIndex * 4]},${pal[panelIndex * 4 + 1]},${pal[panelIndex * 4 + 2]}`;
    if (b0.colours.size < 9) errors.push(`the band shows ${b0.colours.size} colours: the fontbg fill alone is 8, so it is not drawing`);
    const alien = [...b0.colours].filter((c) => c !== panel && !shared.has(c));
    if (alien.length) errors.push(`the band paints ${alien.length} colour(s) that are not the shared font's or the panel: ${alien[0]}`);
    return errors;
}

/// Walk the text through a full cycle and compare it with what the accumulator
/// says it should be. This is what pays for hashStill() leaving the TEXT pixels
/// out: a text stuck on one colour, on the wrong phase, or running at the
/// jukebox's faster rate all fail here.
export function walkCycle(V, bigPal, cyc, tileNow, step) {
    const got = [], want = [];
    for (let k = 0; k < Math.ceil(8 / CYCLE_STEP) + 4; k++) {
        got.push(V.textRGB().join());
        want.push(cycleColour(bigPal, cyc, tileNow()).join());
        step();
    }
    const errors = [];
    if (new Set(got).size < 8) errors.push(`the text shows ${new Set(got).size} of the 8 cycle colours: it is not cycling through them`);
    if (got.join("|") !== want.join("|"))
        errors.push(`the text cycle is ${got.slice(0, 6).join(" ")}..., += ${CYCLE_STEP} gives ${want.slice(0, 6).join(" ")}...`);
    return { got, errors };
}
