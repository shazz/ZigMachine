// Headless proof that the Union Demo menu asks for its SNDH and that the tune
// really plays. Boots demo-union_demo.wasm over the real machine + ROM, polls the
// song bridge the way docs/sealed-loader.js does (pollSongRequest -> songNamePtr/
// songNameLen/songTune), then hands the requested file to the real audio modules
// the way the worklet does for a .sndh (audioLoadSndh + audioSndhPlay(tune)).
//
// "Plays" means more than a peak: Alloy Run is a SID tune, and it once loaded,
// reported mode 4 and made no sound at all (the player had loaded it over the
// vector table it writes). So every second must be audible, and each of the
// three voices must have its volume register written.
//
//   node apps/union_demo_music_check.mjs              # the check
//   node apps/union_demo_music_check.mjs --fail-proof # must FAIL: a wrong tune name
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112, AUDIO_PAGES = 48;
const FAIL_PROOF = process.argv.includes("--fail-proof");
const WANT = FAIL_PROOF ? "union_demo_menu.ymraw" : "union/alloy_run.sndh";
const WANT_TUNE = 1;
const MODE_SNDH = 4; // demo_audio_main.zig audioMode()
const SECONDS = 10, SR = 44100, BLOCK = 882;

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
            return {
                name: dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())),
                tune: demo.songTune(),
            };
    }
    return null;
}

async function sndhPlay(name, tune) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const volWrites = [0, 0, 0];
    env.machineYmWrite = (r, v) => {
        if (r >= 8 && r <= 10) volWrites[r - 8]++;
        return machine.machineYmWrite(r, v);
    };
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    if (bytes.length > audio.audioSongCapacity()) return { loaded: false, why: "over song capacity" };
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) return { loaded: false, why: "audioLoadSndh refused it" };
    audio.audioSndhPlay(tune);
    volWrites.fill(0); // count the replay's writes, not the player's silence() at start
    let peak = 0, secPeak = 0, silent = 0;
    for (let done = 0; done < SECONDS * SR; done += BLOCK) {
        audio.audioRender(BLOCK);
        for (const v of new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK)) {
            const a = Math.abs(v);
            peak = Math.max(peak, a);
            secPeak = Math.max(secPeak, a);
        }
        if ((done / BLOCK + 1) % 50 === 0) { if (secPeak <= 0.01) silent++; secPeak = 0; }
    }
    return { loaded: true, peak, silent, volWrites, mode: audio.audioMode(), stuckPc: audio.audioSndhStuckPc() };
}

const cart = await bootCart("docs/demo-union_demo.wasm");
const req = firstRequest(cart, 400); // the song starts with the street, after the ~100-frame loader panel
const again = cart.demo.pollSongRequest();
console.log(`union_demo request: ${req ? `"${req.name}" tune ${req.tune}` : "none"} (polled twice: ${again ? "STILL pending" : "cleared"})`);
let ok = !!req && req.name === WANT && req.tune === WANT_TUNE && !again;
if (ok) {
    const r = await sndhPlay(req.name, req.tune);
    if (!r.loaded) console.log(`  SNDH not loaded (${r.why})`);
    else console.log(`  SNDH mode ${r.mode} (${MODE_SNDH} == SNDH), peak ${r.peak.toFixed(4)}, silent seconds ${r.silent}/${SECONDS}, ` +
        `volume writes A/B/C ${r.volWrites.join("/")}, stuck PC $${r.stuckPc.toString(16)}`);
    ok = r.loaded && r.mode === MODE_SNDH && r.peak > 0.01 && r.silent === 0 && r.volWrites.every((n) => n > 0);
}
if (FAIL_PROOF) {
    console.log(ok ? "=> FAIL ❌ the fail proof passed: the check cannot tell a wrong tune" : "=> PASS ✅ fail proof: a wrong tune name is refused");
    process.exit(ok ? 1 : 0);
}
console.log(ok ? "=> PASS ✅ the menu's SNDH plays on the sealed YM, all three voices" : `=> FAIL ❌ wanted "${WANT}" tune ${WANT_TUNE} playing`);
process.exit(ok ? 0 : 1);
