// The scroller band along the bottom of the Digital Solution — the geometry and
// the two helpers apps/digital_solution_headless.mjs needs to cover it. Split
// out so that harness stays inside the 200-line rule.
//
// WHY THIS FILE EXISTS AT ALL. The harness asserts every visible pixel of the
// Digital Solution against the capture — except these 16 rows, which cannot be:
// the scroll offset at capture time is unknown, and the remake's 41,351-char
// transcription does not contain the fragment visible in the capture anywhere,
// so its text may not even be the real screen's. An excluded region is exactly
// where two real bugs survived six zero-difference frames on big_demo until
// Matt spotted them by eye, so the exclusion is paid for with the checks below.
import { createHash } from "node:crypto";
import { boot } from "./big_demo_machine.mjs";

export const BAND_ROWS = [179, 195]; // rows of the 320x200 the scroller owns; 16 = A.SCROLL_H
export const BAND_H = BAND_ROWS[1] - BAND_ROWS[0];
export const CW = 320, CH = 200, LEFT = 40, TOP = 40; // the picture, and where it sits in the 400x280 plane
/// The band's top row in PLANE coordinates, on each screen. The Digital
/// Solution's picture starts at plane row 40 (big/digital.zig Y), the jukebox's
/// content at plane row 5 (A.TOP) with its band at A.SCROLL_Y = 222.
export const DIGITAL_BAND_Y = 40 + BAND_ROWS[0]; // 219
export const JUKEBOX_BAND_Y = 5 + 222; // 227

export const pixelsOf = (memory, machine) =>
    new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), machine.hwPhysWidth() * machine.hwPhysHeight() * 4);
/// A pixel of the plane, by PLANE row: the physical frame is 800 wide and the
/// visible x is doubled, while y maps straight through on an overscan plane.
export const atPlane = (buf, PW, x, planeY) => { const o = (planeY * PW + 2 * (LEFT + x)) * 4; return buf.subarray(o, o + 4); };

/// The band as pixels: a hash for comparing two runs, and the set of colours in
/// it for proving it is not a flat rectangle.
export function readBand(memory, machine, planeY0) {
    const buf = pixelsOf(memory, machine), PW = machine.hwPhysWidth();
    const h = createHash("sha256"), colours = new Set();
    for (let y = 0; y < BAND_H; y++) for (let x = 0; x < CW; x++) {
        const p = atPlane(buf, PW, x, planeY0 + y);
        h.update(p);
        colours.add(`${p[0]},${p[1]},${p[2]}`);
    }
    return { hash: h.digest("hex"), colours };
}

/// A SECOND machine running the same cart, which opens the Digital Solution
/// LATER than the run under test and then stays there.
///
/// This is what proves the scrolltext CARRIES ON rather than restarting, and it
/// compares like with like: both bands are the Digital Solution's, on the same
/// flat panel, so they must be pixel-identical at the same ABSOLUTE frame — and
/// they only can be if the scroller advanced once per frame throughout, on both
/// screens, and was never reset. If it restarted on entry each run would be
/// (now - its own entry frame) steps in, and the two entries differ on purpose.
///
/// (Comparing against a machine left in the JUKEBOX does not work and is not a
/// port bug: the jukebox's band sits on main.png's own grey and rows 224..229
/// of it are re-coloured by the 50%-shadow strip drawn after the scroller, so
/// the two bands are the same glyphs on different backgrounds.)
export async function shadow(cartPath, { waitFrames, rows, delay }) {
    const { memory, machine, demo } = await boot(cartPath);
    let frame = 0;
    const step = () => {
        machine.hwClear();
        demo.frame(1000 / 60);
        for (let p = 0; p < 4; p++) if (demo.isPlaneEnabled(p)) machine.hwRenderPlane(p);
        frame++;
    };
    const runTo = (n) => { while (frame < n) step(); };
    runTo(waitFrames + 1);                               // go() has taken over
    for (let k = 0; k < rows; k++) { demo.input(1); step(); } // down to the Digital Department row
    runTo(frame + delay);                                // ...and dawdle there, unlike the run under test
    demo.key(13); step();                                // Return: the screen opens
    return { get frame() { return frame; }, runTo, band: () => readBand(memory, machine, DIGITAL_BAND_Y) };
}

