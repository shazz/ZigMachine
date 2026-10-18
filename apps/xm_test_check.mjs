// XM TEST (cart "xm_test", apps/zig/scenes/xm_test.zig): the minimal XM screen for the
// board. Boots the cart over the real machine + ROM, presses 1..4 through setShadeMode
// (what the browser loader and the board's glass send a digit to) and polls the song
// bridge the way the loader does.
//   names     keys 1..3 ask for keygen_9000.xm, poppy_flower_girls.xm, local.xm; key 4 asks
//             for "none" (zg.SONG_STOP); the committed ones are git-tracked files in docs/music/
//             (the board's song table is built from those names: fpga/tools/song_pack.py)
//   songs     the two bundled modules are The Mod Archive's files byte for byte (the md5 its
//             page gives: their Public Domain licence is for THAT file, docs/MUSIC.md), have
//             the channel count the screen shows, and play in the real audio modules
//             (mode 1, not silent). The generated test songs (apps/xm_song.mjs) are covered
//             in memory by apps/xm_check.mjs and are not shipped.
//   local     local.xm is never committed
//   node apps/xm_test_check.mjs [--break name]
//     name: key 2 is expected to ask for another file, so the check must fail
import { readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112, AUDIO_PAGES = 48, SR = 44100, SECONDS = 2;
const BROKE = process.argv.includes("--break");
const WANT = ["keygen_9000.xm", BROKE ? "other.xm" : "poppy_flower_girls.xm", "local.xm", "none"];
/** The bundled modules: The Mod Archive's md5 (module.php?173938 and ?175325) and channel count. */
const BUNDLED = {
    "keygen_9000.xm": { md5: "02b1f1dad70ea15a0b064c45468caa55", channels: 8 },
    "poppy_flower_girls.xm": { md5: "251ef415c7e4a64b589f2fc3f86582df", channels: 12 },
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

/** An XM through the real audio modules: loaded, mode 1, peak and RMS over SECONDS. */
async function xmPlays(bytes) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
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
const cart = await bootCart("docs/demo-xm_test.wasm");
for (const [i, want] of WANT.entries()) {
    cart.demo.setShadeMode(i);
    const got = request(cart, 3);
    console.log(`  key ${i + 1}: asks for ${got ?? "nothing"}`);
    if (got !== want) errors.push(`names: key ${i + 1} asked for ${got}, not ${want}`);
}
const tracked = execFileSync("git", ["ls-files", "docs/music"], { encoding: "utf8" }).split("\n");
for (const [name, { md5, channels }] of Object.entries(BUNDLED)) {
    if (!tracked.includes(`docs/music/${name}`)) { errors.push(`songs: ${name} is not a committed file in docs/music/`); continue; }
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    const got = createHash("md5").update(bytes).digest("hex");
    if (got !== md5) errors.push(`songs: ${name} md5 ${got}, not the archive's ${md5}: its licence covers that file`);
    const ch = bytes[68] | (bytes[69] << 8); // the XM header's channel count
    if (ch !== channels) errors.push(`songs: ${name} has ${ch} channels, the screen says ${channels}`);
    const xm = await xmPlays(bytes);
    console.log(`  ${name}: ${xm.why}`);
    if (!xm.ok) errors.push(`songs: ${name} does not play (${xm.why})`);
}
if (tracked.includes("docs/music/local.xm")) errors.push("local: docs/music/local.xm is committed: it must stay on its owner's machine");

// exitCode, never process.exit() (see apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (BROKE) {
    const hit = errors.find((e) => e.startsWith("names:"));
    console.log(hit ? `xm_test_check: PASS (--break name caught: ${hit})` : "xm_test_check: FAILED -- --break name not caught");
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `xm_test_check: FAILED -- ${errors.join("; ")}` : "xm_test_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
