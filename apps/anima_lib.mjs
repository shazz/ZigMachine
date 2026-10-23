// apps/anima_headless.mjs's machine: boots the sealed machine + docs/demo-anima.wasm the way
// docs/sealed-loader.js does (hwClear, frame, hwRenderPlane per enabled plane, every frame: the
// HBL runs inside hwRenderPlane, so the raster and the borders are live), counts CHISEL ops,
// records every song request, and reads the composed 800x280 picture.
import { readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

export const CART = "docs/demo-anima.wasm";
const PAGES = 112;

export async function boot() {
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
    const m = { memory, machine, blits: 0, maxBlits: 0, frame: 0, songs: [] };
    const cartBytes = await readFile(CART);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    env.hwBlit = () => { m.blits++; machine.hwBlit(); };
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => 0;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    m.demo = demo;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    m.W = machine.hwPhysWidth();
    m.H = machine.hwPhysHeight();
    pollSong(m);
    return m;
}

function pollSong(m) {
    if (m.demo.pollSongRequest() !== 1) return;
    const name = new TextDecoder().decode(new Uint8Array(m.memory.buffer, m.demo.songNamePtr(), m.demo.songNameLen()));
    m.songs.push({ frame: m.frame, tick: m.demo.animaTick(), name });
}

/// One host frame, exactly as the browser runs it.
export function step(m) {
    m.frame++;
    m.machine.hwClear();
    m.blits = 0;
    m.demo.frame(16.6);
    if (m.frame > 1) m.maxBlits = Math.max(m.maxBlits, m.blits);
    pollSong(m);
    m.machine.hwRenderPlane(0);
}

export const picture = (m) => new Uint32Array(m.memory.buffer, m.machine.hwPhysicalPtr(), m.W * m.H);
export const plane = (m) => new Uint8Array(m.memory.buffer, m.demo.animaFb(), 400 * 280);
export const background = (m) => new Uint32Array(m.memory.buffer, m.machine.hwVideoBase() + 4, 1)[0];

/// SHA-256 of the composed picture (flip one bit first when `spoil`), and a PPM of it.
export async function shot(m, path, spoil) {
    const px = new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), m.W * m.H * 4);
    const h = createHash("sha256");
    if (spoil) { const c = px.slice(); c[1000] ^= 1; h.update(c); } else h.update(px);
    const rgb = Buffer.alloc(m.W * m.H * 3);
    for (let i = 0; i < m.W * m.H; i++) for (let c = 0; c < 3; c++) rgb[i * 3 + c] = px[i * 4 + c];
    await writeFile(path, Buffer.concat([Buffer.from(`P6\n${m.W} ${m.H}\n255\n`), rgb]));
    return h.digest("hex");
}

/// Visible lines whose two border columns do not show `want(r)` where the plane holds index 0.
export function borderMisses(m, want) {
    const px = picture(m), fb = plane(m);
    let miss = 0, seen = 0;
    for (let r = 40; r < 240; r++) for (const [x, lx] of [[0, 0], [m.W - 1, 399]]) {
        if (fb[r * 400 + lx] !== 0) continue;
        seen++;
        if (px[r * m.W + x] !== want(r)) miss++;
    }
    return { miss, seen };
}
