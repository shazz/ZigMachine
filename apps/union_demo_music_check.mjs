// Headless proof that the Union screens ask for their SNDH tunes and that the
// tunes really play. Boots a cart over the real machine + ROM, polls the song
// bridge the way docs/sealed-loader.js does (pollSongRequest -> songNamePtr/
// songNameLen/songTune), then hands the requested file to the real audio modules
// the way the worklet does for a .sndh (audioLoadSndh + audioSndhPlay(tune)).
//   - union_demo: the menu's Alloy Run.
//   - union_main: track 1 autoplays; keys 2, 5 and 6 (setShadeMode(1)/(4)/(5))
//     ask for 150 mph, Lap 33 and Reality BY THEIR SNDH names; the .ymraw dumps
//     they replaced must never come back. 150 mph and Reality are SID tunes.
//
// "Plays" means more than a peak: Alloy Run is a SID tune, and it once loaded,
// reported mode 4 and made no sound at all (the player had loaded it over the
// vector table it writes). So every second must be audible, and each of the
// three voices must have its volume register written.
//
//   node apps/union_demo_music_check.mjs              # the check
//   node apps/union_demo_music_check.mjs --fail-proof # must FAIL: wrong tune names
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112, AUDIO_PAGES = 48;
const FAIL_PROOF = process.argv.includes("--fail-proof");
// Fail proof: each screen is asked for the file it used to play before its SNDH.
const MENU_WANT = FAIL_PROOF ? "union_demo_menu.ymraw" : "union/alloy_run.sndh";
const MENU_TUNE = 1;
// [setShadeMode, name, voices] — mode 0 is the autoplay request. `voices` is how
// many volume registers the replay must write in 10 s: Lap 33 only rewrites
// voice A's (B and C keep their init volume; it matched the dump 100%).
const MAIN_WANT = [
    [0, "union/sharpness_buzztone.sndh", 3],
    [1, FAIL_PROOF ? "union/150mph.ymraw" : "union/150_mph.sndh", 3],
    [4, FAIL_PROOF ? "union/Lap33.ymraw" : "union/lap_33.sndh", 1],
    [5, FAIL_PROOF ? "union/Reality.ymraw" : "union/reality.sndh", 3],
];
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

async function audioRig() {
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
    return { memory, machine, audio, volWrites };
}

async function sndhPlay(name, tune) {
    const { memory, machine, audio, volWrites } = await audioRig();
    let bytes;
    try {
        bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    } catch {
        return { loaded: false, why: `docs/music/${name} is not on the shelf` }; // a removed dump
    }
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

async function plays(req, voices = 3) {
    const r = await sndhPlay(req.name, req.tune);
    if (!r.loaded) { console.log(`  SNDH not loaded (${r.why})`); return false; }
    const written = r.volWrites.filter((n) => n > 0).length;
    console.log(`  SNDH mode ${r.mode} (${MODE_SNDH} == SNDH), peak ${r.peak.toFixed(4)}, silent seconds ${r.silent}/${SECONDS}, ` +
        `volume writes A/B/C ${r.volWrites.join("/")} (want ${voices} voices), stuck PC $${r.stuckPc.toString(16)}`);
    return r.mode === MODE_SNDH && r.peak > 0.01 && r.silent === 0 && written >= voices && r.stuckPc === 0;
}

async function checkMenu() {
    const cart = await bootCart("docs/demo-union_demo.wasm");
    const req = firstRequest(cart, 10);
    const again = cart.demo.pollSongRequest();
    console.log(`union_demo request: ${req ? `"${req.name}" tune ${req.tune}` : "none"} (polled twice: ${again ? "STILL pending" : "cleared"})`);
    return !!req && req.name === MENU_WANT && req.tune === MENU_TUNE && !again && (await plays(req));
}

async function checkMain() {
    const cart = await bootCart("docs/demo-union_main.wasm");
    let ok = true;
    for (const [mode, want, voices] of MAIN_WANT) {
        if (mode > 0) cart.demo.setShadeMode(mode);
        const req = firstRequest(cart, 10);
        console.log(`union_main track ${mode + 1} request: ${req ? `"${req.name}" tune ${req.tune}` : "none"} (want "${want}")`);
        ok = !!req && req.name === want && (await plays(req, voices)) && ok;
    }
    return ok;
}

const menu = await checkMenu();
const main = await checkMain();
if (FAIL_PROOF) {
    const refused = !menu && !main; // BOTH screens must reject their old file name
    console.log(refused ? "=> PASS ✅ fail proof: wrong tune names are refused on both screens"
        : `=> FAIL ❌ the fail proof passed on ${menu ? "union_demo" : ""} ${main ? "union_main" : ""}: the check cannot tell a wrong tune`);
    process.exit(refused ? 0 : 1);
}
const ok = menu && main;
console.log(ok ? "=> PASS ✅ the Union SNDH tunes play on the sealed YM, all three voices"
    : `=> FAIL ❌ union_demo ${menu ? "ok" : "BROKEN"}, union_main ${main ? "ok" : "BROKEN"}`);
process.exit(ok ? 0 : 1);
