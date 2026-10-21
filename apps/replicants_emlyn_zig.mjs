// ZIG mode's own checks for apps/replicants_emlyn_headless.mjs: the bars in the
// opened TOP and BOTTOM borders, and the 1 / 2 keys. The census it is handed is
// the harness's (bucket colours per PHYSICAL line, read back through the
// plane's HBL); BLACK_RGBA is a closed border's colour.
//
//   borders(c)   ZIG: the border lines carry raster colours, and crossing the
//                window's top or bottom edge changes no more entries than any
//                line inside does (the rotation runs on, no seam)
//   closed(c)    ORIGINAL: every border line is black, as before ZIG existed
//   keys(...)    1 toggles the scrolltext (curve <-> flat), 2 the bars
//                (turning <-> horizontal), each back to where it started;
//                Space still leaves, and leaving closes the borders again
const CONTENT_Y = 20, CONTENT_H = 240;
const K_SCROLLER = 0x31, K_RASTERS = 0x32; // '1', '2'

/// Entries that differ between two lines' used buckets.
const diff = (a, b) => a.reduce((n, v, i) => n + (v !== b[i] ? 1 : 0), 0);

export function makeZigChecks({ check, census, run, demo, fire, broke }) {
    function borders(c, what) {
        const L = c.lines;
        let inner = 0;
        for (let y = CONTENT_Y + 1; y < CONTENT_Y + CONTENT_H; y++) inner = Math.max(inner, diff(L[y], L[y - 1]));
        const top = diff(L[CONTENT_Y], L[CONTENT_Y - 1]);
        const bottom = diff(L[CONTENT_Y + CONTENT_H], L[CONTENT_Y + CONTENT_H - 1]);
        console.log(`  ${what}: ${c.tbLit}/40 border lines lit; entries changing at the top edge ${top}, bottom ${bottom}, inside at most ${inner}`);
        check(`${what}: the bars run on into the opened TOP and BOTTOM borders`, c.tbLit > 0, true);
        check(`${what}: ... continuously: no seam at the window's top or bottom edge`, top <= inner && bottom <= inner, true);
    }

    function closed(c, what) {
        check(`${what}: the top and bottom border lines stay black`, c.tbLit, 0);
    }

    const scrollerFlat = (c) => c.fontBottom - c.fontTop < 32;
    const press = (k) => { if (broke !== "keys") demo.key(k); };

    /// From ORIGINAL with the bars home: into ZIG, through both keys, and out.
    function keys(spinFrames, returnFrames) {
        press(K_SCROLLER);
        press(K_RASTERS);
        run(returnFrames);
        let c = census();
        check("ORIGINAL: 1 and 2 change nothing (bars flat, scroller flat, borders black)",
            c.count === 1 && c.tilted === 0 && scrollerFlat(c) && c.tbLit === 0, true);
        fire();
        run(spinFrames);
        c = census();
        check("ZIG again: both styles start on (bars turning, scroller bent)", c.tilted > 200 && !scrollerFlat(c), true);
        press(K_RASTERS);
        run(returnFrames);
        c = census();
        check("2: the bars go back to the original's horizontal ones", c.count === 1 && c.tilted === 0, true);
        // (horizontal bars never reach rows 0..19 or 260..279: the group spans
        // less than the window vertically, so the open borders stay black here)
        check("... and the scrolltext stays bent", !scrollerFlat(c), true);
        press(K_SCROLLER);
        run(returnFrames);
        c = census();
        check("1: the scrolltext flattens to the original's", scrollerFlat(c), true);
        press(K_RASTERS);
        press(K_SCROLLER);
        run(spinFrames);
        c = census();
        check("2 and 1 again: back where ZIG started, bars turning and scroller bent", c.tilted > 200 && !scrollerFlat(c), true);
        borders(c, "ZIG after the keys");
        fire();
        run(returnFrames);
        c = census();
        check("Space leaves ZIG: bars home, scroller flat", c.count === 1 && c.tilted === 0 && scrollerFlat(c), true);
        closed(c, "ORIGINAL after the keys");
    }

    return { borders, closed, keys };
}
