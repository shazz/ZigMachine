// SKYSTRIKE ZIG-mode harness, the other screens (apps/skystrike_zig.mjs
// drives): the title, the difficulty menu, the briefing, the hall of fame and
// its name entry, in the open 400 x 280 frame on the overlay plane
// (zig_screens.zig), checked on the composited frame. In ORIGINAL the same
// moments show plane 0 alone (the ST's 320 x 200).
//   title / menu / briefing  the screen 1:1 at 40,40 (the title's scroller
//       zone as it was before the letters); the left, right and top borders
//       the neighbouring sectors and the sky above as line 1000 draws them:
//       not flat, running on from the screen's edges, not the old 5/4
//       scaling; the bottom border plain but for the title's
//       scroller: white, full width, clear of the monitor's frame, and the
//       original's own letters at the original's own phase (153 px right)
//   hall of fame / name entry  the picture scaled by 5/4, the text 1:1 over
//       it, the text being exactly what the game drew; Z is a letter
// --break intro: the intro screens expected scaled by 5/4 as before.
// --break hiscore: the hall's text expected scaled with its picture.
import { zsession, WIN_W } from "./skystrike_zig_session.mjs";
import { toPlay, L } from "./skystrike_session.mjs";
import { grab, lowres, png } from "./skystrike_zig_frame.mjs";
import * as K from "./skystrike_zig_screens_layout.mjs";

const pending = [];

/// The frame of the moment, the planes shown, a screenshot.
function look(s, name, outdir) {
    s.machine.hwClear();
    s.demo.frame(20); // a displayed frame; lockstep: no VBL runs
    const planes = [0, 1, 2, 3].map((p) => s.demo.isPlaneEnabled(p) ? 1 : 0).join("");
    const frame = lowres(grab(s));
    if (outdir) pending.push(png(`${outdir}/zig_${name.replace(/ /g, "_")}.png`, frame, 400, 280));
    return { planes, frame, pal: K.palette(s), physic: s.screen("physic") };
}

function check(s, name, zig, outdir, broke, errors, notes) {
    const v = look(s, name, zig ? outdir : null);
    if (!zig) {
        if (v.planes !== "1000") errors.push(`screens: ORIGINAL's ${name} shows planes ${v.planes}, not plane 0 alone`);
        return;
    }
    if (v.planes !== "0010") return errors.push(`screens: ZIG's ${name} shows planes ${v.planes}, not the overlay alone`);
    const hall = name === "hall of fame" || name === "name entry";
    const kind = s.val(319);
    if (kind !== (hall ? K.KIND.hall : K.KIND.scene)) return errors.push(`screens: ZIG's ${name} is drawn as screen kind ${kind}`);
    const e = errors.length;
    if (hall) checkHall(s, name, v, broke === "hiscore", errors);
    else checkScene(s, name, v, broke === "intro", errors);
    if (errors.length === e) notes.push(name);
}

/// The frame against a whole expected frame of indices.
function against(want, v, name, what, errors) {
    const m = K.misses(0, WIN_W, 0, 280, (x, y) => v.frame[y * WIN_W + x] >>> 0 === v.pal[want[y * WIN_W + x]]);
    if (m.bad) errors.push(`screens: ZIG's ${name} differs from ${what} in ${m.bad} of ${m.of} pixels (first ${m.first})`);
}

function checkScene(s, name, v, broke, errors) {
    if (broke) return against(K.scaled(v.physic), v, name, "the physic screen scaled by 5/4", errors);
    const title = name === "title", zone = K.zone(s);
    const at = (x, y) => v.frame[y * WIN_W + x] >>> 0;
    const inZone = (x, y) => title && x >= K.ZX && x < K.ZX + K.ZW && y >= K.ZY && y < K.ZY + K.ZH;
    const want = (x, y) => v.pal[inZone(x, y) ? zone[(y - K.ZY) * K.ZW + x - K.ZX] : v.physic[y * 320 + x]];
    const c = K.misses(0, 320, 0, 200, (x, y) => at(K.SX + x, K.SY + y) === want(x, y));
    if (c.bad) errors.push(`screens: ZIG's ${name} is not the screen 1:1 at ${K.SX},${K.SY} in ${c.bad} pixels (first ${c.first})`);
    if (title) {
        let gone = 0;
        for (let y = 0; y < K.ZH; y++) for (let x = 0; x < K.ZW; x++) if (zone[y * K.ZW + x] !== v.physic[(K.ZY + y) * 320 + K.ZX + x]) gone++;
        if (gone < 100) errors.push(`screens: the title's scroller is still at its place (${gone} pixels of it taken out)`);
    }
    borders(s, name, v, errors);
    band(name, v, K.ink(s), errors);
}

