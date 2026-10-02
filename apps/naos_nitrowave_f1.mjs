// F1 (Ric's multisprites) in the NAOS NITROWAVE harness. F1 is ported BEST
// EFFORT (Matt, 2026-10-02): on the ST its colour changes and its screen
// writes were cycle races, which the port places at their nominal lines, so
// its frames are held to Hatari's by SIMILARITY, not equality. The reference
// (apps/naos_nitrowave_ref.json.gz "ric", prototypes/naos_nitrowave_re/
// make_ref.py) holds, per figure, captures counted from the main loop's first
// VBL; the title is the same in every run.
//   figure   chosen as the original does, by chance: the menu's VBL count at
//            the key, halved, mod 4 -- so F1 pressed 2F VBLs into the menu
//            flies figure F. Each of the four is entered and recognised
//   title    shown as long as the set-up took on the ST for that figure,
//            silent; then the part, asking for its own tune
//   frames   each held to its capture over the plane rows Hatari captures:
//            at least SIMILAR of the pixels the same ST colour, and, once the
//            figure shows (the shifter follows the drawn screens from VBL
//            100, or 140 for figure 3), closer to its own figure's capture
//            than to any other figure's
//   motion   the figure's frames differ over time; F1 freezes the part, F2
//            lets it go on
// --break figure: every figure held against the next figure's capture.
const TITLE_VBLS = [747, 748, 672, 594]; // ric.zig
const TUNE = "robocop_tune_2.sndh";
const SIMILAR = 0.99; // measured 99.66..99.84%; another figure scores ~82%
const ROW0 = 11; // physical row of capture row 0
const KEY = { space: 32, f1: 0xe001, f2: 0xe002 };
const SHOWN = 150; // from this VBL every figure's screens show

/// The share of the captured rows where two planes show the same colour.
function similarity(a, b) {
    let same = 0;
    for (let i = ROW0 * 400; i < a.length; i++) if (a[i] === b[i]) same++;
    return same / (a.length - ROW0 * 400);
}

export async function checkF1(h) {
    const { demo, plane, refs, words, unz, errors, broke, ppm, outdir, VBL_MS, song } = h;
    const ric = refs.ric;
    const title = words(unz(ric.title));
    const figRef = (f) => {
        const r = ric.figures[f], base = words(unz(r.base));
        const m = new Map([[r.first, base]]);
        for (const [k, v] of Object.entries(r.frames)) m.set(Number(k), words(unz(v)).map((b, i) => b ^ base[i]));
        return m;
    };
    const all = [0, 1, 2, 3].map(figRef);
    const step = (n) => { for (let i = 0; i < n; i++) demo.frame(VBL_MS); };
    for (let f = 0; f < 4; f++) {
        if (f > 0) { // the menu again, its VBL count from 0 (figure 0: the menu at VBL 1)
            demo.key(KEY.space);
            step(2 * f);
        }
        demo.key(KEY.f1);
        step(100);
        const t = plane();
        const ts = similarity(t, title);
        if (ts < 1) errors.push(`F1 figure ${f}: the title is ${(100 * ts).toFixed(2)}% the capture's, not all of it`);
        if (song() !== "none") errors.push(`F1 figure ${f}: the title is not silent (${song()})`);
        step(TITLE_VBLS[f] - 100 + 1); // the main loop's first VBL: model frame 0
        if (song() !== `${TUNE} #1`) errors.push(`F1 figure ${f} music: asked for ${song()}, not ${TUNE} #1`);
        const want = all[broke === "figure" ? (f + 1) % 4 : f];
        let frame = 0, worst = 1;
        const got = [];
        for (const k of [...want.keys()].sort((a, b) => a - b)) {
            step(k - frame);
            frame = k;
            const p = plane();
            got.push(p);
            await ppm(`${outdir}/ric${f}_${String(k).padStart(5, "0")}.ppm`, p);
            const s = similarity(p, want.get(k));
            worst = Math.min(worst, s);
            const other = Math.max(...[0, 1, 2, 3].filter((g) => g !== f && all[g].has(k)).map((g) => similarity(p, all[g].get(k))));
            if (s < SIMILAR) errors.push(`F1 figure ${f} frame ${k}: ${(100 * s).toFixed(2)}% of the pixels as Hatari's, under ${100 * SIMILAR}%`);
            else if (k >= SHOWN && other >= s) errors.push(`F1 figure ${f} frame ${k}: as close to another figure's capture (${(100 * other).toFixed(2)}%) as to its own`);
            if (h.verbose) console.log(`    figure ${f} frame ${k}: ${(100 * s).toFixed(2)}% (best other figure ${(100 * other).toFixed(2)}%)`);
        }
        if (similarity(got.at(-1), got.at(-2)) === 1) errors.push(`F1 figure ${f}: two frames the same, nothing moves`);
        console.log(`  F1 figure ${f}: title as captured, then ${got.length} frames to ${frame}, each at least ${(100 * worst).toFixed(2)}% Hatari's pixels; ${TUNE} #1`);
    }
    freeze(h, step);
}

/// The original's keys: F1 switches to its frozen VBL, F2 back.
function freeze({ demo, plane, errors }, step) {
    demo.key(KEY.f1);
    step(3);
    const a = plane();
    step(10);
    const b = plane();
    demo.key(KEY.f2);
    step(10);
    const c = plane();
    if (similarity(a, b) !== 1) errors.push("keys: F1 does not freeze the multisprites");
    else if (similarity(b, c) === 1) errors.push("keys: F2 does not let the multisprites go on");
    else console.log("  keys: F1 freezes the multisprites and F2 lets them go");
}
