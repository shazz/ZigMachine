// Headless NORTH & SOUTH (battle) driver: boots the sealed machine the way
// docs/sealed-loader.js does and checks the cart against the REFERENCE MODEL
// (the rip's Python model, itself byte-exact against the original 68000 battle
// code on all 13 scripted battles):
//   replay   every script's per-frame inputs (the three bytes the original
//            read: last scancode, keyboard/port stick, port-1 stick) go through
//            the cart's battle (nsTestStart / nsTestFrame, the same Game the
//            scene plays); after EVERY frame the battle RAM (flat $1C3F0..
//            $1DA80, 5776 bytes), the screen the frame flipped to, the sound
//            sequences started, and the frame's length in VBLs must be the
//            model's (CRC-32s from apps/north_south_expect.json), and the
//            winner must be; no read may stray outside the game's memory
//   play     through the host path: the front page, Space starts the battle,
//            battle frames run on a 50 Hz VBL clock at a 60 Hz host (their
//            VBL lengths add up to the elapsed time), the plane shows the
//            battle screen through the field palette, '/' switches the unit
//            (sequence $1E = subtune 31 of north_south_digi.sndh), F10 leaves
//   sound    north_south_digi.sndh plays a sequence on the sealed YM
//   node apps/north_south_headless.mjs
//   node apps/north_south_headless.mjs --break    one poked RAM byte must FAIL the replay
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const AUDIO_PAGES = 48; // AUDIO_PAGES in machine/sdk/audio.zig
const SOUND = "north_south_digi.sndh";
const MODES = { 0: 0, 1: 1, 2: 2, 3: 3 };
const broke = process.argv.includes("--break");

