// Headless EQUINOX check: the whole 320x228 screen of CODEF wab screen 015,
// re-derived independently from its screen.js and compared plane by plane.
//
// Nothing errors when this screen goes wrong, and it has: the dragons never
// morphed, the logo never showed, the roads were drawn in swapped order, the
// scroller ran at 8 px instead of 6.5, and the bottom 28 rows were pulled up
// into 200. So every sampled frame must match, exactly, a reference built from
// the source's own tables:
//   plane 0  black fill, road2 on the odd bands, road1 on the even (270-289);
//            and the SWAPPED order must NOT match (the check can tell them apart)
//   plane 1  backtop at 0, backscroll at 188, the logo at (55,145) with the
//            alpha of showLogo() (190-214), on schedule
//   plane 2  seven dragons on the trajectory with morphSprite()'s frame
//   plane 3  scrolltext_horizontal at speed 13 on the 640 canvas
// plus, measured from pixels alone: the scroller moves 13 ST px every 2 frames
// (6.5 px/frame) and 130 px in 20, and the bottom border rows 200..227 are open.
//
//   node apps/equinox_headless.mjs [outdir] [cart.wasm]
import { readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const TOP = 40, LEFT = 80; // ST (0,0) in the physical frame (x doubled)
const SW = 320, SH = 228; // 640x456 canvas halved
const ASSETS = "apps/zig/assets/screens/equinox";

// frame -> the morph frame screen.js shows there (7 = egg, 0 = dragon)
const MORPH = [[300, 7], [640, 3], [700, 0], [1000, 2], [1530, 5], [2000, 7]];
// frame -> the logo's 8-bit alpha (fade in by 0.1 from 400, out by 0.2, then in by 0.2 from 800)
const LOGO = [[399, 0], [409, 26], [449, 128], [499, 255], [519, 153], [549, 0], [809, 51], [849, 255]];
const SCROLL = [600, 601, 602, 620];

async function boot(cart) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cart);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine))
        if (/^hw(Rom)?Ram|^hwVideoBase$|^hwBlit$/.test(k)) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

const load = (f) => readFile(`${ASSETS}/${f}`);
const A = {
    roadPal: await load("road_pal.dat"), backPal: await load("backtop_pal.dat"), logoPal: await load("logo_pal.dat"),
    bobPal: await load("bobs_pal.dat"), fontPal: await load("fonts_pal.dat"),
    road1: await load("road1.raw"), road2: await load("road2.raw"), backtop: await load("backtop.raw"),
    backscroll: await load("backscroll.raw"), logo: await load("logo.raw"), font: await load("fonts.raw"),
    text: (await load("scrolltext.txt")).toString("latin1"),
    dragons: await Promise.all([1, 2, 3, 4, 5, 6, 7, 8].map((i) => load(`bob${i}.raw`))),
};

// ---- the reference, from screen.js ----------------------------------------
const OFFSETS = [[0,2,4,6,14,20,28,38,58],[0,2,4,8,14,22,28,40,52],[0,2,6,8,14,22,30,42,46],[0,4,4,8,16,24,30,44,40],[0,4,4,10,16,24,32,46,34],[0,4,6,10,16,26,32,48,28],[0,4,6,12,16,26,34,52,20],[0,6,4,12,20,26,34,54,14],[0,6,6,12,20,26,36,56,8],[2,4,6,14,20,28,38,58,0],[2,4,8,14,22,28,40,52,0],[2,6,8,14,22,30,42,46,0],[4,4,8,16,24,30,44,40,0],[4,4,10,16,24,32,46,34,0],[4,6,10,16,26,32,48,28,0],[4,6,12,16,26,34,52,20,0],[6,4,12,20,26,34,54,14,0],[6,6,12,20,26,36,56,8,0]];
const SUMS = [[0,0,2,6,12,26,46,74,112,170],[0,0,2,6,14,28,50,78,118,170],[0,0,2,8,16,30,52,82,124,170],[0,0,4,8,16,32,56,86,130,170],[0,0,4,8,18,34,58,90,136,170],[0,0,4,10,20,36,62,94,142,170],[0,0,4,10,22,38,64,98,150,170],[0,0,6,10,22,42,68,102,156,170],[0,0,6,12,24,44,70,106,162,170],[0,2,6,12,26,46,74,112,170,0],[0,2,6,14,28,50,78,118,170,0],[0,2,8,16,30,52,82,124,170,0],[0,4,8,16,32,56,86,130,170,0],[0,4,8,18,34,58,90,136,170,0],[0,4,10,20,36,62,94,142,170,0],[0,4,10,22,38,64,98,150,170,0],[0,6,10,22,42,68,102,156,170,0],[0,6,12,24,44,70,106,162,170,0]];

