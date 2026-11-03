// KT TEST (cart "kt_test", apps/zig/scenes/kt_test.zig): the klystrack (.kt) test screen for the
// .kt player (libs/zig/players/kt.zig; apps/kt_check.mjs checks the player itself). Boots the cart over the real machine + ROM, presses 1..5 through
// setShadeMode (what the loader and the board's glass send a digit to) and polls the song bridge.
//   names     keys 1..4 ask for starport2.kt, castlevania.kt, oceanloader3.kt, dpintro.kt; key 5 asks
//             for "none" (zg.SONG_STOP)
//   songs     the bundled files are upstream klystrack's examples (apps/ports/klystrack/data) byte for
//             byte (md5), tracked in docs/music/
//   plays     the audio modules load and play each song (mode 1), not silent
//   node apps/kt_test_check.mjs [--break name]
//     name: key 2 is expected to ask for another file, so the check must fail
import { readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128, AUDIO_PAGES = 48;
const BROKE = process.argv.includes("--break");
const WANT = ["starport2.kt", BROKE ? "other.kt" : "castlevania.kt", "oceanloader3.kt", "dpintro.kt", "none"];
/** The bundled songs: upstream's example files (apps/ports/klystrack/data/<NAME>.KT), md5 of each. */
const BUNDLED = {
    "starport2.kt": "0246c50252e717ea7677fefb5c044ea4",
    "castlevania.kt": "9657f6b0554d8df5548bb35c3f91cef5",
    "oceanloader3.kt": "22139dc5dbaf6df1ec72b35b2db25775",
    "dpintro.kt": "eaee7e7520571ce27a857b7edcd58e68",
};

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

/** The audio modules given a .kt, as the loader feeds it (loadKt): it loads, plays in mode 1, and is heard. */
async function audioPlaysKt(bytes) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
    if (!a.audioLoadKt(bytes.length)) return false;
    a.audioKtPlay(0);
    let sum = 0;
    for (let i = 0; i < 100; i++) {
        a.audioRender(441);
        for (const v of new Float32Array(memory.buffer, m.audioLeftPtr(), 441)) sum += v * v;
    }
    return a.audioMode() === 1 && Math.sqrt(sum / 44100) > 0.01;
}

const errors = [];
const cart = await bootCart("docs/demo-kt_test.wasm");
for (const [i, want] of WANT.entries()) {
    cart.demo.setShadeMode(i);
    const got = request(cart, 3);
    console.log(`  key ${i + 1}: asks for ${got ?? "nothing"}`);
    if (got !== want) errors.push(`names: key ${i + 1} asked for ${got}, not ${want}`);
}
const tracked = execFileSync("git", ["ls-files", "docs/music"], { encoding: "utf8" }).split("\n");
for (const [name, md5] of Object.entries(BUNDLED)) {
    if (!tracked.includes(`docs/music/${name}`)) { errors.push(`songs: ${name} is not a committed file in docs/music/`); continue; }
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    const got = createHash("md5").update(bytes).digest("hex");
    if (got !== md5) errors.push(`songs: ${name} md5 ${got}, not upstream's ${md5}`);
    if (!(await audioPlaysKt(bytes))) errors.push(`plays: the audio modules did not play ${name}`);
}
// The frames run on after a request, no trap.
cart.demo.setShadeMode(0);
for (let f = 0; f < 5; f++) cart.demo.frame(16.6);
console.log("  after key 1, 5 frames: no trap; every bundled song plays in the audio modules");

// exitCode, never process.exit() (see apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (BROKE) {
    const hit = errors.find((e) => e.startsWith("names:"));
    console.log(hit ? `kt_test_check: PASS (--break name caught: ${hit})` : "kt_test_check: FAILED -- --break name not caught");
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `kt_test_check: FAILED -- ${errors.join("; ")}` : "kt_test_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