async function boot(cart = "docs/demo-north_south.wasm") {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const env0 = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
    const rom = (await WebAssembly.instantiate(romBytes, { env: env0 })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cart);
    const env = { ...env0, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hwRam") || k.startsWith("hwRomRam")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

const CRC = new Uint32Array(256).map((_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
});
function crc32(b) {
    let c = 0xFFFFFFFF;
    for (let i = 0; i < b.length; i++) c = CRC[(c ^ b[i]) & 0xFF] ^ (c >>> 8);
    return (c ^ 0xFFFFFFFF) >>> 0;
}

// ---------------------------------------------------------------- replay
async function replay() {
    const expect = JSON.parse(await readFile("apps/north_south_expect.json", "utf8"));
    const { memory, demo } = await boot();
    const tot = { frames: 0, state: 0, screen: 0, sound: 0, vbl: 0, real_vbl: 0, results: 0, scripts: 0 };
    let failures = 0;
    for (const [name, e] of Object.entries(expect)) {
        const h = e.head;
        const u = h.union ?? [255, 255, 255], c = h.confed ?? [255, 255, 255];
        demo.nsTestStart(h.field ?? 2, ...u, ...c, MODES[h.mode], h.levels[0], h.levels[1], h.seed === null ? 0 : 1, (h.seed ?? 0) >>> 0);
        const ram = () => new Uint8Array(memory.buffer, demo.nsRamPtr(), demo.nsRamLen());
        const setupOk = crc32(ram()) === e.setup;
        if (!setupOk) { failures++; console.log(`  FAIL ${name}: the setup RAM is not the model's`); }
        let inp = [0, 0, 0], k = 0, result = 0, first = -1;
        const s = { state: 0, screen: 0, sound: 0, vbl: 0, real: 0 };
        e.frames.forEach((f, i) => {
            while (k < e.inputs.length && e.inputs[k][0] === i) inp = e.inputs[k++].slice(1);
            if (broke && i === 50) ram()[0x1C7FA - 0x1C3F0 + 3] ^= 1; // the RNG's low byte
            result = demo.nsTestFrame(...inp);
            const [ramCrc, scrCrc, vbls, realVbls, , ...ev] = f;
            const st = crc32(ram()) === ramCrc;
            const sc = crc32(new Uint8Array(memory.buffer, demo.nsShownPtr(), 64000)) === scrCrc;
            const got = Array.from({ length: demo.nsEventCount() }, (_, j) => demo.nsEvent(j));
            const sn = got.length === ev.length && got.every((v, j) => v === ev[j]);
            const vb = demo.nsVbls() === vbls;
            s.state += st; s.screen += sc; s.sound += sn; s.vbl += vb; s.real += demo.nsVbls() === realVbls;
            if (!(st && sc && sn && vb) && first < 0) first = i;
        });
        const resOk = result === e.result;
        const misses = demo.nsMisses();
        const n = e.frames.length;
        const ok = setupOk && s.state === n && s.screen === n && s.sound === n && s.vbl === n && resOk && misses === 0;
        if (!ok) failures++;
        console.log(`  ${ok ? "ok  " : "FAIL"} ${name.padEnd(28)} ${n} frames: state ${s.state} screen ${s.screen} sound ${s.sound} vbl ${s.vbl}` +
            ` (real game ${s.real})  result ${result}/${e.result}${misses ? `  ${misses} stray reads` : ""}${first >= 0 ? `  first bad frame ${first}` : ""}`);
        tot.frames += n; tot.state += s.state; tot.screen += s.screen; tot.sound += s.sound; tot.vbl += s.vbl;
        tot.real_vbl += s.real; tot.results += resOk; tot.scripts++;
    }
    console.log(`  replay: ${tot.scripts} scripts, ${tot.frames} frames — state ${tot.state}, screen ${tot.screen}, sound ${tot.sound},` +
        ` VBLs ${tot.vbl} equal to the model (${tot.real_vbl} to the real game, ${(100 * tot.real_vbl / tot.frames).toFixed(1)} %),` +
        ` results ${tot.results}/${tot.scripts}`);
    return failures;
}

// ---------------------------------------------------------------- play
async function play() {
    const { memory, machine, demo } = await boot();
    const dec = new TextDecoder();
    const songs = [];
    const PW = machine.hwPhysWidth(), BX = machine.hwBorderX(), BY = 40;
    const host = (n, dt = 1000 / 60) => {
        for (let i = 0; i < n; i++) {
            machine.hwClear();
            demo.frame(dt);
            if (demo.pollSongRequest())
                songs.push([dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())), demo.songTune()]);
            machine.hwRenderPlane(0);
        }
    };
    let failures = 0;
    const check = (what, ok) => { if (!ok) failures++; console.log(`  ${ok ? "ok  " : "FAIL"} ${what}`); };
    const pfb = () => new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), PW * machine.hwPhysHeight() * 4);
    const px = (x, y) => { const p = pfb(), i = ((BY + y) * PW + BX + 2 * x) * 4; return (p[i] << 16) | (p[i + 1] << 8) | p[i + 2]; };

    host(2);
    let lit = 0;
    for (let x = 0; x < 320; x++) lit += px(x, 43) !== 0; // the title, y 40..47
    check(`the front page is up (${lit} lit pixels on the title row)`, lit > 20 && demo.nsFrames() === 0);

    demo.key(32); // Space on START: river, you = Union vs CPU, 6/3/1 each
    const t0 = performance.now();
    let vblSum = 0, frames = 0;
    const VBLS = 1500; // 30 s at 50 Hz, run at a 60 Hz host
    let switched = false;
    for (let i = 0; i < VBLS * 6 / 5; i++) {
        host(1);
        if (demo.nsFrames() !== frames) { frames = demo.nsFrames(); vblSum += demo.nsVbls(); }
        if (i === 300) demo.key(47); // '/' = Right Shift: switch unit
        if (i === 306) { demo.keyUp(47); switched = true; }
    }
    const ms = (performance.now() - t0) / (VBLS * 6 / 5);
    // The last frame's span runs past the window by up to its own length (9 at most).
    check(`${frames} battle frames in ${VBLS} VBLs at a 60 Hz host; their VBL lengths add up to ${vblSum}`,
        frames > VBLS / 10 && vblSum >= VBLS - 2 && vblSum <= VBLS + 9);
    const shown = new Uint8Array(memory.buffer, demo.nsShownPtr(), 64000);
    let same = 0;
    const pal = new Map();
    for (let i = 0; i < 64000; i++) {
        const c = px(i % 320, (i / 320) | 0);
        if (!pal.has(shown[i])) pal.set(shown[i], c);
        same += pal.get(shown[i]) === c;
    }
    check(`the plane shows the battle's screen (${same}/64000 pixels consistent with one colour per index)`, same === 64000 && pal.size > 4);
    const ours = songs.filter(([n]) => n === SOUND);
    check(`${ours.length} sound requests, all ${SOUND} subtunes 1..47`, ours.length > 0 && ours.length === songs.length && ours.every(([, t]) => t >= 1 && t <= 47));
    check(`'/' switched the unit: subtune 31 (sequence $1E) was requested`, switched && ours.some(([, t]) => t === 31));
    demo.key(0xE00A); // F10
    check("F10 leaves for the menu", demo.pollCartRequest() === -1);
    console.log(`  ${ms.toFixed(3)} ms per host frame (battle + present + plane composite)`);
    return failures;
}

