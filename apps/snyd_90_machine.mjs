// The sealed machine + demo-snyd_90.wasm, booted as docs/sealed-loader.js
// does (for apps/snyd_90_headless.mjs), and an SNDH played on the sealed YM.
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112, REG_FB_BASE = 0x44;
export const PW = 400, PH = 280;

/// `setMute(true)` keeps the plane's HBLs from running (the --break hbl case).
export async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo, mute = false;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => { if (!mute) demo.hblDispatch(id, p, l, x); } },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const noop = () => {};
    const cartBytes = await readFile("docs/demo-snyd_90.wasm");
    const env = { memory, jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop, consoleLogJS: noop, ...rom };
    for (const k of Object.keys(machine)) if (/^hw(Video|Blit|Ram|RomRam)/.test(k)) env[k] = machine[k];
    for (const k of ["audioPlay", "audioStop", "loadSample", "beep", "diskReadBlock", "hostAudioStreamStart", "hostAudioFeed", "hostAudioStreamStop"]) env[k] = noop;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const base = machine.hwVideoBase();
    return {
        memory, machine, demo, setMute: (v) => { mute = v; },
        plane: () => new Uint8Array(memory.buffer, base + new DataView(memory.buffer, base).getUint32(REG_FB_BASE, true), PW * PH),
    };
}

/// Play docs/music/<file> #sub for two seconds on the sealed YM: null if it
/// plays (its peak in `out.peak`), else why not.
export async function tuneFault(file, sub, out = {}) {
    const bytes = new Uint8Array(await readFile(`docs/music/${file}`));
    const mem = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const ma = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory: mem } })).instance.exports;
    const env = { memory: mem };
    for (const x of Object.keys(ma)) if (x.startsWith("machine")) env[x] = ma[x];
    const au = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    au.audioInit();
    new Uint8Array(mem.buffer, au.audioSongPtr(), bytes.length).set(bytes);
    if (!au.audioLoadSndh(bytes.length)) return `${file} is not an SNDH image`;
    au.audioSndhPlay(sub);
    const left = new Float32Array(mem.buffer, ma.audioLeftPtr(), 1024);
    let peak = 0;
    for (let d = 0; d < 2 * 44100; d += 1024) { au.audioRender(1024); for (const v of left) peak = Math.max(peak, Math.abs(v)); }
    out.peak = peak;
    if (au.audioMode() !== 4 || peak < 0.05 || au.audioSndhStuckPc()) return `${file} #${sub} does not play (mode ${au.audioMode()}, peak ${peak.toFixed(3)})`;
    return null;
}
