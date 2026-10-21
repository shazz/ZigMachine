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
//                (turning <-> horizontal), 3 the ramp (the gradient <-> at
//                most 16 palette writes on EVERY line, counted line by line
//                over a sweep), each back to where it started;
//                Space still leaves, and leaving closes the borders again
const CONTENT_Y = 20, CONTENT_H = 240;
const K_SCROLLER = 0x31, K_RASTERS = 0x32, K_COLOURS = 0x33; // '1', '2', '3'
const CAP = 16; // cap16.zig's LIMIT
const CAP_FRAMES = 60; // a fifth of a turn: every angle from ~1.6 rad on

/// Entries that differ between two lines' buckets.
const diff = (a, b) => a.reduce((n, v, i) => n + (v !== b[i] ? 1 : 0), 0);
/// The most palette entries any line wrote (line 0 is loaded before the beam).
const maxWrites = (c) => c.palettes.slice(1).reduce((m, p, y) => Math.max(m, diff(p, c.palettes[y])), 0);

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

    /// Key 3 from ZIG's gradient (`c`, this frame's census): capped, every line
    /// of every frame of a sweep writes at most CAP entries; pressed again,
    /// the gradient's finer ramp is back.
    function colours(c) {
        const fine = { count: c.count, writes: maxWrites(c) };
        press(K_COLOURS);
        let worst = 0;
        for (let i = 0; i < CAP_FRAMES; i++) {
            run(1);
            const d = census();
            worst = Math.max(worst, maxWrites(d));
            if (i === CAP_FRAMES - 1) c = d;
        }
        console.log(`  3: capped over ${CAP_FRAMES} frames: at most ${worst} writes a line (gradient: ${fine.writes}), ${c.count} buckets (gradient: ${fine.count})`);
        check(`3: at most ${CAP} palette writes on every line of every frame`, worst <= CAP, true);
        check("... still a ramp of many buckets, and the bars still turn", c.count > 16 && c.tilted > 200, true);
        press(K_COLOURS);
        run(1);
        const back = census();
        check("3 again: the gradient is back (more than 16 writes a line where it needs them)",
            maxWrites(back) > CAP, true);
    }

    /// From ORIGINAL with the bars home: into ZIG, through the keys, and out.
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
        colours(c);
        fire();
        run(returnFrames);
        c = census();
        check("Space leaves ZIG: bars home, scroller flat", c.count === 1 && c.tilted === 0 && scrollerFlat(c), true);
        closed(c, "ORIGINAL after the keys");
    }

    return { borders, closed, keys };
}