/// Left, top, right: the tiles, not flat, running on, not the screen scaled.
function borders(s, name, v, errors) {
    const t = K.tiles(s), old = K.scaled(v.physic), at = (x, y) => v.frame[y * WIN_W + x] >>> 0;
    const regions = [
        { n: "left", x0: 0, x1: K.SX, y0: 0, y1: K.BAND, edge: (i) => [K.SX - 1, K.SY + i, 0, i], len: 200 },
        { n: "top", x0: K.SX, x1: K.SX + 320, y0: 0, y1: K.SY, edge: (i) => [K.SX + i, K.SY - 1, i, 0], len: 320 },
        { n: "right", x0: K.SX + 320, x1: WIN_W, y0: 0, y1: K.BAND, edge: (i) => [K.SX + 320, K.SY + i, 319, i], len: 200 },
    ];
    for (const r of regions) {
        const why = faults(r, at, (x, y) => v.pal[t[y * WIN_W + x]], (x, y) => v.pal[old[y * WIN_W + x]], (x, y) => v.pal[v.physic[y * 320 + x]]);
        if (why.length) errors.push(`screens: ZIG's ${name}, ${r.n} border: ${why.join("; ")}`);
    }
}

/// What is wrong with one border: `tile`, `old`, `screen` give the colour
/// ZIG's draw, the old scaling and the 320 x 200 screen have at a point.
function faults(r, at, tile, old, screen) {
    const shown = K.misses(r.x0, r.x1, r.y0, r.y1, (x, y) => at(x, y) === tile(x, y));
    const scaledOld = K.misses(r.x0, r.x1, r.y0, r.y1, (x, y) => at(x, y) !== old(x, y));
    const colours = new Set();
    for (let y = r.y0; y < r.y1; y++) for (let x = r.x0; x < r.x1; x++) colours.add(at(x, y));
    let on = 0;
    for (let i = 0; i < r.len; i++) {
        const [fx, fy, px, py] = r.edge(i);
        if (at(fx, fy) === screen(px, py)) on++;
    }
    const why = [];
    if (shown.bad > shown.of * 0.05) why.push(`${shown.bad} of ${shown.of} pixels are not the neighbours line 1000 drew`);
    if (colours.size < 2) why.push(`${colours.size} colour(s): flat`);
    if (on < r.len * 0.6) why.push(`only ${on} of ${r.len} edge pixels run on from the screen`);
    if (scaledOld.bad < scaledOld.of * 0.1) why.push("the screen scaled by 5/4");
    return why;
}

