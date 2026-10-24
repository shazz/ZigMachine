// Headless JOCHEN HIPPEL MUSIC DEMO check (cart 109, apps/zig/scenes/hippel_musicdisk.zig).
// The harness holds the cart to its OWN model of the Amiga screen, written from
// the original's code (prototypes/hippel_musicdisk_re/NOTES.md), not from the Zig;
// it reads only the ripped data (tables.bin = $0678..$0817, font.bin = $1286..):
//
//   pixels  every frame for 600 frames (> 2 turns of the 192-line copper scroll,
//           > 60 bar rotations), planes 0 and 1 as the machine composes them =
//           the model on all 400x280: the two COLOR00 bars on lines $2F../$108..
//           (row = line - 24), each the table minus the grey per channel, the
//           top one rotated left and one rotation behind, the bottom one right;
//           the text (the $0168 printer's bitmap, PF1 = row n+1) in the COLOR01
//           of its 8-px copper column (one px lead), row (n + phase) mod 192 of
//           $0372's 4 blocks x 3, lines $100..$106 holding line $FF's last
//           move; the $888 shadow (PF2 = row n, one px right) under it
//   pacing  the phase is the original's 50 Hz frame: 5 steps every 6 frames
//   music   rings_of_medusa.hip song 1 at start ('i'); keys a..j (and A..J) ask
//           for the module and song of the original's table; every file is in
//           docs/music/hippel/, a .hip (bra, bra, "TFMX" past the player) on the
//           same 0xA2C-byte replay, with at least that many songs; each of the
//           ten PLAYS 8 s on demo-audio's .hip player (loud, a Paula voice started, no
//           bad pointer or unanswered write, no two the same sound) -- or the run
//           says NOT CHECKED while that player is not in docs/ (--audio DIR)
//   leave   a key that is not a tune asks for nothing; Escape leaves
//
//   node apps/hippel_musicdisk_headless.mjs [--break pixels|lead|music|pacing] [--ppm FILE] [--audio DIR]  (FILE: frame 300, 400x280)
//     each --break must be caught (the model is wrong on purpose)
import { readFileSync, writeFileSync } from "node:fs";
import { cartRam } from "../docs/wasm_hiwater.js";
import { screenModel } from "./hippel_musicdisk_model.mjs";
import { playHip } from "./hippel_musicdisk_audio.mjs";

const PAGES = 112, W = 400, H = 280, PW = 800;
const argv = process.argv.slice(2);
const opt = (n) => { const i = argv.indexOf(n); return i < 0 ? null : argv[i + 1]; };
const brk = opt("--break");
if (brk && !["pixels", "lead", "music", "pacing"].includes(brk)) throw new Error("--break pixels|lead|music|pacing");
const ppm = opt("--ppm");
const audioDir = opt("--audio") ?? "docs"; // where demo-audio.wasm + machine-audio.wasm are