// an expected plane: per ST pixel [r,g,b,a], a = 0 meaning "transparent, colour ignored"
const blank = () => new Int16Array(SW * SH * 4);
function put(img, x, y, pal, idx, alpha = 255) {
    if (x < 0 || x >= SW || y < 0 || y >= SH) return;
    const o = (y * SW + x) * 4;
    img.set([pal[idx * 4], pal[idx * 4 + 1], pal[idx * 4 + 2], alpha], o);
}
function sprite(img, src, w, x0, y0, pal, key, alpha = 255, base = 0) {
    for (let i = 0; i < src.length; i++) {
        if (src[i] === key) continue;
        const o = (Math.floor(i / w) + y0) * SW + (i % w) + x0;
        put(img, (i % w) + x0, Math.floor(i / w) + y0, pal, src[i] + base, alpha);
    }
}

function roads(frame, swapped) {
    const img = blank(), counter = frame % 18;
    for (let y = 0; y < SH; y++) for (let x = 0; x < SW; x++) put(img, x, y, A.roadPal, 5);
    const band = (road, b) => {
        const h = OFFSETS[counter][b] / 2, top = SUMS[counter][b] / 2;
        for (let r = 0; r < h; r++) for (let x = 0; x < SW; x++) put(img, x, 113 + top + r, A.roadPal, road[(top + r) * SW + x]);
    };
    const [odd, even] = swapped ? [A.road1, A.road2] : [A.road2, A.road1];
    for (let b = 1; b < 9; b += 2) band(odd, b);
    for (let b = 0; b < 9; b += 2) band(even, b);
    return img;
}

function logoAlpha(frames) {
    let show = false, alpha = 0.00000001, inc = 0.1, t = 0;
    for (let f = 1; f <= frames; f++) {
        if (f % 400 === 0) show = true;
        if (!show) continue;
        if (++t !== 10) continue;
        alpha += inc;
        if (alpha >= 1.0) { inc = -0.2; alpha = 1.0; }
        else if (alpha < 0.1) { inc = 0.2; alpha = 0.0000001; show = false; }
        t = 0;
    }
    return Math.round(Math.min(1, Math.max(0, alpha)) * 255);
}

function backdrop(frame) {
    const img = blank();
    sprite(img, A.backtop, SW, 0, 0, A.backPal, 5);
    sprite(img, A.backscroll, SW, 0, 188, A.backPal, 5);
    const a = logoAlpha(frame);
    if (a) sprite(img, A.logo, 203, 55, 145, A.logoPal, 1, a);
    return img;
}

function trajectory() {
    const xs = [], ys = [];
    let fx = 0, fy = 0;
    for (let i = 0; i < 1500; i++) {
        if (i < 125 || i >= 950) { fx += 0.05; fy += 0.05; }
        else if (i < 220) { fx += 0.03; fy += 0.035; }
        else if (i < 480) { fx += 0.06; fy += 0.03; }
        else if (i < 630) { fx += 0.045; fy += 0.035; }
        else { fx += 0.02; fy += 0.045; }
        xs[i] = Math.floor((320 - 64 / 2 + ((256 - 64 / 2 - 5.0) * Math.cos(fx))) / 2);
        ys[i] = Math.floor((200 - 52 / 2 + 30 + ((128 - 52 / 2 - 10.0) * Math.sin(fy))) / 2);
    }
    return { xs, ys };
}
const PATH = trajectory();

