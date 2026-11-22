// MUSIC DEBUG (cart "music"): every key asks for its song BY NAME, through the same
// setShadeMode the browser loader and the board's glass both send a digit to
// (docs/sealed-loader.js, fpga/glass/firmware/glass_input.c), so the cart owns its
// songs on both. Boots the cart over the real machine + ROM, presses 1..7 and polls
// the song bridge the way the loader does.
//   names     key n asks for TUNES[n-1]; each committed one is a file in docs/music/
//             (the board's song table is built from those names: fpga/tools/song_pack.py)
//   local     key 6 asks for local.xm, which is gitignored and never committed
//   xm        key 5's XM (keygen_9000.xm, a Public Domain module: docs/guide/MUSIC.md) loads in
//             the real audio modules and plays (mode 1, not silent)
//   vgm       key 7 asks for kestrel_fm.vgm (ours: libs/c/vgm/make_tune.py), which plays on our YM2612 +
//             SN76489 (mode 1, not silent); 7 again asks for local.vgm (gitignored, never committed)
//   node apps/music_debug_check.mjs [--break name|vgm]
//     name: key 5 is expected to ask for another file, so the check must fail
//     vgm: key 7 pressed again is expected to ask for another file
import { readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128, AUDIO_PAGES = 48, SR = 44100, SECONDS = 4;
const bi = process.argv.indexOf("--break");
const BROKE = bi > 0 ? process.argv[bi + 1] || "name" : null;
// [key (0-based), the song it asks for]: key 7 twice, the second time the local VGM
const WANT = [[0, "lollapalooza.mod"], [1, "concerto.ymraw"], [2, "smp1.raw"], [3, "crystallized.sndh"],
    [4, BROKE === "name" ? "other.xm" : "keygen_9000.xm"], [5, "local.xm"], [6, "kestrel_fm.vgm"],
    [6, BROKE === "vgm" ? "other.vgm" : "local.vgm"]];
const LOCALS = ["local.xm", "local.vgm"];

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

/** A song through the real audio modules (its loader, then its play): mode 1, peak and RMS over SECONDS. */
async function plays(name) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    const bytes = await readFile(`docs/music/${name}`);
    new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
    if (name.endsWith(".vgm")) {
        if (!a.audioLoadVgm(bytes.length)) return { ok: false, why: `refused, status ${a.audioVgmStatus()}` };
    } else {
        if (!a.audioLoadXm(bytes.length)) return { ok: false, why: `refused, reason ${a.audioXmError()}` };
        a.audioXmPlay(0);
    }
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
for (const [i, want] of WANT) {
    cart.demo.setShadeMode(i);
    const got = request(cart, 5);
    console.log(`  key ${i + 1}: asks for ${got ?? "nothing"}`);
    if (got !== want) errors.push(`${want.endsWith(".vgm") || want === "other.vgm" ? "vgm" : "names"}: key ${i + 1} asked for ${got}, not ${want}`);
}
const tracked = execFileSync("git", ["ls-files", "docs/music"], { encoding: "utf8" }).split("\n");
for (const [, name] of WANT.filter(([, n]) => !LOCALS.includes(n) && !n.startsWith("other")))
    if (!tracked.includes(`docs/music/${name}`)) errors.push(`names: ${name} is not a committed file in docs/music/`);
for (const l of LOCALS)
    if (tracked.includes(`docs/music/${l}`)) errors.push(`local: docs/music/${l} is committed: it must stay on its owner's machine`);
const xm = await plays("keygen_9000.xm");
console.log(`  key 5's XM: ${xm.why}`);
if (!xm.ok) errors.push(`xm: keygen_9000.xm does not play (${xm.why})`);
const vgm = await plays("kestrel_fm.vgm");
console.log(`  key 7's VGM: ${vgm.why}`);
if (!vgm.ok) errors.push(`vgm: kestrel_fm.vgm does not play (${vgm.why})`);

// exitCode, never process.exit() (see apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (BROKE) {
    const hit = errors.find((e) => e.startsWith(`${BROKE === "vgm" ? "vgm" : "names"}:`));
    console.log(hit ? `music_debug_check: PASS (--break ${BROKE} caught: ${hit})` : `music_debug_check: FAILED -- --break ${BROKE} not caught`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `music_debug_check: FAILED -- ${errors.join("; ")}` : "music_debug_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
