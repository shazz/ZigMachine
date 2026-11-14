// KESTRAMP (cart 133, apps/zig/scenes/kestramp.zig) end to end: the cart over the real machine + ROM,
// C: = docs/mp3-c.img through KOS GEMDOS, its env.hostMp3* wired to the audio modules a frame at a time
// (as apps/mp3_player_check.mjs). C:\MUSIC in name order: MONO44, TONES32, TONES44, TONES48. The window is
// read back from the plane and checked by region: draws; X starts MONO44 (time and status move); B / Z
// start TONES32 and back (the title box changes); V stops (time back at 00:00); L draws the list; a track
// that ends starts the next; Esc asks for request 4.   node apps/kestramp_check.mjs [--shots DIR]
import { readFile, mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { makeCDrive } from "./scene_hash_disk.mjs";
import { writePng } from "./scene_png.mjs";
const PAGES = 128, AUDIO_PAGES = 48, BLOCK = 735, W = 320, H = 200;
const K_ESC = 0xE012;
const CTL_START = 0, CTL_STOP = 1, CTL_END = 3;
const REGION = { time: [6, 14, 93, 27], title: [102, 14, 210, 11], status: [6, 90, 306, 9], list: [6, 102, 306, 72], logo: [6, 3, 64, 8] };
const SHOTS = process.argv.includes("--shots") ? process.argv[process.argv.indexOf("--shots") + 1] : null;
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
    const cartBytes = await readFile("docs/demo-kestramp.wasm");
    const env = { memory, ...rom, kosDriveRead: makeCDrive(memory, new Uint8Array(await readFile("docs/mp3-c.img"))), kosFileOp: () => -46 };
    env.hostMp3Ctl = (op, arg) => {
        log.ctl.push(op);
        if (op === CTL_START) log.starts.push(log.fed.length); // where this file's bytes begin in log.fed
        snd.a.audioMp3Ctl(op, arg);
    };
    env.hostMp3Feed = (ptr, len) => {
        const src = new Uint8Array(memory.buffer, ptr, len).slice();
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
/** `n` frames of the cart and of the audio; the output kept as s16 (L, R). Stops early when `until` says so. */
function run(cart, snd, n, out, until) {
    for (let f = 0; f < n; f++) {
        cart.machine.hwClear();
        cart.demo.frame(16.6);
        snd.a.audioRender(BLOCK);
        const l = new Float32Array(snd.memory.buffer, snd.m.audioLeftPtr(), BLOCK), r = new Float32Array(snd.memory.buffer, snd.m.audioRightPtr(), BLOCK);
        for (let i = 0; i < BLOCK; i++) out.push(Math.round(l[i] * 32768), Math.round(r[i] * 32768));
        if (until && until()) return f + 1;
    }
    return n;
}
// The physical frame is PW x PH. The plane's 320 x 200 window sits at (OX, OY) in it, and is drawn
// twice as wide (each logical column is two physical ones), so logical x is physical OX + 2x.
let PW = 0, PH = 0, OX = -1, OY = 0;
const SCALE_X = 2;
/** The physical picture after the plane's render (PW x PH RGBA words); the window's origin is its first non-black pixel. */
function picture(cart) {
    cart.machine.hwRenderPlane(0);
    PW = cart.machine.hwPhysWidth();
    PH = cart.machine.hwPhysHeight();
    const px = new Uint32Array(cart.memory.buffer, cart.machine.hwPhysicalPtr(), PW * PH).slice();
    if (OX < 0) {
        const first = px.findIndex((p) => (p & 0x00ffffff) !== 0);
        if (first < 0) throw new Error("the picture is all black");
        OX = first % PW;
        OY = Math.floor(first / PW);
    }
    return px;
}
/** The window's logical picture: W x H words, one per logical pixel (the left column of each doubled pair). */
function windowOf(px) {
    const out = new Uint32Array(W * H);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) out[y * W + x] = px[(OY + y) * PW + OX + SCALE_X * x];
    return out;
}
function region(px, [x, y, w, h]) {
    const hash = createHash("sha256");
    const win = windowOf(px);
    for (let r = 0; r < h; r++) hash.update(Buffer.from(win.buffer, ((y + r) * W + x) * 4, w * 4));
    return hash.digest("hex").slice(0, 16);
}
function colours(px, [x, y, w, h]) {
    const win = windowOf(px);
    const set = new Set();
    for (let r = 0; r < h; r++) for (let c = 0; c < w; c++) set.add(win[(y + r) * W + x + c]);
    return set.size;
}
const errors = [], notes = [];
const check = (ok, msg) => { if (!ok) errors.push(msg); };
const asset = async (name) => new Uint8Array(await readFile(join("apps/zig/assets/mp3", name)));
/** The first `n` bytes fed since `from` are the file's first `n` bytes. */
const fedIs = (log, from, file, n) => {
    const got = log.fed.slice(from, from + n);
    return got.length === n && Buffer.compare(Buffer.from(got), Buffer.from(file.subarray(0, n))) === 0;
};
const snd = await audio();
const log = { ctl: [], fed: [], starts: [], out: [] };
const cart = await bootCart(snd, log);
const MONO = await asset("MONO44.MP3"), TONES32 = await asset("TONES32.MP3");
// draws: the stopped window, before any key
run(cart, snd, 3, log.out);
const idle = picture(cart);
check(colours(idle, [0, 0, W, H]) >= 6, `draws: the window has ${colours(idle, [0, 0, W, H])} colours, not the panel's`);
check(colours(idle, REGION.logo) >= 2, "draws: the logo is not on the picture");
check(colours(idle, REGION.list) === 1, "draws: the list shows with the list closed");
const idleTime = region(idle, REGION.time), idleStatus = region(idle, REGION.status);
notes.push(`window: ${colours(idle, [0, 0, W, H])} colours, logo and panel drawn, list closed`);
if (SHOTS) {
    await mkdir(SHOTS, { recursive: true });
    writePng(join(SHOTS, "stopped.png"), new Uint8Array(windowOf(idle).buffer), W, H);
}
// X: the first file of C:\MUSIC (name order) starts; the time and the status move. MONO44 plays out
// in about 80 frames and the cart then starts the next file by itself, so every step below waits for
// the start it caused (never a fixed count) and presses the next key at once.
const startedSince = (n) => log.starts.length > n;
cart.demo.key("x".charCodeAt(0));
run(cart, snd, 200, log.out, () => (snd.a.audioMp3Status(2) >>> 0) >= 40); // about a second decoded
const playing = picture(cart);
check(log.ctl[0] === CTL_START, `X: the first control was ${log.ctl[0]}, not start`);
check(log.starts.length === 1 && fedIs(log, 0, MONO, 1000), "X: the bytes fed are not MONO44.MP3's (the first track)");
check(region(playing, REGION.time) !== idleTime, "X: the time box did not advance from 00:00");
check(region(playing, REGION.status) !== idleStatus, "X: the status line did not change to PLAYING");
const playingTitle = region(playing, REGION.title);
notes.push(`X: MONO44.MP3 fed in order, ${log.fed.length} bytes so far; the time box moved off 00:00`);
if (SHOTS) writePng(join(SHOTS, "playing.png"), new Uint8Array(windowOf(playing).buffer), W, H);
// B: the next track, TONES32; Z: back to MONO44
cart.demo.key("b".charCodeAt(0));
run(cart, snd, 5, log.out, () => startedSince(1));
check(startedSince(1) && log.ctl.at(-1) === CTL_START, "B: next did not start a track");
check(log.starts.length >= 2 && fedIs(log, log.starts[1], TONES32, 1000), "B: the track after MONO44 is not TONES32.MP3");
const nextPic = picture(cart);
check(region(nextPic, REGION.title) !== playingTitle, "B: the title box did not change");
cart.demo.key("z".charCodeAt(0));
run(cart, snd, 5, log.out, () => startedSince(2));
check(log.starts.length >= 3 && fedIs(log, log.starts[2], MONO, 1000), "Z: prev did not start MONO44.MP3 again");
const backPic = picture(cart);
check(region(backPic, REGION.title) === playingTitle, "Z: the title box did not return to MONO44's");
notes.push("B / Z: TONES32 then MONO44 again, the title box changes both ways");
// V: stop; the window goes back to the stopped picture
cart.demo.key("v".charCodeAt(0));
run(cart, snd, 3, log.out);
const stopped = picture(cart);
check(log.ctl.at(-1) === CTL_STOP, `V: the last control was ${log.ctl.at(-1)}, not stop`);
check(region(stopped, REGION.time) === idleTime, "V: the time box is not back at 00:00");
check(region(stopped, REGION.status) === idleStatus, "V: the status line is not back at STOPPED");
notes.push("V: stop (ctl 1), the time back at 00:00, STOPPED");
// L: the list opens and shows the four files
cart.demo.key("l".charCodeAt(0));
run(cart, snd, 2, log.out);
const listPic = picture(cart);
check(colours(listPic, REGION.list) >= 3 && region(listPic, REGION.list) !== region(stopped, REGION.list), "L: the list did not draw");
if (SHOTS) writePng(join(SHOTS, "list.png"), new Uint8Array(windowOf(listPic).buffer), W, H);
cart.demo.key("l".charCodeAt(0));
run(cart, snd, 2, log.out);
// end: X plays MONO44; when it ends by itself the next file (TONES32) starts
const base = log.starts.length; // starts before this X
const ctlBase = log.ctl.length;
cart.demo.key("x".charCodeAt(0));
const frames = run(cart, snd, 4000, log.out, () => startedSince(base + 1));
run(cart, snd, 5, log.out); // the new file's first chunk is fed a frame after its start
const tail = log.ctl.slice(ctlBase);
check(tail.includes(CTL_END) && tail.indexOf(CTL_START, tail.indexOf(CTL_END)) > 0, "end: the track ended and the next start did not follow");
check(startedSince(base + 1) && fedIs(log, log.starts[base + 1], TONES32, 1000), "end: the track after the one that ended is not TONES32.MP3");
notes.push(`end: MONO44 ended after ${frames} frames, the next track (TONES32) started by itself`);
// Esc: stop, and the host gets the request to go back
cart.demo.key(K_ESC);
run(cart, snd, 2, log.out);
check(log.ctl.at(-1) === CTL_STOP, `Esc: the last control was ${log.ctl.at(-1)}, not stop`);
check(cart.demo.pollCartRequest() === 4, "Esc: the cart did not ask to go back (4)");
notes.push(`controls: ${log.ctl.join(" ")} (0 start, 1 stop, 3 end), then Esc asks for request 4`);
for (const x of notes) console.log(`  ${x}`);
console.log(errors.length ? `kestramp_check: FAILED -- ${errors.join("; ")}` : "kestramp_check: all pass");
// exitCode, never process.exit() (see apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
process.exitCode = errors.length ? 1 : 0;