function morphFrameAt(frames) {
    let state = "in_egg", type = 7, inc = 1, ticks = 0;
    for (let f = 1; f <= frames; f++) {
        if (f % 10) continue;
        ticks++;
        if (state === "in_egg") { type = 7; if (ticks === 60) { state = "morphing"; ticks = 0; } }
        else if (state === "morphing") { if (type > 0) type--; if (ticks === 20) { state = "alive"; ticks = 0; } }
        else if (state === "alive") {
            if (type === 0) inc = 1; else if (type === 3) inc = -1;
            type += inc;
            if (ticks === 70) { state = "demorphing"; ticks = 0; }
        } else { if (type < 7) type++; if (ticks === 20) { state = "in_egg"; ticks = 0; } }
    }
    return type;
}

function dragons(frame) {
    const img = blank(), tabpos = frame - 1;
    for (let n = 0; n < 7; n++) {
        const i = tabpos + n * 18;
        sprite(img, A.dragons[morphFrameAt(frame)], 32, PATH.xs[i % 940], PATH.ys[i % 964], A.bobPal, 0);
    }
    return img;
}

function scroller(frame) {
    const letters = [];
    let off = 0;
    for (let i = 0; i <= 11; i++) letters.push({ x: 11 * 64 + i * 64, c: A.text.charCodeAt(off++) });
    for (let f = 0; f < frame; f++) for (const l of letters) {
        l.x -= 13;
        if (l.x > -64) continue;
        l.x = 11 * 64 + (l.x + 64);
        l.c = A.text.charCodeAt(off++);
        if (off > A.text.length - 1) off = 0;
    }
    const img = blank();
    // fonts.raw is a strip of 32x26 glyphs, glyph k = character 32 + k (the sheet
    // layout drawTile reads from fonts.png is checked by tools/private_tools/equinox_assets.py)
    for (const l of letters) {
        const g = (l.c - 32) * 32 * 26;
        for (let y = 0; y < 26; y++) for (let x = 0; x < 32; x++) {
            const p = A.font[g + y * 32 + x];
            if (p) put(img, Math.floor(l.x / 2) + x, 201 + y, A.fontPal, p);
        }
    }
    return img;
}

// ---- the machine ----------------------------------------------------------
const outdir = process.argv[2];
const { memory, machine, demo } = await boot(process.argv[3] || "docs/demo-equinox.wasm");
const W = machine.hwPhysWidth(), size = W * machine.hwPhysHeight() * 4;
const errors = [];

function planeAt(layer) { // the 320x228 screen of one plane, RGBA
    const out = new Uint8Array(SW * SH * 4);
    for (let y = 0; y < SH; y++) for (let x = 0; x < SW; x++) {
        const o = ((y + TOP) * W + LEFT + 2 * x) * 4;
        out.set(layer.subarray(o, o + 4), (y * SW + x) * 4);
    }
    return out;
}
function differ(got, exp) {
    let n = 0;
    for (let i = 0; i < SW * SH * 4; i += 4) {
        if (exp[i + 3] === 0) { if (got[i + 3] !== 0) n++; continue; }
        if (got[i] !== exp[i] || got[i + 1] !== exp[i + 1] || got[i + 2] !== exp[i + 2] || got[i + 3] !== exp[i + 3]) n++;
    }
    return n;
}

const frames = [...new Set([...MORPH.map((m) => m[0]), ...LOGO.map((l) => l[0]), ...SCROLL])].sort((a, b) => a - b);
const shots = {};
let f = 0;
for (const frame of frames) {
    while (f < frame) { machine.hwClear(); demo.frame(1000 / 60); f++; }
    const planes = [];
    for (let p = 0; p < 4; p++) {
        machine.hwRenderPlane(p);
        planes.push(planeAt(new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), size)));
    }
    shots[frame] = planes;
    const refs = [roads(frame, false), backdrop(frame), dragons(frame), scroller(frame)];
    const names = ["roads", "backdrop+logo", "dragons", "scrolltext"];
    refs.forEach((r, p) => {
        const n = differ(planes[p], r);
        if (n) errors.push(`frame ${frame} plane ${p} (${names[p]}): ${n} px differ from screen.js`);
    });
    if (frame === MORPH[1][0] && differ(planes[0], roads(frame, true)) === 0)
        errors.push(`frame ${frame}: the roads also match the SWAPPED band order (check is blind)`);
    if (outdir) await shot(`${outdir}/equinox-${frame}.ppm`, planes);
}

