// NFO VIEWER (cart "nfo_viewer", apps/zig/scenes/nfo_viewer.zig, zigdemo/nfo.zig): the NFO / ASCII-art
// viewer on the desk plane. Boots the cart over the real machine + ROM and drives it like desk_check.mjs.
//   picture  the 640x480 desk picture is the model's, every pixel (the model below is a second
//            implementation of the glyph cell: font pictures read from nfo_font.zig, blocks,
//            dither, shadow, grid, bar), at the start, mid-scroll and at the end
//   glyph    an 'A' of the sample sits at its cell with exactly the font's pixels in white, and a
//            full block has its grid lines (right column, bottom row): no model involved
//   scroll   after the start delay the pan moves 1 px every 2 frames: FB_BASE grows by one 640-byte
//            row a step, and a step rewrites only the rows the bar leaves and covers (the text is
//            painted once, never again)
//   bar      the bottom 18 rows of the window are the same bytes at every scroll position, the text
//            above them is not
//   keys     PgDn pages to the end, PgUp to the top and the automatic scroll stops, an arrow moves 18
//            rows, Space leaves, a key that is not configured does nothing
//   older    a machine without the desk mode (hwDeskAvailable() = 0) keeps the cart out of it
//   node apps/nfo_viewer_check.mjs           node apps/nfo_viewer_check.mjs --break
//   --break  each mutant (a wrong glyph pixel, no shadow, a dither seam, a bar that scrolls, a wrong
//            step rate, an older machine said yes, a pan by the wrong row) must be caught
// ON THE BOARD only a person can check what no model sees: FRESCO scans plane 0 live in the desk and
// latches FB_BASE at the VBL, so a pan by 640 bytes (one row) must show the next row with no tear,
// and the bar's 18 rewritten rows may tear for one frame (single buffer). Look at the scroll and the bar.
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128, W = 640, H = 480, CART = "docs/demo-nfo_viewer.wasm", HALF = W * (H / 2) * 4;
const REG_RES = 0x00, REG_FB_BASE = 0x44, OFF_VRAM = 0x1100, VRAM_BYTES = 1 << 20, RES_DESK = 3;
// nfo_viewer.zig's config: the checks below fail if the cart's differs.
const DELAY = 90, FPP = 2, BAR_H = 18, PROMPT = "up/down or PgUp/PgDn to scroll, SPACE to leave";
const PAL = { 0: [0x40, 0x5f, 0x89], 1: [255, 255, 255], 2: [0x1f, 0x3b, 0x67], 3: [0xe2, 0xe6, 0xeb], 4: [0xe5, 0xda, 0xf0], 5: [0x1f, 0x3b, 0x67], 6: [0x12, 0x25, 0x45], 7: [0xa3, 0xe1, 0xff] };
const MUTANTS = ["glyph", "shadow", "dither", "bar", "step", "older", "pan"];

// --- the model: the sample NFO as CP437 bytes, the font, the cell ---
const CP437 = { "▀": 0xdf, "▄": 0xdc, "█": 0xdb, "▌": 0xdd, "▐": 0xde, "░": 0xb0, "▒": 0xb1, "▓": 0xb2 };
const fontSrc = await readFile("libs/zig/zigdemo/nfo_font.zig", "utf8");
const PICS = [...fontSrc.matchAll(/^\s*"([#./]{63})",/gm)].map((m) => m[1]);
if (PICS.length !== 95) throw new Error(`nfo_font.zig: ${PICS.length} glyph pictures, not 95`);
const sample = (await readFile("apps/zig/scenes/nfo_viewer/sample.nfo.txt", "utf8")).split("\n");
if (sample[sample.length - 1] === "") sample.pop();
const LINES = sample.map((l) => [...l].slice(0, 80).map((c) => (c.charCodeAt(0) < 128 ? c.charCodeAt(0) : CP437[c])));
const ymax = (LINES.length * 9) - (H - BAR_H);

