// SID TEST (cart "sid_test", apps/zig/scenes/sid_test.zig): the test screen for the .sid player
// (libs/zig/players/sid.zig; apps/sid_check.mjs checks the player and its engine). Boots the cart over
// the real machine + ROM and presses keys through setShadeMode, as the loader and the glass do:
//   name     key 1 asks for hermini.sid by name; key 5 for "none" (zg.SONG_STOP)
//   bytes    key 2 is zg.requestSongBytes (sfx op 8, kind 6: SongKind.sid) of the tune's exact bytes, the
//            path a C64 port takes for a tune read off its own disk; key 3 the same bytes as an RSID
//   bridge   docs/sealed-loader.js's own postSfx turns each into loadSid; the audio modules play the PSID
//            (mode 1, heard) and refuse the RSID ("RSID not supported", silent)
//   song     docs/music/hermini.sid and apps/zig/assets/sid/HERMINI.SID are cRSID's HerMiniSID (md5)
//   node apps/sid_test_check.mjs [--break name]
//     name: key 1 is expected to ask for another file, so the check must fail
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const BROKE = process.argv.includes("--break");
const MD5 = "537f693740ed05502fc23151381082d9"; // libs/c/crsid/upstream/tests/HerMiniSID.sid

async function bootCart(path) {
    const memory = new WebAssembly.Memory({ initial: 128, maximum: 128 });
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

/** One key, a frame: the song request by name (or null) and the loader's messages for the sfx queue. */
async function press(cart, key) {
    cart.demo.setShadeMode(key);
    cart.demo.frame(16.6);
    const { memory, demo } = cart;
    const name = demo.pollSongRequest() ? new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())) : null;
    const src = (await readFile("docs/sealed-loader.js", "utf8")).match(/^function postSfx\(mem, at, n\) \{[\s\S]*?^\}\n/m)[0];
    const posted = [];
    const run = new Function("audioNode", `let songGen = 0, sndhResident = null, songPosted = Promise.resolve(), sfxChain = Promise.resolve();
        ${src}; postSfx(arguments[1], arguments[2], arguments[3]); return sfxChain;`);
    await run({ port: { postMessage: (m) => posted.push(m) } }, memory, demo.sfxEntriesPtr(), demo.pollSfx());
    return { name, posted };
}

/** The worklet's loadSid on the audio modules: loaded?, its status, mode, heard? */
async function loadSid(msg) {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    const bytes = new Uint8Array(msg.bytes);
    new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
    const ok = a.audioLoadSid(bytes.length, msg.tune >>> 0);
    let peak = 0;
    for (let b = 0; b < 60; b++) {
        a.audioRender(735);
        for (const v of new Float32Array(memory.buffer, m.audioLeftPtr(), 735)) peak = Math.max(peak, Math.abs(v));
    }
    return { ok, status: (a.audioSidStatus() >> 8) & 0xff, mode: a.audioMode(), peak };
}

const errors = [], tune = new Uint8Array(await readFile("docs/music/hermini.sid"));
for (const f of ["docs/music/hermini.sid", "apps/zig/assets/sid/HERMINI.SID"]) {
    const md5 = createHash("md5").update(await readFile(f)).digest("hex");
    if (md5 !== MD5) errors.push(`song: ${f} md5 ${md5}, not HerMiniSID's ${MD5}`);
}
const cart = await bootCart("docs/demo-sid_test.wasm");
const k1 = await press(cart, 0);
if (k1.name !== (BROKE ? "other.sid" : "hermini.sid")) errors.push(`name: key 1 asked for ${k1.name}`);
for (const [key, rsid] of [[1, false], [2, true]]) {
    const { posted } = await press(cart, key);
    const msg = posted.find((p) => p.type === "loadSid");
    const bytes = msg ? new Uint8Array(msg.bytes) : null;
    const want = tune.slice();
    if (rsid) want[0] = "R".charCodeAt(0);
    if (!bytes || bytes.length !== want.length || bytes.some((b, i) => b !== want[i])) {
        errors.push(`bytes: key ${key + 1} posted ${posted.map((p) => p.type).join(",") || "nothing"}, not loadSid of the ${rsid ? "RSID" : "tune"}'s bytes`);
        continue;
    }
    const got = await loadSid(msg);
    const fine = rsid ? !got.ok && got.status === 2 && got.mode === 0 && got.peak === 0 : got.ok && got.mode === 1 && got.peak > 0.01;
    if (!fine) errors.push(`bridge: key ${key + 1} ${JSON.stringify(got)}`);
    console.log(`  key ${key + 1}: loadSid of ${bytes.length} bytes (${rsid ? "RSID: refused, status 2" : `played, mode 1, peak ${got.peak.toFixed(3)}`})`);
}
const k5 = await press(cart, 4);
if (k5.name !== "none") errors.push(`name: key 5 asked for ${k5.name}, not none`);
console.log(`  key 1: asks for ${k1.name}; key 5: ${k5.name}; both tune files are HerMiniSID (md5)`);
// exitCode, never process.exit() (see apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (BROKE) {
    const hit = errors.find((e) => e.startsWith("name:"));
    console.log(hit ? `sid_test_check: PASS (--break name caught: ${hit})` : "sid_test_check: FAILED -- --break name not caught");
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `sid_test_check: FAILED -- ${errors.join("; ")}` : "sid_test_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