// the schedules the tables claim, against the reference
for (const [frame, want] of MORPH) if (morphFrameAt(frame) !== want) errors.push(`frame ${frame}: reference morph frame ${morphFrameAt(frame)}, table says ${want}`);
for (const [frame, want] of LOGO) {
    if (logoAlpha(frame) !== want) errors.push(`frame ${frame}: reference logo alpha ${logoAlpha(frame)}, table says ${want}`);
    // measured: the highest alpha over the logo's own (non-field) pixels on plane 1
    let got = 0;
    for (let i = 0; i < A.logo.length; i++) if (A.logo[i] !== 1) {
        const o = ((145 + Math.floor(i / 203)) * SW + 55 + (i % 203)) * 4;
        const px = shots[frame][1];
        if (px[o] === A.logoPal[A.logo[i] * 4] && px[o + 1] === A.logoPal[A.logo[i] * 4 + 1]) got = Math.max(got, px[o + 3]);
    }
    if (got !== want) errors.push(`frame ${frame}: logo alpha on screen ${got}, want ${want}`);
}
// the scroll speed, from pixels alone: the ink moves left by 13 px every 2 frames
function inkShift(a, b) { // the unique s with b[x] == a[x + s] on the scroller rows
    const hits = [];
    for (let s = 0; s < 160; s++) {
        let ok = true;
        for (let y = 201; y < 227 && ok; y++) for (let x = 0; x + s < SW && ok; x++)
            if ((a[(y * SW + x + s) * 4 + 3] !== 0) !== (b[(y * SW + x) * 4 + 3] !== 0)) ok = false;
        if (ok) hits.push(s);
    }
    return hits.length === 1 ? hits[0] : `${hits.length} candidates`;
}
const s01 = inkShift(shots[600][3], shots[601][3]), s12 = inkShift(shots[601][3], shots[602][3]);
const s02 = inkShift(shots[600][3], shots[602][3]), s20 = inkShift(shots[600][3], shots[620][3]);
if (s02 !== 13 || s20 !== 130 || s01 + s12 !== 13 || ![6, 7].includes(s01))
    errors.push(`scroll shifts ${s01}+${s12} per frame, ${s02} in 2 frames, ${s20} in 20 (want 6/7, 13, 130)`);
// the bottom border is open: rows 200..227 carry the backscroll and the letters
let border = 0;
for (let y = 200; y < SH; y++) for (let x = 0; x < SW; x++) if (shots[600][1][(y * SW + x) * 4 + 3]) border++;
if (border < 8000) errors.push(`bottom border rows 200..227 of plane 1 carry only ${border} px`);

// the 320x228 screen, planes alpha-blended bottom first
async function shot(file, planes) {
    const hdr = new TextEncoder().encode(`P6\n${SW} ${SH}\n255\n`);
    const buf = new Uint8Array(hdr.length + SW * SH * 3);
    buf.set(hdr);
    for (let i = 0; i < SW * SH; i++) for (const l of planes) {
        const a = l[i * 4 + 3] / 255, d = hdr.length + i * 3;
        for (let c = 0; c < 3; c++) buf[d + c] = Math.round(l[i * 4 + c] * a + buf[d + c] * (1 - a));
    }
    await writeFile(file, buf);
}

if (errors.length) {
    console.error(`equinox: WRONG\n  ${errors.slice(0, 20).join("\n  ")}`);
    process.exit(1);
}
console.log(`equinox: 4 planes match screen.js at ${frames.length} frames; dragons morph, logo fades on schedule, scroll ${s01}+${s12} px/frame (130 px in 20), bottom border open`);