function pix(ch, x, ly, par, brk) {
    if (ch >= 0x20 && ch < 0x7f) {
        if (ly > 7) return 0;
        const on = PICS[ch - 32][ly * 8 + x] === "#";
        return (brk === "glyph" && ch === 65 && ly === 0 && x === 2 ? !on : on) ? 1 : 0;
    }
    const solid = () => (ly === 8 ? 3 : x === 7 ? 4 : 1);
    switch (ch) {
        case 0xdb: return solid();
        case 0xdf: return ly <= 4 ? solid() : 0;
        case 0xdc: return ly >= 4 ? solid() : 0;
        case 0xdd: return x <= 3 ? solid() : 0;
        case 0xde: return x >= 4 ? solid() : 0;
        case 0xb0: case 0xb1: case 0xb2: {
            const p = (brk === "dither" ? ly & 1 : par) * 2 + (x & 1), lvl = ch - 0xaf;
            return (lvl === 1 ? p === 0 : lvl === 2 ? p === 0 || p === 3 : p !== 3) ? 1 : 0;
        }
        default: return ch <= 0x20 || ch === 0x7f ? 0 : 0;
    }
}
const at = (l, c) => (c >= 0 && c < l.length ? l[c] : 0x20);
function textRow(y, brk) {
    const row = new Uint8Array(W), cur = LINES[Math.floor(y / 9)] ?? [], ly = y % 9;
    const up = y > 0 ? LINES[Math.floor((y - 1) / 9)] ?? [] : [], uly = (y - 1) % 9;
    for (let c = 0; c < 80; c++) for (let x = 0; x < 8; x++) {
        let v = pix(at(cur, c), x, ly, y & 1, brk);
        if (!v && y > 0 && brk !== "shadow") {
            const sc = x > 0 ? at(up, c) : c > 0 ? at(up, c - 1) : 0x20;
            if (pix(sc, (x + 7) & 7, uly, (y - 1) & 1, brk)) v = 2;
        }
        row[c * 8 + x] = v;
    }
    return row;
}
function barRow(k) {
    const row = new Uint8Array(W).fill(k === 0 ? 7 : 5), x0 = (W - PROMPT.length * 8) / 2;
    for (const [d, colour] of [[1, 6], [0, 1]]) for (let i = 0; i < PROMPT.length; i++) for (let ly = 0; ly < 8; ly++) {
        if (k !== 5 + ly + d) continue;
        for (let x = 0; x < 8; x++) if (pix(PROMPT.charCodeAt(i), x, ly, 0)) row[x0 + i * 8 + x + d] = colour;
    }
    return row;
}
/** The window at pan y as palette indices, 480 rows of 640. */
function model(y, brk) {
    const out = new Uint8Array(W * H);
    for (let r = 0; r < H; r++) {
        const k = r - (H - BAR_H);
        out.set(k >= 0 ? barRow(brk === "bar" ? (k + y) % BAR_H : k) : textRow(y + r, brk), r * W);
    }
    return out;
}

// --- the machine ---
async function boot(brk, available = 1) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    machine.hwSetDeskAvailable(brk === "older" ? 1 : available);
    const cartBytes = await readFile(CART);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo, video: machine.hwVideoBase(), brk, frames: 0 };
}
const dv = (m) => new DataView(m.memory.buffer, m.video);
function frame(m) {
    m.machine.hwClear();
    m.demo.frame(1000 / 60);
    m.frames++;
}
const fbBase = (m) => dv(m).getUint32(REG_FB_BASE, true);
const vram = (m, from, n) => new Uint8Array(m.memory.buffer, m.video + from, n).slice();
function picture(m) {
    const out = new Uint8Array(2 * HALF);
    for (let half = 0; half < 2; half++) {
        m.machine.hwRenderDesk(half);
        out.set(new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), HALF), half * HALF);
    }
    return out;
}
/** Wrong pixels of the machine's picture against the model's indices (alpha must be 255). */
function diff(px, idx) {
    let bad = 0, first = "";
    for (let i = 0; i < W * H; i++) {
        const want = PAL[idx[i]], o = i * 4;
        if (px[o + 3] !== 255 || px[o] !== want[0] || px[o + 1] !== want[1] || px[o + 2] !== want[2]) {
            if (!bad++) first = ` first at (${i % W}, ${Math.floor(i / W)}): ${[...px.slice(o, o + 4)]} want ${want}`;
        }
    }
    return { bad, first };
}
/** The pan the machine shows: FB_BASE in rows from the buffer's start. */
const panOf = (m, base0, brk) => (fbBase(m) - base0) / (brk === "pan" ? 641 : 640);
const expectY = (updates, brk) => Math.max(0, Math.floor((updates - DELAY) / (brk === "step" ? 3 : FPP)));

