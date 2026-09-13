// Headless proof that a FOREIGN-LANGUAGE cart can have music with zero host change.
//
// The song bridge is four exports the loader polls every frame
// (docs/sealed-loader.js: pollSongRequest -> songNamePtr/songNameLen/songTune ->
// playSongByName). A C cart gets them from apps/c/zigmachine_music.h, a Rust cart
// from apps/rust/zigmachine_music.rs. This drives each cart exactly that way over
// the real machine + ROM, then hands the requested tune to the real audio modules
// the way the worklet does (audioLoadSndh + audioSndhPlay(tune)) and requires the
// sealed YM to make a sound.
//
//   node apps/c_music_check.mjs   # C screen34 + Rust v8_populous (play), rust hello (silent)
import { readFile } from "node:fs/promises";
import { cartRam, CART_RAM_BASE, CART_RAM_TOP } from "../docs/wasm_hiwater.js";

const PAGES = 112, VIDEO_BASE = 0x300000, AUDIO_PAGES = 48;
const dec = new TextDecoder();

async function bootCart(path) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const live = { demo: null };
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (...a) => live.demo && live.demo.hblDispatch(...a) },
    })).instance.exports;
    const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwInit();
    rom.romReset();
    const cart = new Uint8Array(await readFile(path));
    // A C/Rust cart is NOT rebuilt by ./build.sh: a stale docs/demo-c*.wasm has no bridge.
    const probe = new WebAssembly.Module(cart);
    const names = WebAssembly.Module.exports(probe).map((e) => e.name);
    if (!names.includes("pollSongRequest")) {
        const script = path.includes("demo-rust") ? "apps/rust/build.sh" : "apps/c/build.sh";
        console.log(`FAIL  ${path} has no pollSongRequest export: rebuild it with bash ${script}`);
        process.exit(1);
    }
    const ram = cartRam(cart);
    const env = {
        memory, hwVideoBase: () => VIDEO_BASE, consoleLogJS: () => {},
        hwRamBase: () => CART_RAM_BASE, hwRamTop: () => CART_RAM_TOP,
        hwRamSize: () => CART_RAM_TOP - CART_RAM_BASE, hwRamUsed: () => ram.used, hwRamFree: () => ram.free,
    };
    const x = (await WebAssembly.instantiate(cart, { env: { ...rom, ...env } })).instance.exports;
    live.demo = x;
    return { memory, x };
}

// The loader's poll site, frame by frame: returns the FIRST request seen.
function pollFrames({ memory, x }, frames) {
    let req = null;
    for (let f = 0; f < frames; f++) {
        x.frame(16.6);
        if (!req && x.pollSongRequest()) {
            req = {
                name: dec.decode(new Uint8Array(memory.buffer, x.songNamePtr(), x.songNameLen())),
                tune: x.songTune(),
            };
        }
    }
    return req;
}

async function playPeak(name, tune) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const demo = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    demo.audioInit();
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    new Uint8Array(memory.buffer, demo.audioSongPtr(), bytes.length).set(bytes);
    if (!demo.audioLoadSndh(bytes.length)) return { loaded: false, peak: 0 };
    demo.audioSndhPlay(tune);
    const left = new Float32Array(memory.buffer, machine.audioLeftPtr(), 1024);
    let peak = 0;
    for (let done = 0; done < 44100; done += 1024) {
        demo.audioRender(1024);
        for (const v of left) peak = Math.max(peak, Math.abs(v));
    }
    return { loaded: true, peak, mode: demo.audioMode() };
}

async function checkPlays(path, wantName, wantTune) {
    const cart = await bootCart(path);
    cart.x.boot();
    const req = pollFrames(cart, 10);
    const again = cart.x.pollSongRequest();
    console.log(`\n${path}`);
    console.log(`  request       : ${req ? `"${req.name}" tune ${req.tune}` : "none"}`);
    console.log(`  polled twice  : ${again ? "STILL pending (would replay every frame)" : "cleared"}`);
    const asked = !!req && req.name === wantName && req.tune === wantTune && !again;
    const played = asked ? await playPeak(req.name, req.tune) : { loaded: false, peak: 0 };
    if (asked) console.log(`  SNDH loaded   : ${played.loaded}, mode ${played.mode} (4 == SNDH), peak ${played.peak.toFixed(4)}`);
    const ok = asked && played.loaded && played.mode === 4 && played.peak > 0.01;
    console.log(`  => ${ok ? "PASS ✅ the cart's request reaches the sealed YM" : "FAIL ❌"}`);
    return ok;
}

async function checkSilent(path) {
    const cart = await bootCart(path);
    const has = ["pollSongRequest", "songNamePtr", "songNameLen", "songTune"].every((n) => typeof cart.x[n] === "function");
    cart.x.boot();
    const req = has ? pollFrames(cart, 10) : null;
    const ok = has && req === null;
    console.log(`\n${path}`);
    console.log(`  bridge exports: ${has}   request: ${req ? `"${req.name}"` : "none"}`);
    console.log(`  => ${ok ? "PASS ✅ exports the bridge, asks for nothing" : "FAIL ❌"}`);
    return ok;
}

let ok = await checkPlays("docs/demo-c-screen34.wasm", "sos.sndh", 0);
ok = (await checkPlays("docs/demo-rust-v8_populous.wasm", "custodian.sndh", 1)) && ok;
ok = (await checkSilent("docs/demo-rust.wasm")) && ok;
process.exit(ok ? 0 : 1);