/// The bottom border: its own colour, the scroller's ink on the title only,
/// in its 8 lines and in the music credits' 8 above them (zig_credits.zig,
/// checked by apps/skystrike_zig_music.mjs), never in the last HUD_MARGIN lines.
function band(name, v, ink, errors) {
    const bg = v.frame[K.BAND * WIN_W] >>> 0;
    let stray = 0, left = 0, right = 0, n = 0;
    for (let y = K.BAND; y < 280; y++) for (let x = 0; x < WIN_W; x++) {
        const c = v.frame[y * WIN_W + x] >>> 0, row = y >= K.SCROLL_Y && y < K.SCROLL_Y + 8;
        const credits = name === "title" && y >= K.CREDITS_Y && y < K.CREDITS_Y + 8;
        if (c === ink && row) { n++; if (x < K.SX) left++; if (x >= K.SX + 320) right++; }
        else if (c !== bg && !(c === ink && credits)) stray++;
    }
    if (stray) errors.push(`screens: ZIG's ${name}, bottom border: ${stray} pixels neither its colour nor the scroller's`);
    if (name !== "title") {
        if (n) errors.push(`screens: ZIG's ${name} shows the scroller (${n} pixels)`);
        return;
    }
    if (!left || !right || n < 400) errors.push(`screens: the title's scroller is not white across the bottom border (${n} ink pixels, ${left} left, ${right} right)`);
    if (K.SCROLL_Y + 8 > 280 - K.HUD_MARGIN) errors.push("screens: the scroller is under the monitor's frame");
    // The same letters as the original's zone, at the same phase: its pen 0.
    let off = 0;
    for (let y = 0; y < 8; y++) for (let x = K.ZX; x < 240; x++) {
        const pen = v.physic[(K.ZY + y) * 320 + x] === 0;
        if (pen !== (v.frame[(K.SCROLL_Y + y) * WIN_W + x + K.SHIFT] >>> 0 === ink)) off++;
    }
    if (off) errors.push(`screens: the title's scroller differs from the original's letters in ${off} of ${8 * (240 - K.ZX)} pixels`);
}

function checkHall(s, name, v, broke, errors) {
    const pic = K.hallPic(s), text = K.hallText(s);
    against(K.hallFrame(pic, text, v.physic, broke), v, name, "its picture scaled by 5/4 under its text 1:1", errors);
    const t = K.textIsTheGames(pic, text, v.physic);
    if (t.n < 1000 || t.missing || t.extra) errors.push(`screens: ZIG's ${name} text is not what the game drew (${t.n} text pixels, ${t.missing} not on the screen, ${t.extra} drawn but not kept)`);
}

async function intro(zig, outdir, broke, errors, notes) {
    const s = await zsession(zig);
    await toPlay(s, (what) => (what === "play" ? null : check(s, what, zig, outdir, broke, errors, notes)));
}

/// The title's timeout to the hall of fame; then a game over with a score
/// for the table, to the name entry, where Z is typed.
async function hallOfFame(zig, outdir, broke, errors, notes) {
    const h = await zsession(zig);
    h.run(2200);
    if (h.label() < L.l2260 || h.label() > L.l2311) errors.push(`screens: the title's timeout is not in the hall of fame (label ${h.label()})`);
    else check(h, "hall of fame", zig, outdir, broke, errors, notes);
    const n = await zsession(zig);
    await toPlay(n);
    n.set("scre", 3000000);
    n.set("planes", 1);
    n.set("cl", 1);
    for (let i = 0; i < 400 && n.label() !== L.l227b && n.label() !== L.l190b; i++) n.run(1);
    n.press(32);
    for (let i = 0; i < 2000 && n.label() !== L.l2310 && n.label() !== L.l2311; i++) n.run(1);
    if (n.label() !== L.l2310 && n.label() !== L.l2311) return errors.push(`screens: a game over with 3,000,000 points did not reach the name entry (label ${n.label()})`);
    n.run(10);
    n.press(0x41); // 'A': a letter typed, the cursor moved on
    n.run(3);
    check(n, "name entry", zig, outdir, broke, errors, notes);
    n.press(0x5a);
    if (n.z("zig") !== (zig ? 1 : 0)) errors.push("screens: Z in the name entry switched the mode");
}

export async function screens(outdir, broke) {
    const errors = [], notes = [];
    for (const zig of [true, false]) {
        await intro(zig, zig ? outdir : null, broke, errors, notes);
        await hallOfFame(zig, zig ? outdir : null, broke, errors, notes);
    }
    await Promise.all(pending);
    console.log(`  screens: ZIG shows ${notes.join(", ")}: the intro 1:1 with the world round it and the title's scroller white in the bottom border, the hall's picture scaled under its text 1:1; ORIGINAL shows plane 0 alone; Z is a letter in the name entry`);
    return errors;
}
