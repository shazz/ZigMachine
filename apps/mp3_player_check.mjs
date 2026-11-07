// MP3 PLAYER (cart "mp3_player", apps/zig/scenes/mp3_player.zig) end to end: the cart over the real
// machine + ROM, C: = docs/mp3-c.img (KOS GEMDOS through env.kosDriveRead, as the page and the native
// host serve it), its env.hostMp3* wired to the real audio modules a frame at a time (735 samples a
// frame, as a page with sound on renders them; the status read back synchronously).
//   list      C:\MUSIC's four .MP3 files, in name order (NOTES.TXT is not one)
//   bytes     Return on TONES44.MP3: the bytes the cart fed are the file's, in order, start to end, never
//             past the 64 KiB ring (nothing dropped), and it told the player the input ended
//   exact     the audio out is the reference decode >> 1 (apps/mp3_check.mjs's pin), sample for sample
//   next      at the end the next file starts by itself (TONES48), N skips, Esc stops, Esc again quits (4)
//   node apps/mp3_player_check.mjs [--break byte]
//     byte: one fed byte changed on its way, so the bytes and exact checks must fail
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { makeCDrive } from "./scene_hash_disk.mjs";

const PAGES = 128, AUDIO_PAGES = 48, BLOCK = 735;
const PIN44 = "bf403e4f2ee2e764b7a8ce2807f363206f691aad3dc6890b98b2b7d63d2516d9"; // apps/mp3_check.mjs TONES44
const BROKE = process.argv.includes("--break");
const K_ESC = 0xE012;

async function audio() {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    return { memory, m, a };
}

async function bootCart(snd, log) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile("docs/demo-mp3_player.wasm");
    const env = { memory, ...rom, kosDriveRead: makeCDrive(memory, new Uint8Array(await readFile("docs/mp3-c.img"))), kosFileOp: () => -46 };
    env.hostMp3Ctl = (op, arg) => { log.ctl.push(op); snd.a.audioMp3Ctl(op, arg); };
    env.hostMp3Feed = (ptr, len) => {
        const src = new Uint8Array(memory.buffer, ptr, len).slice();
        if (BROKE && log.fed.length <= 1000 && 1000 < log.fed.length + len) src[1000 - log.fed.length] ^= 1; // byte 1000, in a frame
        if (log.base === null) log.base = log.out.length; // this frame's audio is the first that can play it
        log.fed.push(...src);
        new Uint8Array(snd.memory.buffer, snd.a.audioMp3FeedPtr(), len).set(src);
        snd.a.audioMp3Feed(len);
    };
    env.hostMp3Status = (w) => snd.a.audioMp3Status(w) >>> 0;
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => 0;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, demo, machine };
}

/** `n` frames: the cart's, then a frame of audio; the output kept as s16 (L, R). */
function run(cart, snd, n, out, until) {
    for (let f = 0; f < n; f++) {
        cart.demo.frame(16.6);
        snd.a.audioRender(BLOCK);
        const l = new Float32Array(snd.memory.buffer, snd.m.audioLeftPtr(), BLOCK), r = new Float32Array(snd.memory.buffer, snd.m.audioRightPtr(), BLOCK);
        for (let i = 0; i < BLOCK; i++) out.push(Math.round(l[i] * 32768), Math.round(r[i] * 32768));
        if (until && until()) return f + 1;
    }
    return n;
}

const errors = [], notes = [];
const out = [];
const snd = await audio(), log = { ctl: [], fed: [], out, base: null };
const cart = await bootCart(snd, log);
run(cart, snd, 3, out);
cart.demo.input(1); // Down: MONO44, TONES32, [TONES44], TONES48
cart.demo.input(1);
cart.demo.key(13);
const file = new Uint8Array(await readFile("apps/zig/assets/mp3/TONES44.MP3"));
out.length = 0;
const frames = run(cart, snd, 1200, out, () => log.ctl.filter((c) => c === 0).length > 1); // until the next file starts
if (log.ctl[0] !== 0) errors.push(`bytes: Return sent ctl ${log.ctl[0]}, not start`);
const fed = Uint8Array.from(log.fed.slice(0, file.length));
if (log.fed.length < file.length || Buffer.compare(Buffer.from(fed), Buffer.from(file)) !== 0) errors.push(`bytes: the cart fed ${log.fed.length} bytes, not TONES44.MP3's ${file.length}`);
if (!log.ctl.includes(3)) errors.push("bytes: the end of the input never told");
if (snd.a.audioMp3Dropped()) errors.push(`bytes: ${snd.a.audioMp3Dropped()} bytes dropped (overfed)`);
const n = 308 * 1152 * 2;
const first = log.base ?? 0;
const got = Int16Array.from(out.slice(first, first + n));
const sha = createHash("sha256").update(Buffer.from(got.buffer)).digest("hex");
if (sha !== PIN44) errors.push(`exact: the audio is not the reference >> 1 (${sha.slice(0, 12)}, from sample ${first >> 1})`);
notes.push(`TONES44 via the cart: ${file.length} bytes fed in order, ${frames} frames to the next track, audio ${sha === PIN44 ? "= reference >> 1" : "differs"}`);
if (log.ctl.filter((c) => c === 0).length < 2) errors.push("next: the next file did not start at the end");
cart.demo.key("n".charCodeAt(0));
run(cart, snd, 5, []);
cart.demo.key(K_ESC);
run(cart, snd, 5, []);
if (log.ctl.at(-1) !== 1) errors.push(`next: Esc sent ctl ${log.ctl.at(-1)}, not stop`);
cart.demo.key(K_ESC);
run(cart, snd, 2, []);
if (cart.demo.pollCartRequest() !== 4) errors.push("next: Esc again did not ask to go back (4)");
notes.push(`controls: ${log.ctl.join(" ")} (0 start, 3 end, 1 stop), then request 4`);

for (const x of notes) console.log(`  ${x}`);
// exitCode, never process.exit() (see apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (BROKE) {
    const hit = errors.find((e) => e.startsWith("bytes:")) && errors.find((e) => e.startsWith("exact:"));
    console.log(hit ? `mp3_player_check: PASS (--break byte caught: ${errors.join("; ")})` : `mp3_player_check: FAILED -- --break byte not caught`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `mp3_player_check: FAILED -- ${errors.join("; ")}` : "mp3_player_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