// ---------------------------------------------------------------- sound
// Subtune n+1 plays sequence n: every sample of it, one level byte per Timer A
// tick at 614400/data Hz, then silence. The YM volume registers are sampled
// every 8 output samples: the level changes must stop when the sequence's last
// sample ends, and there can be no more of them than level bytes.
async function sound() {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const name of Object.keys(machine)) if (name.startsWith("machine")) env[name] = machine[name];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const tune = new Uint8Array(await readFile(`docs/music/${SOUND}`));
    new Uint8Array(memory.buffer, audio.audioSongPtr(), tune.length).set(tune);
    const loaded = audio.audioLoadSndh(tune.length) && audio.audioSndhSubtunes() === 47;
    const SEQ = 0x29; // a two-soldier volley
    const bank = await readFile("apps/zig/assets/screens/north_south/ns_battle_digi.bin");
    const nseq = bank.readUInt16BE(6), nsmp = bank.readUInt16BE(8);
    let p = bank.readUInt32BE(12 + 4 * SEQ), bytes = 0, secs = 0;
    for (; bank[p] !== 0xFF; p += 2) {
        const len = bank.readUInt32BE(12 + 4 * nseq + 4 * nsmp + 4 * bank[p]) - 1;
        bytes += len;
        secs += len * bank[p + 1] / 614400;
    }
    audio.audioSndhPlay(SEQ + 1);
    const regs = new Uint8Array(memory.buffer, machine.audioYmRegsPtr(), 16);
    const left = new Float32Array(memory.buffer, machine.audioLeftPtr(), 8);
    const RATE = 44100, STEP = 8;
    let prev = -1, changes = 0, lastAt = 0, peak = 0;
    for (let n = 0; n < RATE; n += STEP) {
        audio.audioRender(STEP);
        for (const v of left) peak = Math.max(peak, Math.abs(v));
        const v = regs[8] | regs[9] << 8 | regs[10] << 16;
        if (v !== prev) { changes++; lastAt = n / RATE; prev = v; }
    }
    const ok = loaded && peak > 0.05 && changes > bytes / 4 && changes <= bytes + 1 && Math.abs(lastAt - secs) < 0.05;
    console.log(`  ${ok ? "ok  " : "FAIL"} ${SOUND}: 47 subtunes; sequence $29 = ${bytes} level bytes over ${(secs * 1000).toFixed(0)} ms,` +
        ` played as ${changes} volume changes ending at ${(lastAt * 1000).toFixed(0)} ms (peak ${peak.toFixed(3)})`);
    return ok ? 0 : 1;
}

const bad = await replay();
if (broke) {
    console.log(bad ? `north_south: PASS (--break caught: ${bad} scripts differ)` : "north_south: FAILED — --break was not caught");
    process.exit(bad ? 0 : 1);
}
const total = bad + await play() + await sound();
console.log(total ? `north_south: FAILED (${total})` : "north_south: PASS");
process.exit(total ? 1 : 0);
