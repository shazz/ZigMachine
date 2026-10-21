// Which carts show the TUBE (what the mixer folds the first canvas over) on screen:
// picture pixels where every enabled plane's PFB snapshot is alpha 0 (pure tube) or
// below 255 (tube blended in). Boots each cart as apps/scene_hash.mjs does (no disk),
// runs FRAMES frames and inspects the last one.
//
//   node prototypes/gray_bg_re/tube_survey.mjs [frames=120] docs/demo-*.wasm
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../../docs/wasm_hiwater.js";

const PAGES = 112;

async function boot(cartPath) {
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
    const cartBytes = await readFile(cartPath);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw") && !(k in env)) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => 0;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

async function survey(cart, frames) {
    const { memory, machine, demo } = await boot(cart);
    const W = machine.hwPhysWidth(), H = machine.hwPhysHeight(), n = W * H;
    let alphas = null;
    for (let f = 1; f <= frames; f++) {
        machine.hwClear();
        demo.frame(16.6);
        const last = f === frames;
        if (last) alphas = new Uint8Array(n).fill(0); // max alpha over the drawn canvases
        let drawn = 0;
        for (let p = 0; p < machine.hwPlanesNumber(); p++) {
            if (!demo.isPlaneEnabled(p)) continue;
            machine.hwRenderPlane(p);
            drawn++;
            if (last) fold(alphas, new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), n * 4));
        }
        if (last && !drawn) fold(alphas, new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), n * 4));
    }
    let zero = 0, partial = 0;
    for (const a of alphas) a === 0 ? zero++ : a < 255 && partial++;
    return { zero, partial, n };
}

function fold(alphas, pfb) {
    for (let i = 0; i < alphas.length; i++) if (pfb[i * 4 + 3] > alphas[i]) alphas[i] = pfb[i * 4 + 3];
}

const args = process.argv.slice(2);
const frames = /^\d+$/.test(args[0] ?? "") ? Number(args.shift()) : 120;
for (const cart of args) {
    const tag = cart.replace(/^.*demo-/, "").replace(/\.wasm$/, "");
    try {
        const { zero, partial, n } = await survey(cart, frames);
        console.log(`${tag}\t${zero}\t${partial}\t${((100 * zero) / n).toFixed(1)}%`);
    } catch (e) {
        console.log(`${tag}\tERROR\t${String(e.message ?? e).slice(0, 60)}`);
    }
}
