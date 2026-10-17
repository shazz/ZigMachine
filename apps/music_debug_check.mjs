// MUSIC DEBUG (cart "music"): every key asks for its song BY NAME, through the same
// setShadeMode the browser loader and the board's glass both send a digit to
// (docs/sealed-loader.js, fpga/glass/firmware/glass_input.c), so the cart owns its
// songs on both. Boots the cart over the real machine + ROM, presses 1..6 and polls
// the song bridge the way the loader does.
//   names     key n asks for TUNES[n-1]; each committed one is a file in docs/music/
//             (the board's song table is built from those names: fpga/tools/song_pack.py)
//   local     key 6 asks for local.xm, which is gitignored and never committed
//   xm        key 5's XM loads in the real audio modules and plays (mode 1, not silent)
//   node apps/music_debug_check.mjs [--break name]
//     name: key 5 is expected to ask for another file, so the check must fail
import { readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112, AUDIO_PAGES = 48, SR = 44100, SECONDS = 4;
const BROKE = process.argv.includes("--break");
const WANT = ["lollapalooza.mod", "concerto.ymraw", "smp1.raw", "crystallized.sndh",
    BROKE ? "other.xm" : "zm_test.xm", "local.xm"];
const LOCAL = "local.xm";

async function bootCart(path) {
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
    const cartBytes = await readFile(path);
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

function request({ memory, demo }, frames) {
    for (let f = 0; f < frames; f++) {
        demo.frame(16.6);
        if (demo.pollSongRequest())
            return new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    }
    return null;
}

/** The XM through the real audio modules: loaded, mode 1, peak and RMS over SECONDS. */
async function xmPlays(name) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    const bytes = await readFile(`docs/music/${name}`);
    new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
    if (!a.audioLoadXm(bytes.length)) return { ok: false, why: `refused, reason ${a.audioXmError()}` };
    a.audioXmPlay(0);
    let peak = 0, sum = 0;
    for (let i = 0; i < SR * SECONDS; i += 128) {
        a.audioRender(128);
        for (const v of new Float32Array(memory.buffer, m.audioLeftPtr(), 128)) { peak = Math.max(peak, Math.abs(v)); sum += v * v; }
    }
    const rms = Math.sqrt(sum / (SR * SECONDS));
    return { ok: a.audioMode() === 1 && rms > 0.01 && peak <= 1, why: `mode ${a.audioMode()}, peak ${peak.toFixed(3)}, rms ${rms.toFixed(3)}` };
}

const errors = [];
const cart = await bootCart("docs/demo-music.wasm");
for (const [i, want] of WANT.entries()) {
    cart.demo.setShadeMode(i);
    const got = request(cart, 5);
    console.log(`  key ${i + 1}: asks for ${got ?? "nothing"}`);
    if (got !== want) errors.push(`names: key ${i + 1} asked for ${got}, not ${want}`);
}
const tracked = execFileSync("git", ["ls-files", "docs/music"], { encoding: "utf8" }).split("\n");
for (const name of WANT.filter((n) => n !== LOCAL && !n.startsWith("other")))
    if (!tracked.includes(`docs/music/${name}`)) errors.push(`names: ${name} is not a committed file in docs/music/`);
if (tracked.includes(`docs/music/${LOCAL}`)) errors.push(`local: docs/music/${LOCAL} is committed: it must stay on its owner's machine`);
const xm = await xmPlays("zm_test.xm");
console.log(`  key 5's XM: ${xm.why}`);
if (!xm.ok) errors.push(`xm: zm_test.xm does not play (${xm.why})`);

// exitCode, never process.exit() (see apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (BROKE) {
    const hit = errors.find((e) => e.startsWith("names:"));
    console.log(hit ? `music_debug_check: PASS (--break name caught: ${hit})` : "music_debug_check: FAILED -- --break name not caught");
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `music_debug_check: FAILED -- ${errors.join("; ")}` : "music_debug_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