async function run(brk) {
    const fails = [];
    const check = (ok, what) => ok || fails.push(what);
    const m = await boot(brk);
    frame(m); // the first frame attaches: no update yet
    check(m.machine.hwDeskActive() === 1 && dv(m).getUint8(REG_RES) === RES_DESK, "picture: the cart is not in desk mode");
    const base0 = fbBase(m);
    check(base0 % 64 === 0 && base0 >= OFF_VRAM && base0 + W * (ymax + H) <= OFF_VRAM + VRAM_BYTES, `pool: FB_BASE ${base0}, the tall buffer must lie in the VRAM pool`);
    const first = picture(m);
    const d0 = diff(first, model(0, brk));
    check(d0.bad === 0, `picture: the first window has ${d0.bad} wrong pixels${d0.first}`);
    checkGlyph(first, check);
    let prev = vram(m, base0, W * (ymax + H)), updates = 0, steps = 0;
    for (let f = 0; f < DELAY + 2 * 70 + 6; f++) {
        frame(m); updates++;
        const y = panOf(m, base0, brk);
        check(y === expectY(updates, brk), `scroll: after ${updates} updates the pan is ${y}, want ${expectY(updates, brk)}`);
        const now = vram(m, base0, W * (ymax + H));
        const changed = new Set();
        for (let i = 0; i < now.length; i++) if (now[i] !== prev[i]) changed.add(Math.floor(i / W));
        const allowed = (r) => r >= Math.max(0, y - 1) + H - BAR_H && r < y + H;
        check([...changed].every(allowed), `scroll: update ${updates} rewrote text rows outside the bar's rows (${[...changed].filter((r) => !allowed(r)).slice(0, 3)})`);
        if (y !== expectY(updates - 1, brk)) steps++;
        prev = now;
    }
    check(steps >= 60, `scroll: only ${steps} steps in 140 frames`);
    barAndEnd(m, brk, check, base0);
    await keysAndOlder(brk, check);
    return fails;
}

function checkGlyph(px, check) {
    const li = LINES.findIndex((l) => String.fromCharCode(...l).includes("ASCII")), col = String.fromCharCode(...LINES[li]).indexOf("A");
    const A = [0x30, 0x48, 0x84, 0x84, 0xfc, 0x84, 0x84, 0x00]; // 'A': "..##..." ".#..#.." "#....#." ...
    let bad = 0;
    for (let ly = 0; ly < 8; ly++) for (let x = 0; x < 8; x++) {
        const o = ((li * 9 + ly) * W + col * 8 + x) * 4, white = px[o] === 255 && px[o + 1] === 255 && px[o + 2] === 255;
        if (white !== !!(A[ly] & (0x80 >> x))) bad++;
    }
    check(bad === 0, `glyph: 'A' at line ${li} column ${col} differs from the font in ${bad} pixels`);
    const bi = LINES.findIndex((l) => l[1] === 0xdb), g = (x, y) => [...px.slice((y * W + x) * 4, (y * W + x) * 4 + 3)].join();
    const same = (a, rgb) => a === rgb.join();
    check(same(g(8 + 3, bi * 9 + 3), PAL[1]) && same(g(8 + 7, bi * 9 + 3), PAL[4]) && same(g(8 + 3, bi * 9 + 8), PAL[3]),
        "glyph: a full block lacks its body, its right grid line or its bottom grid line");
}

