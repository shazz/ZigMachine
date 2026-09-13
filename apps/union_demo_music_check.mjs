// Headless proof that the Union Demo menu asks for its YM dump and that the dump
// makes a sound. Boots demo-union_demo.wasm over the real machine + ROM, polls the
// song bridge the way docs/sealed-loader.js does (pollSongRequest -> songNamePtr/
// songNameLen), then hands the requested file to the real audio modules the way
// the worklet does for a .ymraw (audioLoadYm + audioYmPlay) and requires a peak.
//
//   node apps/union_demo_music_check.mjs
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112, AUDIO_PAGES = 48;
const WANT = "union_demo_menu.ymraw";
const MODE_YM = 2; // demo_audio_main.zig audioMode()

async function bootCart(cartPath) {
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
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, demo };
}

function firstRequest({ memory, demo }, frames) {
    const dec = new TextDecoder();
    for (let f = 0; f < frames; f++) {
        demo.frame(16.6);
        if (demo.pollSongRequest())
            return dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    }
    return null;
}

async function ymPeak(name) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    if (bytes.length > audio.audioSongCapacity()) return { loaded: false, peak: 0, why: "over song capacity" };
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadYm(bytes.length)) return { loaded: false, peak: 0, why: "audioLoadYm refused it" };
    audio.audioYmPlay();
    const left = new Float32Array(memory.buffer, machine.audioLeftPtr(), 1024);
    let peak = 0;
    for (let done = 0; done < 44100 * 2; done += 1024) {
        audio.audioRender(1024);
        for (const v of left) peak = Math.max(peak, Math.abs(v));
    }
    return { loaded: true, peak, mode: audio.audioMode() };
}

const cart = await bootCart("docs/demo-union_demo.wasm");
const name = firstRequest(cart, 10);
const again = cart.demo.pollSongRequest();
console.log(`union_demo request: ${name ? `"${name}"` : "none"} (polled twice: ${again ? "STILL pending" : "cleared"})`);
let ok = name === WANT && !again;
if (ok) {
    const r = await ymPeak(name);
    console.log(`  YM loaded ${r.loaded}${r.why ? ` (${r.why})` : ""}, mode ${r.mode} (${MODE_YM} == YM), peak ${r.peak.toFixed(4)}`);
    ok = r.loaded && r.mode === MODE_YM && r.peak > 0.01;
}
console.log(ok ? "=> PASS ✅ the menu's YM dump reaches the sealed YM" : `=> FAIL ❌ wanted "${WANT}" playing`);
process.exit(ok ? 0 : 1);
