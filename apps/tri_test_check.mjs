// TRI TEST (cart 125) headless: boots the sealed machine + demo-tri_test.wasm and proves every
// TRIANGLE the cart draws against a rasteriser written here from HW_API.md / BLITTER_HW_SPEC.md
// (deterministic odd-even scanline fill: each edge with ay < by covers rows [ay, by) at
// x = ax + floor((bx-ax) * (y-ay) / (by-ay)), the span from the least x to the greatest, cut to
// the clip), not from machine/blitter_ops.zig. Then the hashes the cart shows (FNV-1a of the
// drawing area, set A once, set B folded over 300 frames) must be the goldens pinned in
// apps/zig/scenes/tri_test.zig: what the board's OK / BAD verdict compares against.
//
//   node apps/tri_test_check.mjs [--break floor]
//     --break floor  this rasteriser truncates toward zero instead of flooring: must be caught
import { readFile } from "node:fs/promises";
import { cartRam } from "../docs/wasm_hiwater.js";

const PAGES = 128, OFF_BLIT = 0x80, REG_FB_BASE = 0x44, W = 320, H = 200, LABEL = 16;
const CMD_FILL = 2, CMD_TRI = 4, CON_CLIP_EN = 0x80, MT_XOR_BC = 0x66;
const broke = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : "";
const src = await readFile("apps/zig/scenes/tri_test.zig", "utf8");
const golden = (name) => Number.parseInt(src.match(new RegExp(`${name}: u32 = 0x([0-9A-Fa-f]+)`))[1], 16) >>> 0;
const failures = [];
function check(name, ok, detail = "") {
    if (!ok) failures.push(name);
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`);
}

const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const ref = new Uint8Array(W * H); // the drawing area as this rasteriser sees it
let tris = 0, drawn = 0;
const hwBlit = () => {
    const VB = machine.hwVideoBase();
    apply(new DataView(memory.buffer.slice(VB + OFF_BLIT, VB + OFF_BLIT + 0x80)));
    machine.hwBlit();
};
const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit } })).instance.exports;
const cartBytes = await readFile("docs/demo-tri_test.wasm"), env = { memory, ...rom };
for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
env.hwBlit = hwBlit;
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
machine.hwInit();
demo.boot();
demo.skipBoot();
const VB = machine.hwVideoBase();
const plane = () => new Uint8Array(memory.buffer, VB + new DataView(memory.buffer).getUint32(VB + REG_FB_BASE, true), W * H);

// floor(n / d), d > 0, exactly (no double rounding near an integer); --break floor truncates
function div(n, d) {
    if (broke === "floor") return Math.trunc(n / d);
    let q = Math.floor(n / d);
    while (q * d > n) q--;
    while ((q + 1) * d <= n) q++;
    return q;
}
function clipRect(b) {
    const u16 = (o) => b.getUint16(o - OFF_BLIT, true);
    let c = [0, 0, W, H];
    if (b.getUint8(2) & CON_CLIP_EN) {
        const cx = u16(0xb8), cy = u16(0xba);
        c = [Math.max(cx, 0), Math.max(cy, 0), Math.min(cx + u16(0xbc), W), Math.min(cy + u16(0xbe), H)];
    }
    return c;
}
function put(x, y, color, mt) {
    ref[y * W + x] = mt === MT_XOR_BC ? ref[y * W + x] ^ color : color;
}
function apply(b) {
    const cmd = b.getUint8(0), mt = b.getUint8(1), color = b.getUint8(4);
    const i16 = (o) => b.getInt16(o - OFF_BLIT, true);
    if (cmd === CMD_FILL) {
        const x0 = i16(0xac), y0 = i16(0xae), w = b.getUint16(0xa8 - OFF_BLIT, true), h = b.getUint16(0xaa - OFF_BLIT, true);
        for (let y = Math.max(y0, 0); y < Math.min(y0 + h, H); y++)
            for (let x = Math.max(x0, 0); x < Math.min(x0 + w, W); x++) ref[y * W + x] = color;
        return;
    }
    if (cmd !== CMD_TRI) return;
    tris++;
    const v = [0xac, 0xae, 0xb0, 0xb2, 0xb4, 0xb6].map(i16);
    const [cx0, cy0, cx1, cy1] = clipRect(b);
    const ys = [v[1], v[3], v[5]];
    for (let y = Math.max(Math.min(...ys), cy0); y <= Math.min(Math.max(...ys), cy1 - 1); y++) {
        let xl = Infinity, xr = -Infinity;
        for (let e = 0; e < 3; e++) {
            let [ax, ay, bx, by] = [v[2 * e], v[2 * e + 1], v[(2 * e + 2) % 6], v[(2 * e + 3) % 6]];
            if (ay === by) continue;
            if (ay > by) [ax, ay, bx, by] = [bx, by, ax, ay];
            if (y < ay || y >= by) continue;
            const x = ax + div((bx - ax) * (y - ay), by - ay);
            xl = Math.min(xl, x);
            xr = Math.max(xr, x);
        }
        for (let x = Math.max(xl, cx0); x <= Math.min(xr, cx1 - 1); x++, drawn++) put(x, y, color, mt);
    }
}
// the cart's hash: FNV-1a over the area's little-endian words
function hashArea(p) {
    const w = new Uint32Array(p.buffer, p.byteOffset + LABEL * W, ((H - LABEL) * W) / 4);
    let h = 0x811c9dc5;
    for (const x of w) h = Math.imul(h ^ x, 0x01000193) >>> 0;
    return h;
}
const areaBad = (p) => p.subarray(LABEL * W).reduce((n, v, i) => n + (v !== ref[LABEL * W + i]), 0);

console.log("tri_test");
demo.setShadeMode(0);
demo.frame(16.6);
let p = plane();
const a = hashArea(p);
check(`set A: ${tris} triangles, ${drawn} pixels, every one the rasteriser's`, areaBad(p) === 0, `${areaBad(p)} px differ`);
check("set A: the edge cases draw (>= 180 triangles, >= 20,000 pixels)", tris >= 180 && drawn >= 20000);
check(`set A: hash ${a.toString(16)} is GOLDEN_A`, a === golden("GOLDEN_A"), golden("GOLDEN_A").toString(16));

demo.setShadeMode(1);
let fold = 0, bad = 0;
tris = drawn = 0;
for (let f = 0; f < 300; f++) {
    demo.frame(16.6);
    p = plane();
    bad += areaBad(p);
    fold = Math.imul(fold ^ hashArea(p), 0x01000193) >>> 0;
}
check(`set B: 300 frames, ${tris} triangles, ${drawn} pixels, every one the rasteriser's`, bad === 0, `${bad} px differ`);
check(`set B: folded hash ${fold.toString(16)} is GOLDEN_B`, fold === golden("GOLDEN_B"), golden("GOLDEN_B").toString(16));
demo.frame(16.6);
check("set B: frozen on its last frame", hashArea(plane()) === hashArea(p));

if (broke) {
    const caught = failures.some((f) => f.includes("rasteriser's"));
    console.log(caught ? "tri_test: PASS (--break floor caught)" : "tri_test: FAILED -- --break floor not caught");
    process.exit(caught ? 0 : 1);
}
console.log(failures.length ? `tri_test: FAILED (${failures.length})` : "tri_test: PASS");
process.exit(failures.length ? 1 : 0);
