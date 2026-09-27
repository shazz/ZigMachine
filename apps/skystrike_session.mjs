// SKYSTRIKE harness, part 1 (apps/skystrike_headless.mjs is the driver): the
// sealed machine booted the way docs/sealed-loader.js boots it, and a lockstep
// session on the cart's test door (apps/zig/scenes/skystrike/testapi.zig).
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig

export async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const env0 = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
    const rom = (await WebAssembly.instantiate(romBytes, { env: env0 })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile("docs/demo-skystrike.wasm");
    const env = { ...env0, ...rom };
    for (const n of Object.keys(machine)) if (n.startsWith("hwRam") || n.startsWith("hwRomRam")) env[n] = machine[n];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

// The flow labels and the variable ids, read from the cart's own sources.
const flowSrc = await readFile("apps/zig/scenes/skystrike/flow.zig", "utf8");
export const L = Object.fromEntries(flowSrc.match(/enum\(u8\) \{([\s\S]*?)count,/)[1].replace(/\/\/.*/g, "").match(/\b(boot|l\w+)\b/g).map((n, i) => [n, i]));
const apiSrc = await readFile("apps/zig/scenes/skystrike/testapi.zig", "utf8");
export const V = Object.fromEntries(apiSrc.match(/const VARS = [^{]*\{([\s\S]*?)\};/)[1].match(/"\w+"/g).map((n, i) => [n.slice(1, -1), 20 + i]));
export const PASSES = 10, SP = 11, CLEAR_LOG = 12, ENEMY = 200; // testapi.zig
const OP = { music: 0, samplay: 1, samstop: 2, samloop: 3, volume: 4, noise: 5, envel: 6 };

/// A lockstep session: the cart powered on with RND seeded.
export async function session(seed = 1234) {
    const ctx = await boot();
    const d = ctx.demo;
    d.skyTestReset(seed);
    const s = {
        ...ctx,
        vbl: (n) => d.skyTestVbl(n),
        val: (id) => d.skyTestVal(id),
        v: (name) => d.skyTestVal(V[name]),
        set: (name, x) => d.skyTestPoke(V[name], x),
        poke: (id, x) => d.skyTestPoke(id, x),
        stick: (bits) => d.skyTestStick(bits),
        press(cp) { d.skyTestKey(cp, 1); d.skyTestVbl(3); d.skyTestKey(cp, 0); },
        label: () => d.skyTestVal(0),
        runTo(name, max) {
            for (let i = 0; i < max; i++) { if (d.skyTestVal(0) === L[name]) return true; d.skyTestVbl(1); }
            return false;
        },
        log() {
            const out = [];
            for (let i = 0; i < 64 && d.skyTestVal(100 + i) >= 0; i++) out.push(d.skyTestVal(100 + i));
            return out;
        },
        clearLog: () => d.skyTestPoke(CLEAR_LOG, 0),
        screen(which) { return new Uint8Array(ctx.memory.buffer, d.skyTestPtr(which === "physic" ? 0 : 1), 64000); },
    };
    return s;
}
export const has = (log, op, arg) => log.includes(OP[op] << 8 | arg);

/// Title -> SPACE -> the menu (Easy: FIRE) -> the briefing -> SPACE: play.
export async function toPlay(s, shots, broke) {
    s.vbl(500);
    shots?.("title");
    s.vbl(100);
    s.press(32);
    s.vbl(297);
    if (broke === "screen") { s.stick(2); s.vbl(8); s.stick(0); } // Medium, not Easy
    shots?.("menu");
    s.stick(128); s.vbl(5); s.stick(0);
    s.vbl(400);
    shots?.("briefing");
    s.press(32);
    s.vbl(297);
    shots?.("play");
}

