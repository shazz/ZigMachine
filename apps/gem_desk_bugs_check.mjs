// The five desktop bugs Matt found on the board on 9 Nov 2026 (GEM 5 step 1), held in every path
// they live in: the old ZigGEM path in LOW, MEDIUM and the desk (deskSetEngine 0), and the GEM 5
// engine in the desk (1 flat, 2 3D). The real machine + ROM + shell, driven as the page drives them.
//   reflow  "when expanding the files window, the icons don't reorganize": A:\ resized by its size
//           box shows exactly what a window OPENED at that size shows (the icons re-wrapped to the
//           width, the slider and scroll range with them)
//   page    "clicking on the scrollbar (not the arrows) did nothing": a click in the vertical track
//           under the slider = min(rows shown, rows left) clicks of the down arrow; in the
//           horizontal track right of it = min(columns shown, columns left) of the right arrow
//   hscroll "horizontal scrolling in text mode does weird things": one step right shows the
//           content 8 px to the left, every row (the folder row too), and the frame painted equals
//           a whole repaint (the engine's damage)
//   ghost   "dragging a file in text mode shows the icon ghost": the ghost is the row's dotted
//           outline, the row's width, where the pointer carried it
//   inf     "save desktop works but not read at start": with a C: (a FAT image, as the board's
//           card), Save Desktop in the desk with C:\ moved low writes C:\DESKTOP.INF; the shell
//           re-instantiated (a program returned) and a fresh boot over the same image both come
//           back in the desk with C:\ where it was saved
//   node apps/gem_desk_bugs_check.mjs        node apps/gem_desk_bugs_check.mjs --break
//   --break  each mutant must be caught: reflow (the grid frozen at open), page (no track paging),
//            rowscroll (folder rows stay put), hashpos (the engine's damage blind to a clipped row
//            that moved), rowghost (the icon ghost in text view), infdrop (a host that answers C:'s
//            writes and drops them)
import { readFileSync } from "node:fs";
import { bootGem } from "./gem_headless.mjs";
import { makeCFile } from "./scene_hash_disk.mjs";
import { W, H, res, fbBase, settle, pickRes, deskPicture, bufferAt } from "./gem_desk_lib.mjs";

const BRK = { reflow: 1 << 13, page: 1 << 14, hashpos: 1 << 15, rowscroll: 1 << 16, rowghost: 1 << 17 }; // rom/gem/desktop/deskbreak.zig
const MODES = { low: [0, 320, 200], medium: [0, 640, 200], desk0: [0, 640, 480], desk1: [1, 640, 480], desk2: [2, 640, 480] };
const DISK = Array.from({ length: 14 }, (_, i) => ({ name: `FILE${String(i).padStart(2, "0")}.DAT`, type: 1, size: 1000 * (i + 1), date: 20260912 }));
const FLOPPY = [35, 40], R = { x: 24, y: 24, w: 200, h: 120 }; // A:\ resized to R (low: x 2, clamped)
const TOP = 21, SCROLL = 12, TROW = 10; // gui/types.zig: title 11 + info 10; dirview.TROW_H

// The desktop's coordinates -> the host's (low res halves x in the ROM).
const host = (gem, x, y) => [res(gem) === 0 ? 2 * x : x, y];
const at = (gem) => ({
    click: (x, y) => gem.click(...host(gem, x, y)),
    open: (x, y) => gem.open(...host(gem, x, y)),
    point: (x, y, b) => gem.point(...host(gem, x, y), b),
    drag: (a, b) => gem.drag(...host(gem, ...a), ...host(gem, ...b), 8),
});

// The screen as the desktop's logical pixels: palette RGB in a plane mode, buffer indices in the desk.
function picture(gem, sw, sh) {
    if (sh === 480) { const b = bufferAt(gem, fbBase(gem)).slice(); return { sw, at: (x, y) => b[y * W + x], raw: b }; }
    gem.machine.hwRenderPlane(0);
    const p = new Uint8Array(gem.memory.buffer, gem.machine.hwPhysicalPtr(), gem.w * gem.h * 4), k = 640 / sw;
    const out = new Uint32Array(sw * sh);
    for (let y = 0; y < sh; y++) for (let x = 0; x < sw; x++) {
        const s = ((y + gem.by) * gem.w + k * x + gem.bx) * 4;
        out[y * sw + x] = p[s] | (p[s + 1] << 8) | (p[s + 2] << 16);
    }
    return { sw, at: (x, y) => out[y * sw + x], raw: out };
}
const same = (a, b) => a.raw.length === b.raw.length && a.raw.every((v, i) => v === b.raw[i]);
const isBlack = (pic, x, y) => pic.at(x, y) === 0;

