// VGM TEST (cart "vgm_test", apps/zig/scenes/vgm_test.zig): the test screen for the .vgm player
// (libs/zig/players/vgm.zig; apps/harness/vgm_check.mjs checks the player and its engine). Boots the cart over the
// real machine + ROM and presses keys through setShadeMode, as the loader and the glass do:
//   name     the cart asks for kestrel_fm.vgm at boot; key 1 for it again, key 2 for kestrel_fm.vgz, key 4
//            for "none" (zg.SONG_STOP)
//   bytes    key 3 is zg.requestSongBytes (sfx op 8, kind 7: SongKind.vgm) of the .vgz the cart carries;
//            mode 7 (no key) garbage bytes as a VGM
//   local    keys 5-7 ask for the local Sonic 1 tunes (sonic1_ghz / sonic1_special / sonic1_starlight.vgm:
//            gitignored, never fetched here, none tracked); with none playing the cart runs on past its
//            second of silence (the screen's "NOT ON THIS MACHINE")
//   bridge   site/js/sealed-loader.js's own postSfx turns each into loadVgm; the audio modules play the .vgz
//            (mode 1, heard) and refuse the garbage ("not a VGM", silent)
//   song     site/music/kestrel_fm.vgm is what libs/c/vgm/make_tune.py writes today, and the .vgz (site/music
//            and the cart's asset) inflates to it, byte for byte
//   node apps/harness/vgm_test_check.mjs [--break name|local]
//     name: key 2 is expected to ask for another file, so the check must fail
//     local: key 6 is expected to ask for another file
import { execFileSync } from "node:child_process";
import { readFile, mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gunzipSync } from "node:zlib";
import { cartRam, romRam } from "../../site/js/wasm_hiwater.js";

const bi = process.argv.indexOf("--break");
const BROKE = bi > 0 ? process.argv[bi + 1] || "name" : null;
const LOCAL = ["sonic1_ghz.vgm", "sonic1_special.vgm", "sonic1_starlight.vgm"];

async function bootCart(path) {
    const memory = new WebAssembly.Memory({ initial: 128, maximum: 128 });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("site/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("site/rom.wasm");
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

function songRequest(cart) {
    const { memory, demo } = cart;
    return demo.pollSongRequest() ? new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())) : null;
}

/** One key (or none), a frame: the song request by name (or null) and the loader's messages for the sfx queue. */
async function press(cart, key) {
    if (key !== null) cart.demo.setShadeMode(key);
    cart.demo.frame(16.6);
    const name = songRequest(cart);
    const { memory, demo } = cart;
    const src = (await readFile("site/js/sealed-loader.js", "utf8")).match(/^function postSfx\(mem, at, n\) \{[\s\S]*?^\}\n/m)[0];
    const posted = [];
    const run = new Function("audioNode", `let songGen = 0, sndhResident = null, songPosted = Promise.resolve(), sfxChain = Promise.resolve();
        ${src}; postSfx(arguments[1], arguments[2], arguments[3]); return sfxChain;`);
    await run({ port: { postMessage: (m) => posted.push(m) } }, memory, demo.sfxEntriesPtr(), demo.pollSfx());
    return { name, posted };
}

