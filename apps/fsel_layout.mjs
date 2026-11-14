// The ITEM SELECTOR's layout per screen, from its pixels (gemtest_fsel_check.mjs): the font the screen
// draws it in (8x8 below 400 lines, 16 rows tall from 400: TOS 4's ST low/medium vs ST high/Falcon cells),
// the path as the box's title (centred, the spec's width), the list's rows one font height apart, the
// box on the screen. Flat look (white paper).
import { fselGeom } from "./fsel_geom.mjs";
import { MODES } from "./gemtest_lib.mjs";

const SIZE = [[320, 200], [640, 200], [640, 480]];

// Rows y0..y1-1 and columns x0..x1-1 that hold any pixel other than the paper.
function inkBox(px, x0, y0, x1, y1, paper) {
    let top = -1, bottom = -1, left = 1e9, right = -1;
    for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) if (px(x, y) !== paper) {
        if (top < 0) top = y;
        bottom = y; left = Math.min(left, x); right = Math.max(right, x);
    }
    return { top, bottom, left, right, h: top < 0 ? 0 : bottom - top + 1, w: right < 0 ? 0 : right - left + 1 };
}

// The row of most ink between y0 and y1 (an empty list row's ________.___ template line).
function inkiest(px, x0, x1, y0, y1, paper) {
    let best = -1, most = -1;
    for (let y = y0; y < y1; y++) {
        let n = 0;
        for (let x = x0; x < x1; x++) if (px(x, y) !== paper) n++;
        if (n > most) { most = n; best = y; }
    }
    return best;
}

export async function layout(mode, [d], spec, check) {
    const [sw, sh] = SIZE[mode], g = fselGeom(sw, sh), tag = `${MODES[mode]} layout`;
    d.point(2, sh - 10); d.frames(2);
    const { W, idx } = d.indices(), px = (x, y) => idx[y * W + x];
    const paper = px(g.box.x + g.box.w - 6, g.titleY + 2);
    check(`${tag}: the box (${g.box.w} x ${g.box.h}) is on the ${sw} x ${sh} screen`, g.box.x >= 0 && g.box.y >= 0 && g.box.x + g.box.w <= sw && g.box.y + g.box.h <= sh);
    const label = inkBox(px, g.dirLabel.x, g.dirLabel.y, g.dirLabel.x + 80, g.dirLabel.y + g.ch, paper);
    const tall = g.ch === 16;
    check(`${tag}: "Directory:" in the ${tall ? "8x16" : "8x8"} font (ink ${label.h} rows)`, tall ? label.h >= 12 && label.h <= 16 : label.h >= 6 && label.h <= 8);
    const t = inkBox(px, g.box.x + 4, g.titleY, g.box.x + g.box.w - 8, g.titleY + g.ch, paper);
    const mid = g.box.x + (g.box.w >> 1), tmid = t.left + (t.w >> 1), want = spec.length * 8;
    check(`${tag}: the title is the path ${spec}: ${t.w} px of ink centred (${tmid} vs ${mid})`, t.w > want - 8 && t.w <= want && Math.abs(tmid - mid) <= 4);
    const lines = [2, 3, 4, 5].map((i) => { const r = g.row(i); return inkiest(px, r.x, r.x + r.w, r.y, r.y + g.ch, paper); });
    const steps = lines.slice(1).map((y, i) => y - lines[i]);
    check(`${tag}: the empty rows' template lines are one font height apart (${steps.join(",")})`, steps.every((s) => s === g.ch));
}