// A booted GEM in `mode`, A:\ open and resized to R, then `mutant`'s bit set.
async function setup(mode, mutant, files = DISK) {
    const [look, sw, sh] = MODES[mode];
    const gem = await bootGem();
    gem.mount(files);
    const ui = at(gem);
    if (mode !== "low") pickRes(gem, ui.click, "medium", 320, 200);
    if (sh === 480) pickRes(gem, ui.click, "desk", 640, 200);
    gem.rom.deskSetEngine(look | (BRK[mutant] ?? 0));
    ui.open(...FLOPPY);
    settle(gem, 12);
    const r = { ...R, x: sw === 320 ? 2 : R.x }, from = sw === 320 ? 316 : 320; // low: the window opened clamped
    ui.drag([r.x + from - 6, r.y + r.h - 5], [r.x + r.w - 6, r.y + r.h - 5]); // its size box
    settle(gem, 6);
    return { gem, ui, r, sw, sh, park: () => { ui.point(sw - 10, sh - 10, 0); settle(gem, 4); return picture(gem, sw, sh); } };
}
const textView = (s) => { s.ui.click(117, 8); s.ui.click(145, 23); settle(s.gem, 4); }; // View > Show as Text
const newFolder = (s) => { s.ui.click(72, 8); s.ui.click(100, 39); s.gem.key(13); settle(s.gem, 4); };
const content = (r) => ({ x: r.x + 1, y: r.y + TOP, w: r.w - 2 - SCROLL, h: r.h - TOP - SCROLL });

// reflow: resized = closed and reopened at that size (TOS lays a window out at its width).
async function reflow(mode, mutant, check) {
    const s = await setup(mode, mutant);
    const resized = s.park();
    s.ui.click(s.r.x + 6, s.r.y + 5); // close box: A:\ remembers its rect
    settle(s.gem, 10);
    s.ui.open(...FLOPPY);
    settle(s.gem, 12);
    check(same(resized, s.park()), `${mode} reflow: A:\\ resized to ${s.r.w} differs from A:\\ opened at ${s.r.w} (icons not re-wrapped)`);
}

// How many arrow clicks a track click equals (0: it changed nothing, -1: no count up to 30 does).
function arrowsFor(s, track, arrow, back) {
    const before = s.park();
    s.ui.click(...track);
    const paged = s.park();
    if (same(paged, before)) return 0;
    for (let k = 0; k < 30; k++) s.ui.click(...back); // the opposite arrow, to the start again
    for (let k = 1; k <= 30; k++) { s.ui.click(...arrow); if (same(s.park(), paged)) return k; }
    return -1;
}
async function page(mode, mutant, check) {
    const s = await setup(mode, mutant);
    textView(s);
    const c = content(s.r), n = DISK.length, shown = Math.trunc(c.h / TROW);
    const v = arrowsFor(s, [s.r.x + s.r.w - 6, s.r.y + s.r.h - 24], [s.r.x + s.r.w - 6, s.r.y + s.r.h - 16], [s.r.x + s.r.w - 6, s.r.y + 25]);
    check(v === Math.min(shown, n - shown), `${mode} page: a click in the vertical track = ${v} down-arrow clicks, not ${Math.min(shown, n - shown)}`);
    const cols = Math.trunc(c.w / 8), hmax = Math.ceil((37 * 8 - c.w) / 8);
    const h = arrowsFor(s, [s.r.x + s.r.w - 26, s.r.y + s.r.h - 5], [s.r.x + s.r.w - 17, s.r.y + s.r.h - 5], [s.r.x + 6, s.r.y + s.r.h - 5]);
    check(h === Math.min(cols, hmax), `${mode} page: a click in the horizontal track = ${h} right-arrow clicks, not ${Math.min(cols, hmax)}`);
}

// hscroll: one step right = the content 8 px left (a folder row too), and = a whole repaint.
async function hscroll(mode, mutant, check) {
    const s = await setup(mode, mutant, DISK.slice(0, 4)); // the folder row in view, under 4 files
    newFolder(s);
    textView(s);
    // The SECOND step: from column 1 to 2 a row wider than the window spans both its edges before
    // and after, so its clipped extent does not change (what the engine's damage compared).
    const c = content(s.r), right = [s.r.x + s.r.w - 17, s.r.y + s.r.h - 5]; // the right arrow
    s.ui.click(...right);
    const p0 = s.park();
    s.ui.click(...right);
    const p1 = s.park();
    let bad = null;
    for (let y = c.y; y < c.y + c.h && !bad; y++)
        for (let x = c.x + 12; x < c.x + c.w - 16 && !bad; x++) if (p1.at(x, y) !== p0.at(x + 8, y)) bad = [x, y];
    check(!bad, `${mode} hscroll: a step right is not the content moved 8 px left (first at ${bad})`);
    s.gem.rom.deskSetEngine(MODES[mode][0] | (BRK[mutant] ?? 0)); // both buffers repainted whole
    check(same(s.park(), p1), `${mode} hscroll: the frame painted after the step differs from a whole repaint`);
}