/** The worklet's loadVgm on the audio modules: loaded?, its status, mode, peak heard. */
async function loadVgm(msg) {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("site/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("site/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    const bytes = new Uint8Array(msg.bytes);
    new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
    const ok = a.audioLoadVgm(bytes.length);
    let peak = 0;
    for (let b = 0; b < 60; b++) {
        a.audioRender(735);
        for (const v of new Float32Array(memory.buffer, m.audioLeftPtr(), 735)) peak = Math.max(peak, Math.abs(v));
    }
    return { ok, status: (a.audioVgmStatus() >> 8) & 0xff, mode: a.audioMode(), peak };
}

const errors = [];
const vgm = new Uint8Array(await readFile("site/music/kestrel_fm.vgm"));
const dir = await mkdtemp(join(tmpdir(), "vgm_test_check-"));
execFileSync("python3", ["libs/c/vgm/make_tune.py", `${dir}/k.vgm`]);
if (Buffer.compare(await readFile(`${dir}/k.vgm`), vgm) !== 0) errors.push("song: site/music/kestrel_fm.vgm is not what make_tune.py writes");
const vgz = new Uint8Array(await readFile("apps/zig/assets/vgm/KESTREL_FM.VGZ"));
for (const f of ["site/music/kestrel_fm.vgz", "apps/zig/assets/vgm/KESTREL_FM.VGZ"])
    if (Buffer.compare(gunzipSync(await readFile(f)), vgm) !== 0) errors.push(`song: ${f} does not inflate to kestrel_fm.vgm`);
const cart = await bootCart("site/carts/demo-vgm_test.wasm");
const boot = await press(cart, null);
if (boot.name !== "kestrel_fm.vgm") errors.push(`name: the cart asked for ${boot.name} at boot`);
const names = [];
for (const [key, want] of [[0, "kestrel_fm.vgm"], [1, BROKE === "name" ? "other.vgz" : "kestrel_fm.vgz"], [3, "none"]]) {
    const k = await press(cart, key);
    names.push(k.name);
    if (k.name !== want) errors.push(`name: key ${key + 1} asked for ${k.name}, not ${want}`);
}
for (const [i, want] of LOCAL.entries()) {
    const k = await press(cart, 4 + i), w = BROKE === "local" && i === 1 ? "other.vgm" : want;
    if (k.name !== w) errors.push(`local: key ${5 + i} asked for ${k.name}, not ${w}`);
}
// No host plays them here, as on a card without the files: past the screen's second of silence the cart keeps
// running (a trap would throw out of frame()).
for (let f = 0; f < 90; f++) cart.demo.frame(16.6);
const tracked = execFileSync("git", ["ls-files", "--", ...LOCAL.map((n) => `site/music/${n}`)], { encoding: "utf8" }).trim();
if (tracked) errors.push(`local: ${tracked.split("\n").join(", ")} committed: the Sonic tunes stay on their owner's machine`);
for (const [key, garbage] of [[2, false], [7, true]]) {
    const { posted } = await press(cart, key);
    const msg = posted.find((p) => p.type === "loadVgm");
    const bytes = msg ? new Uint8Array(msg.bytes) : null;
    if (!bytes || (!garbage && Buffer.compare(bytes, vgz) !== 0) || (garbage && bytes[0] === 0x1f)) {
        errors.push(`bytes: mode ${key} posted ${posted.map((p) => p.type).join(",") || "nothing"}, not loadVgm of the ${garbage ? "garbage" : ".vgz"}`);
        continue;
    }
    const got = await loadVgm(msg);
    const fine = garbage ? !got.ok && got.status === 1 && got.mode === 0 && got.peak === 0 : got.ok && got.mode === 1 && got.peak > 0.01;
    if (!fine) errors.push(`bridge: mode ${key} ${JSON.stringify(got)}`);
    console.log(`  mode ${key}: loadVgm of ${bytes.length} bytes (${garbage ? "garbage: refused, status 1" : `the .vgz, played, mode 1, peak ${got.peak.toFixed(3)}`})`);
}
for (let f = 0; f < 90; f++) cart.demo.frame(16.6); // the screen's load readout redraws: no trap
console.log(`  boot: ${boot.name}; keys 1, 2, 4: ${names.join(", ")}; keys 5-7: ${LOCAL.join(", ")} (local, none tracked); the .vgm is make_tune.py's, both .vgz inflate to it`);
// exitCode, never process.exit() (see apps/harness/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (BROKE) {
    const hit = errors.find((e) => e.startsWith(`${BROKE}:`));
    console.log(hit ? `vgm_test_check: PASS (--break ${BROKE} caught: ${hit})` : `vgm_test_check: FAILED -- --break ${BROKE} not caught`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `vgm_test_check: FAILED -- ${errors.join("; ")}` : "vgm_test_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