// ---------------- boot -------------------------------------------------------
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(readFileSync("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(readFileSync("docs/rom.wasm"), { env: romEnv })).instance.exports;
const cartBytes = readFileSync("docs/demo-hippel_musicdisk.wasm");
const env = { ...romEnv, ...rom };
for (const k of Object.keys(machine)) if (/^hw(Rom)?Ram/.test(k)) env[k] = machine[k];
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
machine.hwInit();
demo.boot();
demo.skipBoot();

const errors = [];
const ok = (cond, msg) => { console.log(`  ${cond ? "ok  " : "FAIL"} ${msg}`); if (!cond) errors.push(msg); };
const model = screenModel({ lead: brk === "lead" ? 0 : 1 });

// ---------------- 1. music ---------------------------------------------------
// The original's $04E2 table: key -> module, song (NOTES.md).
const TUNES = [["warp_title", 1], ["warp_ingame2", 1], ["warp_ingame2", 2], ["warp_ingame1", 2],
    ["warp_ingame1", 3], ["warp_ingame1", 4], ["thalion_intro", 1], ["thalion_intro", 2],
    ["rings_of_medusa", 1], ["rings_of_medusa", 2]];
if (brk === "music") TUNES[3] = ["warp_ingame1", 1];
const request = () => demo.pollSongRequest() === 1
    ? `${new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()))}#${demo.songTune()}` : null;
const want = ([m, s]) => `hippel/${m}.hip#${s}`;
ok(request() === want(TUNES[8]), `music: the start asks for ${want(TUNES[8])} ('i', as the original's $00C6)`);
const PLAYER = 0xA2C;
let player = null;
for (const [m, s] of TUNES) {
    const f = readFileSync(`docs/music/hippel/${m}.hip`);
    const isHip = f[0] === 0x60 && f[2] === 0x60 && f.toString("latin1", PLAYER, PLAYER + 4) === "TFMX";
    player ??= f.subarray(0, PLAYER);
    const songs = f.readUInt16BE(PLAYER + 16); // the TFMX header's song count
    ok(isHip && songs >= s && f.subarray(0, PLAYER).equals(player), `music: ${m}.hip is a .hip on the Rings of Medusa replay, ${songs} song(s) >= ${s}`);
}
// each tune PLAYS on the machine's .hip player: loud, a voice started, every pointer
// in the 68000's RAM, and two songs of one module are not the same sound
const sigs = new Map();
for (const [m, s] of brk ? [] : TUNES) {
    const r = await playHip(audioDir, readFileSync(`docs/music/hippel/${m}.hip`), s, 8);
    if (r === null) { console.log(`  NOT CHECKED: ${audioDir}/demo-audio.wasm has no .hip player yet (libs/zig/players/hip_player.zig not merged)`); break; }
    const dup = sigs.get(r.sig);
    sigs.set(r.sig, `${m}#${s}`);
    ok(!r.error && r.span > 0.2 && r.voices >= 1 && r.bad === 0 && !dup,
        `play: ${m}.hip song ${s}: ${r.error ?? `peak to peak ${r.span.toFixed(2)}, ${r.voices} voices, ${r.bad} bad pointers/writes${dup ? `, SAME as ${dup}` : ""}`}`);
}

// ---------------- 2. pixels and pacing, frame by frame -----------------------
const FRAMES = 600;
let bad = 0, first = null, paceBad = 0;
const pfb = () => new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), PW * H);
const shown = new Uint32Array(W * H);
for (let n = 0; n < FRAMES; n++) {
    demo.frame(16.6);
    const p = demo.hipPhase();
    const pace = brk === "pacing" ? n + 1 : Math.floor(((n + 1) * 5) / 6);
    if (p !== pace) paceBad++;
    compose(shown);
    const m = model.frame(p);
    if (brk === "pixels" && n === 300) m[(0x30 - 24) * W + 7] ^= 0x00_0011;
    let diff = -1;
    for (let i = 0; i < W * H; i++) if (shown[i] !== m[i]) { diff = i; break; }
    if (diff >= 0) {
        bad++;
        first ??= `frame ${n} (phase ${p}) x ${diff % W} y ${Math.floor(diff / W)}: cart ${hex(shown[diff])} model ${hex(m[diff])}`;
    }
    if (ppm && n === 300) writePpm(ppm, shown);
}
ok(paceBad === 0, `pacing: the phase is the 50 Hz frame, 5 steps in 6 (${paceBad} frames off)`);
ok(bad === 0, `pixels: planes 0+1 = the model on ${FRAMES - bad}/${FRAMES} frames (400x280)${first ? `; first: ${first}` : ""}`);

// ---------------- 3. keys and leaving ---------------------------------------
for (let k = 0; k < TUNES.length; k++) {
    demo.key((k % 2 ? 65 : 97) + k); // alternate a / B / c / D ...
    demo.frame(16.6);
    const got = request();
    ok(got === want(TUNES[k]) && demo.hipTune() === k, `key ${String.fromCharCode(97 + k)}: asks for ${got} (want ${want(TUNES[k])})`);
}
demo.key(0x6B); demo.frame(16.6); // 'k': not a tune
ok(request() === null && demo.pollCartRequest() === 0, "key k: no request, and the cart stays");
demo.key(0xE012); demo.frame(16.6);
ok(demo.pollCartRequest() === -1, "Escape leaves");

function hex(v) { return (v >>> 0).toString(16).padStart(8, "0"); }

// plane 1 over plane 0; low-res pixel x is physical 2x of the 800-wide raster
function compose(out) {
    machine.hwRenderPlane(0);
    const back = pfb();
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) out[y * W + x] = back[y * PW + 2 * x];
    machine.hwRenderPlane(1);
    const top = pfb();
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const v = top[y * PW + 2 * x];
        if (v >>> 24) out[y * W + x] = v >>> 0;
    }
}

function writePpm(file, img) {
    const body = Buffer.alloc(W * H * 3);
    for (let i = 0; i < W * H; i++) { body[3 * i] = img[i] & 255; body[3 * i + 1] = (img[i] >> 8) & 255; body[3 * i + 2] = (img[i] >> 16) & 255; }
    writeFileSync(file, Buffer.concat([Buffer.from(`P6\n${W} ${H}\n255\n`), body]));
    console.log(`  shot: ${file}`);
}

if (brk) {
    console.log(errors.length ? `hippel_musicdisk: PASS (--break ${brk} caught: ${errors[0]})` : `hippel_musicdisk: FAILED -- --break ${brk} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `hippel_musicdisk: FAILED -- ${errors.join("; ")}` : `hippel_musicdisk: all pass, ${FRAMES} frames`);
process.exit(errors.length ? 1 : 0);