// ghost: a text row dragged out: its dotted outline, its width, where the pointer took it.
async function ghost(mode, mutant, check) {
    const s = await setup(mode, mutant);
    textView(s);
    const c = content(s.r), g = [30, 5], to = [s.sw - c.w - 4 + g[0], s.sh - 40]; // grabbed 30, 5 into row 0; dropped on the desktop
    s.ui.point(c.x + g[0], c.y + g[1], 0);
    s.ui.point(c.x + g[0], c.y + g[1], 1);
    for (const k of [0.5, 1, 1]) s.ui.point(Math.round(c.x + g[0] + (to[0] - c.x - g[0]) * k), Math.round(c.y + g[1] + (to[1] - c.y - g[1]) * k), 1);
    const p = picture(s.gem, s.sw, s.sh), x0 = to[0] - g[0], y0 = to[1] - g[1];
    let top = 0, bot = 0;
    for (let x = x0; x < x0 + c.w; x++) { top += isBlack(p, x, y0); bot += isBlack(p, x, y0 + TROW - 1); }
    check(top >= 0.4 * c.w && bot >= 0.4 * c.w, `${mode} ghost: no dotted row outline ${c.w} wide at (${x0}, ${y0}) (top ${top}, bottom ${bot} black pixels)`);
    s.ui.point(...to, 0);
}

// inf: Save Desktop onto C:, then the shell re-instantiated and a fresh boot, both over the image.
async function inf(mutant, check) {
    const img = new Uint8Array(readFileSync("docs/kos-c.img"));
    const drop = mutant === "infdrop" ? { cFileOp: (m) => { const op = makeCFile(m, img.slice()); return (req) => op(req); } } : {};
    const gem = await bootGem({ cImage: img, ...drop });
    gem.mount(DISK);
    const ui = at(gem);
    pickRes(gem, ui.click, "desk", 320, 200);
    ui.open(20, 70); // C:\ (KOS F5's icon, under drive A)
    settle(gem, 12);
    ui.drag([200, 30], [300, 336]); // its title bar: C:\ to (124, 330)
    ui.click(180, 8); ui.click(210, 31); // Options > Save Desktop
    settle(gem, 6);
    const low = (g, what) => {
        settle(g, 12);
        check(g.machine.hwDeskActive() === 1, `inf: ${what} came up in RESOLUTION ${res(g)}, not the desk DESKTOP.INF asks for`);
        const pic = deskPicture(g);
        let n = 0;
        // DESKTOP.INF keeps character cells: (124, 330) comes back as cells (15, 41) = (120, 328)
        for (let x = 126; x < 436; x++) n += pic[(328 * W + x) * 4] === 0 && pic[(328 * W + x) * 4 + 1] === 0;
        check(n > 0.9 * 310, `inf: ${what}: C:\\ did not reopen where it was saved (no title bar frame on row 328)`);
    };
    gem.swap(gem.gemBytes); // a program returned: the shell is a new instance
    gem.demo.insertDisk(1);
    low(gem, "the shell after a program");
    low(await bootGem({ cImage: img }), "a fresh boot over the same card");
}

async function run(mutant) {
    const fails = [], check = (ok, what) => ok || fails.push(what);
    for (const mode of Object.keys(MODES)) {
        await reflow(mode, mutant, check);
        await page(mode, mutant, check);
        await hscroll(mode, mutant, check);
        await ghost(mode, mutant, check);
    }
    await inf(mutant, check);
    return fails;
}

if (process.argv.includes("--break")) {
    let missed = 0;
    for (const m of [...Object.keys(BRK), "infdrop"]) {
        const fails = await run(m);
        const where = [...new Set(fails.map((f) => f.split(" ").slice(0, 2).join(" ")))].join(", "); // the paths it shows in
        console.log(`${fails.length ? "caught " : "MISSED "} ${m}${fails.length ? ` (${where}): ` + fails[0] : ""}`);
        missed += !fails.length;
    }
    process.exit(missed ? 1 : 0);
}
const fails = await run(null);
for (const f of fails) console.log(`FAIL ${f}`);
console.log(fails.length ? "gem_desk_bugs_check: FAILED" : `gem_desk_bugs_check: in ${Object.keys(MODES).join(", ")}: a resized window re-flows, a track click pages, text view scrolls sideways whole, a text row drags as a row; Save Desktop's C:\\DESKTOP.INF is read back at start`);
process.exit(fails.length ? 1 : 0);
