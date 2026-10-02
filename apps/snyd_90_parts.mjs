// The best-effort parts of SWEDISH NEW YEAR DEMO 89-90 (F3..F6) for
// apps/snyd_90_headless.mjs. They are not byte-identical to the original (the
// cycle races of their interrupts are approximated), so each is checked for:
//   motion   the window's indices differ from shot to shot;
//   look     its colours against Hatari's capture of the real part: the share
//            of each ST colour word over the window column, lines 0..rows-1
//            (past 199 the opened bottom border), histogram intersection
//            >= LOOK (prototypes/snyd90_re/hatari_ref.py makes the reference);
//   borders  where the original opens one (open: "bottom" / "all"), the plane
//            shows picture there; where it does not, the border is one colour
//            a line.
// The song request and its playing are checked with the others.
export const LOOK = 0.8;

/// Per part: its F key, the frames it runs, the shots, which borders it opens.
export const PARTS = [
    { key: 3, name: "f3", frames: 300, shots: [2, 100, 300], open: "bottom" },
];

/// Hatari's capture of the real parts (hatari_ref.py over frames of run_hatari.sh).
const REF = {
    f3: { rows: 240, colours: { 0x000: 0.4793, 0x003: 0.2021, 0x005: 0.1281, 0x002: 0.0439, 0x500: 0.0387, 0x014: 0.0302, 0x300: 0.0231, 0x027: 0.0209, 0x702: 0.0187, 0x004: 0.0089, 0x001: 0.0035 } },
};

const word = (rgb, i) => (Math.round(rgb[i] * 7 / 255) << 8) | (Math.round(rgb[i + 1] * 7 / 255) << 4) | Math.round(rgb[i + 2] * 7 / 255);

/// Shares of ST colour words over the window column, ST lines 0..rows-1.
function shares(rgb, PW, rows) {
    const h = new Map();
    let n = 0;
    for (let y = 40; y < Math.min(280, 40 + rows); y++) for (let x = 40; x < 360; x++) {
        const c = word(rgb, (y * PW + x) * 3);
        h.set(c, (h.get(c) || 0) + 1);
        n++;
    }
    for (const [c, k] of h) h.set(c, k / n);
    return h;
}

/// Histogram intersection of the shot with the part's reference.
export function look(name, rgb, PW) {
    const ref = REF[name];
    const have = shares(rgb, PW, ref.rows);
    let s = 0;
    for (const [c, p] of Object.entries(ref.colours)) s += Math.min(p, have.get(Number(c)) || 0);
    return s;
}

/// Why the borders are wrong for `open`, or null: rows 240..279 of the window
/// column carry picture only where the bottom is open; the side columns only
/// where every border is.
export function borders(open, rgb, PW) {
    const varied = (y, x0, x1) => {
        const c = word(rgb, (y * PW + x0) * 3);
        for (let x = x0 + 1; x < x1; x++) if (word(rgb, (y * PW + x) * 3) !== c) return true;
        return false;
    };
    let bottom = false, side = false;
    for (let y = 240; y < 280; y++) bottom ||= varied(y, 40, 360);
    for (let y = 40; y < 240; y++) side ||= varied(y, 0, 40) || varied(y, 360, 400);
    if (bottom !== (open === "bottom" || open === "all")) return `bottom border ${bottom ? "shows picture" : "is closed"}`;
    if (side !== (open === "all")) return `side borders ${side ? "show picture" : "are closed"}`;
    return null;
}
