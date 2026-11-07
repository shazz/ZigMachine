// CHISEL V2 (cart 112) at play: the parrot photo and the keys of the three texture modes
// (apps/zig/scenes/chisel_v2/play.zig). Boots the cart over the real machine + ROM per case,
// presses keys through key() (the host's path) and compares plane 0's indices below the label
// (rows 24..199). apps/chisel_v2_headless.mjs proves every pixel is its texel; this proves the
// keys reach the picture:
//   photo     P shows the photo (indices 56..247 only) at 64 / 128 / 256 (T), in all three modes,
//             unlike the generated texture and unlike each other
//   keys      each key changes the picture; its opposite brings back the default one (+ then -,
//             I then O, left then right, B four times...); X resets the keys' effect
//   still     a stopped camera (MODE 7 turn 0 speed 0, TUNNEL speed 0 roll 0) or F gives the
//             same frame twice; F prints PAUSED in the label
//   node apps/chisel_v2_play_check.mjs [--break photo]
//     --break photo: P is never sent, so every "photo" check must fail (then exit 0)
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128, REG_FB_BASE = 0x44, W = 320, TOP = 24, H = 200, N = 30;
const K = { up: 0xE020, down: 0xE021, left: 0xE022, right: 0xE023, p: 112, t: 116, f: 102, x: 120,
    plus: 43, minus: 45, r: 114, i: 105, o: 111, b: 98 };
const BROKE = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : "";
const fails = [];
const ok = (c, m) => { console.log(`  ${c ? "ok  " : "FAIL"} ${m}`); if (!c) fails.push(m); };

async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile("docs/demo-chisel_v2.wasm"), env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => 0;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const VB = machine.hwVideoBase();
    const plane = () => new Uint8Array(memory.buffer, VB + new DataView(memory.buffer).getUint32(VB + REG_FB_BASE, true), W * H).slice();
    return { demo, plane };
}

/** Mode `mode`, `keys` pressed before the first frame, `frames` frames: plane 0. */
async function shot(mode, keys, frames = N) {
    const c = await boot();
    c.demo.setShadeMode(mode);
    for (const k of keys) if (!(BROKE === "photo" && k === K.p)) c.demo.key(k);
    for (let f = 0; f < frames; f++) c.demo.frame(16.6);
    return { c, px: c.plane() };
}
const pic = (p) => p.subarray(TOP * W);
const eq = (a, b) => pic(a).every((v, i) => v === pic(b)[i]);

console.log("chisel_v2 play");
for (const [mode, name] of [[0, "ROTOZOOM"], [1, "MODE 7"], [2, "TUNNEL"]]) {
    const gen = (await shot(mode, [])).px;
    const sizes = [];
    for (const [t, side] of [[2, 64], [0, 128], [1, 256]]) { // T: 128 -> 256 -> 64
        const px = (await shot(mode, [K.p, ...Array(t).fill(K.t)])).px;
        sizes.push(px);
        const body = mode === 1 ? px.subarray(49 * W) : pic(px); // MODE 7: the floor, under the sky
        ok(body.every((v) => v >= 56 && v <= 247) && !eq(px, gen), `${name}: P shows the photo at ${side} (photo indices only, not the generated picture)`);
    }
    ok(!eq(sizes[0], sizes[2]) && !eq(sizes[1], sizes[2]), `${name}: the photo's size changes its pixels (64 / 128 / 256)`);
}
const pairs = [
    [0, "ROTOZOOM", "+", [K.plus], [K.plus, K.minus]], [0, "ROTOZOOM", "R", [K.r], [K.r, K.r]],
    [0, "ROTOZOOM", "I", [K.i], [K.i, K.o]], [0, "ROTOZOOM", "right", [K.right], [K.right, K.left]],
    [0, "ROTOZOOM", "down", [K.down], [K.down, K.up]], [0, "ROTOZOOM", "X after I I and +", [K.i, K.i], [K.i, K.i, K.x]],
    [1, "MODE 7", "left", [K.left], [K.left, K.right]], [1, "MODE 7", "+ (height)", [K.plus], [K.plus, K.minus]],
    [1, "MODE 7", "up (drive)", [K.up], null], [2, "TUNNEL", "up", [K.up], [K.up, K.down]],
    [2, "TUNNEL", "right", [K.right], [K.right, K.left]], [2, "TUNNEL", "R", [K.r], [K.r, K.r]],
    [2, "TUNNEL", "B", [K.b], [K.b, K.b, K.b, K.b]],
];
for (const [mode, name, what, keys, back] of pairs) {
    const base = (await shot(mode, [])).px;
    ok(!eq((await shot(mode, keys)).px, base), `${name}: ${what} changes the picture`);
    if (back) ok(eq((await shot(mode, back)).px, base), `${name}: ${what} undone gives the default picture again`);
}
for (const [mode, name, keys] of [[1, "MODE 7", [K.left, K.left, K.up, K.down]], [2, "TUNNEL", [K.down, K.down, K.down, K.left]]]) {
    const s = await shot(mode, keys);
    s.c.demo.frame(16.6);
    ok(eq(s.px, s.c.plane()), `${name}: a stopped camera (turn / roll 0, speed 0): the next frame is the same`);
}
{ // F after 30 frames: the picture stops and the label says so (its ink where the running one has texture)
    const s = await shot(0, []);
    s.c.demo.key(K.f);
    s.c.demo.frame(16.6);
    const a = s.c.plane();
    s.c.demo.frame(16.6);
    ok(eq(a, s.c.plane()), "ROTOZOOM: F pauses: the next frame is the same");
    const tail = (p) => { const o = []; for (let y = 8; y < 16; y++) for (let x = 146; x < 194; x++) o.push(p[y * W + x]); return o; };
    ok(tail(a).includes(1) && tail(a).every((v) => v <= 1) && !tail(s.px).every((v) => v <= 1), "F prints PAUSED in the label");
}
if (BROKE === "photo") {
    const photoFails = fails.filter((m) => m.includes("P shows the photo"));
    const caught = photoFails.length === 9;
    console.log(caught ? "chisel_v2 play: PASS (--break photo caught: 9 photo checks failed)" : `chisel_v2 play: FAILED -- --break photo not caught (${photoFails.length} of 9)`);
    process.exitCode = caught ? 0 : 1;
} else {
    console.log(fails.length ? `chisel_v2 play: FAILED (${fails.length})` : "chisel_v2 play: PASS");
    process.exitCode = fails.length ? 1 : 0;
}