function barAndEnd(m, brk, check, base0) {
    const rowsAt = (a, b) => picture(m).slice(a * W * 4, b * W * 4);
    const barNow = rowsAt(H - BAR_H, H), textNow = rowsAt(0, 200), y1 = panOf(m, base0, brk);
    for (let i = 0; i < 40; i++) frame(m);
    check(panOf(m, base0, brk) > y1, "bar: the scroll stopped before the test could compare");
    const barLater = rowsAt(H - BAR_H, H);
    check(barNow.every((v, i) => v === barLater[i]), "bar: the prompt bar moved or changed while the text scrolled");
    check(!textNow.every((v, i) => v === rowsAt(0, 200)[i]), "bar: the text did not move");
    const dm = diff(picture(m), model(panOf(m, base0, brk), brk));
    check(dm.bad === 0, `picture: mid-scroll the window has ${dm.bad} wrong pixels${dm.first}`);
    m.demo.key(0xe01d); // PgDn: a page (462 rows) takes the pan to the end
    frame(m);
    check(panOf(m, base0, brk) === ymax, `keys: PgDn should pan to ${ymax}, the pan is ${panOf(m, base0, brk)}`);
    const de = diff(picture(m), model(ymax, brk));
    check(de.bad === 0, `picture: the last window has ${de.bad} wrong pixels${de.first}`);
}

async function keysAndOlder(brk, check) {
    const m = await boot(brk);
    frame(m);
    const base0 = fbBase(m), yOf = () => (fbBase(m) - base0) / 640;
    for (let i = 0; i < DELAY + 60; i++) frame(m);
    const y0 = yOf();
    check(y0 > 10, `keys: the scroll did not run (pan ${y0})`);
    m.demo.key("z".charCodeAt(0));
    m.demo.key("x".charCodeAt(0));
    frame(m);
    check(yOf() - y0 <= 1 && yOf() >= y0, `keys: an unconfigured key moved the pan from ${y0} to ${yOf()}`);
    m.demo.key(0xe01c); // PgUp: back to the top, and the reader's scroll stops the automatic one
    frame(m);
    check(yOf() === 0, `keys: PgUp should pan to the top, the pan is ${yOf()}`);
    for (let i = 0; i < 30; i++) frame(m);
    check(yOf() === 0, `keys: after PgUp the automatic scroll ran on (pan ${yOf()})`);
    m.demo.input(1); // the down arrow: two text rows
    frame(m);
    check(yOf() === 18, `keys: the down arrow should pan 18 rows, the pan is ${yOf()}`);
    check(m.demo.pollCartRequest() === 0, "keys: the cart asked to leave before Space");
    m.demo.key(0x20);
    check(m.demo.pollCartRequest() === -1, "keys: Space did not ask for the menu");
    const old = await boot(brk, 0);
    for (let i = 0; i < 3; i++) frame(old);
    check(!old.machine.hwDeskActive(), "older: the cart entered the desk on a machine without it");
}

if (process.argv.includes("--break")) {
    let missed = 0;
    for (const brk of MUTANTS) {
        const fails = await run(brk);
        console.log(`${fails.length ? "caught " : "MISSED "} ${brk}${fails.length ? ": " + fails[0] : ""}`);
        missed += !fails.length;
    }
    process.exit(missed ? 1 : 0);
}
const fails = await run(null);
for (const f of fails) console.log(`FAIL ${f}`);
console.log(fails.length ? "nfo_viewer_check: FAILED" : "nfo_viewer_check: the NFO window's pixels, the 1 px pan, the fixed bar, the keys and the older machine all hold");
process.exit(fails.length ? 1 : 0);
