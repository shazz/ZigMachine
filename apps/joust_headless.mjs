// Headless JOUST driver. Boots the sealed machine the way docs/sealed-loader.js
// does, then checks the cart against the REAL PROGRAM (JOUST.PRG run on the
// rip's 68000 harness, which the Python reference model reproduces frame for
// frame -- apps/joust_fixture.json.gz, from tools/private_tools/joust_fixture.py):
//   replay   two recorded games from power-on, in lockstep: the 1-player TAS
//            (18,293 frames, to wave 9) and the 2-player TAS (7,015 frames).
//            The title's '1' / '2' arrives at the harness's cycle, and every
//            frame gets the joystick bytes the harness's IKBD delivered. Every
//            frame must take the harness's number of 50 Hz VBLs and start the
//            harness's Dosound scripts; every 25th frame start, the game's RAM
//            ($0D00-$1C90, $81CC-$8210, $86DA-$8710) + the screen hash and the
//            CPU cycle count are the harness's, exactly.
//   live     the cart as a player runs it: the title up, '1' on the keyboard
//            starts a game, the screen on the plane is the ST screen through
//            the colour registers, the title tune (subtune 15) and the game's
//            SFX are requested from joust_sfx.sndh, and at a 60 Hz host the
//            machine keeps the ST's 50 Hz time.
//   sound    joust_sfx.sndh, on the sealed audio machine: subtune n+1 leaves the
//            YM registers where TOS's Dosound leaves them running script n of
//            JOUST.PRG ($17E2 table), tick after 50 Hz tick, for all 16 scripts;
//            subtune 17 (the siren) sweeps for ~0.77 s and ends silent.
//   node apps/joust_headless.mjs [outdir]
//   node apps/joust_headless.mjs --break joy     P1's fire flipped on one frame:
//            passes only if the replay checks catch it
//   node apps/joust_headless.mjs --break clock   4 extra CPU cycles once (a
//            one-instruction slip): passes only if the replay checks catch it
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { gunzipSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const CART = "docs/demo-joust.wasm";
const MUSIC = "joust_sfx.sndh";
const W = 400, RW = 800, RH = 280; // the physical frame: 320x200 at (40, 40), x doubled
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (broke && broke !== "joy" && broke !== "clock") throw new Error("--break joy | clock");
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/joust";
const BREAK_AT = 500;

const fixture = JSON.parse(gunzipSync(await readFile("apps/joust_fixture.json.gz")).toString());

async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const env0 = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
    const rom = (await WebAssembly.instantiate(romBytes, { env: env0 })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(CART);
    const env = {
        ...env0,
        hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop, hwRamSize: machine.hwRamSize,
        hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
        hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
        hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
        hwRomRamFree: machine.hwRomRamFree, ...rom,
    };
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

// ---------------------------------------------------------------- the replays
function sfxOf(demo) {
    const n = demo.joustTestVal(7);
    let s = "";
    for (let i = 0; i < n; i++) {
        const v = demo.joustTestVal(8 + i);
        if (v !== 16) s += v.toString(16); // 16 = the siren, not a Dosound script
    }
    demo.joustTestSfxClear();
    return s;
}

async function replay(name) {
    const run = fixture.runs[name];
    const { demo } = await boot();
    const joy = Buffer.from(run.joy, "base64");
    const sfx = run.sfx.split(",");
    const checks = new Map(run.checks.map(([f, h, t]) => [f, [h >>> 0, t]]));
    const sorted = (s) => [...s].sort().join("");
    demo.joustTestReset(fixture.seed);
    for (const [at, code] of run.keys) demo.joustTestKey(Math.floor(at / 2 ** 32), at >>> 0, code);
    demo.joustTestFrame(0, 0); // power-on, the title, the new-game screen: to frame 0's $0018
    sfxOf(demo);
    let bad = 0, vblOk = 0, sfxOk = 0, hashOk = 0;
    const fail = (msg) => { if (bad++ < 5) console.log(`  FAIL ${name}: ${msg}`); };
    const check = (f) => {
        const c = checks.get(f);
        if (!c) return;
        const h = demo.joustTestHash() >>> 0;
        const t = (demo.joustTestVal(1) >>> 0) * 2 ** 32 + (demo.joustTestVal(0) >>> 0);
        if (h === c[0] && t === c[1]) hashOk++;
        else fail(`frame ${f} start: RAM+screen ${h.toString(16)} t=${t}, the harness ${c[0].toString(16)} t=${c[1]}`);
    };
    check(0);
    const t0 = performance.now();
    for (let f = 0; f < run.frames; f++) {
        let p1 = joy[2 * f], p2 = joy[2 * f + 1];
        if (broke === "joy" && f === BREAK_AT) p1 ^= 0x80;
        if (broke === "clock" && f === BREAK_AT) demo.joustTestNudge(4);
        const v = demo.joustTestFrame(p1, p2);
        if (v === Number(run.vbls[f])) vblOk++;
        else fail(`frame ${f} took ${v} VBLs, the harness ${run.vbls[f]}`);
        const s = sfxOf(demo);
        if (sorted(s) === sorted(sfx[f])) sfxOk++;
        else fail(`frame ${f} started SFX [${s}], the harness [${sfx[f]}]`);
        check(f + 1);
    }
    const ms = (performance.now() - t0) / run.frames;
    const oob = demo.joustTestVal(5), cerr = demo.joustTestVal(6);
    if (oob) fail(`${oob} accesses outside the program, the screen and the RAM below it`);
    if (cerr) fail(`${cerr} cycle-table errors`);
    console.log(`  ${name}: ${run.frames} frames from power-on; VBLs per frame ${vblOk}/${run.frames}, ` +
        `SFX ${sfxOk}/${run.frames}, RAM+screen+clock ${hashOk}/${checks.size} checks identical to the harness ` +
        `(${ms.toFixed(3)} ms/frame)`);
    return bad;
}

// ---------------------------------------------------------------- the live path
function visible(memory, machine) {
    const pfb = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), RW * RH);
    const out = new Uint32Array(320 * 200);
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) out[y * 320 + x] = pfb[(40 + y) * RW + 80 + 2 * x];
    return out;
}
async function shot(px, path) {
    const rgb = Buffer.alloc(320 * 200 * 3);
    for (let i = 0; i < px.length; i++) { rgb[3 * i] = px[i] & 255; rgb[3 * i + 1] = (px[i] >> 8) & 255; rgb[3 * i + 2] = (px[i] >> 16) & 255; }
    await writeFile(path, Buffer.concat([Buffer.from("P6\n320 200\n255\n"), rgb]));
}

async function live() {
    const { memory, machine, demo } = await boot();
    const songs = [];
    const dec = new TextDecoder();
    const step = (n, dt) => {
        for (let i = 0; i < n; i++) {
            machine.hwClear();
            demo.frame(dt);
            if (demo.pollSongRequest()) {
                songs.push([dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())), demo.songTune()]);
            }
            machine.hwRenderPlane(0);
        }
    };
    const errors = [];
    step(150, 20); // 3 s of title
    const title = visible(memory, machine);
    await shot(title, `${outdir}/title.ppm`);
    const colours = new Set(title);
    if (colours.size < 6) errors.push(`the title shows ${colours.size} colours`);
    const tdiff = stDiff(memory, demo, title);
    if (tdiff) errors.push(`the title plane is not the ST screen: ${tdiff}`);
    if (!songs.some(([n, t]) => n === MUSIC && t === 15)) errors.push(`no title tune (${MUSIC} subtune 15): ${JSON.stringify(songs)}`);
    if (demo.joustTestVal(4) !== 0) errors.push(`mode ${demo.joustTestVal(4)} on the title`);
    demo.key(0x31); // '1'
    demo.keyUp(0x31);
    step(150, 20);
    if (demo.joustTestVal(4) !== 1) errors.push(`'1' did not start a game (mode ${demo.joustTestVal(4)})`);
    const game = visible(memory, machine);
    await shot(game, `${outdir}/game.ppm`);
    // the plane is the ST screen through the colour registers, pixel for pixel
    const diff = stDiff(memory, demo, game);
    if (diff) errors.push(`the plane is not the ST screen: ${diff}`);
    // a 60 Hz host: the ST's clock still runs at 50.053 Hz
    const v0 = demo.joustTestVal(2);
    step(600, 1000 / 60);
    const dv = demo.joustTestVal(2) - v0;
    if (Math.abs(dv - 500) > 8) errors.push(`10 s at 60 Hz ran ${dv} ST VBLs, not ~500`);
    // flapping right for 3 s: the game's own sound effects are requested
    const n0 = songs.length;
    input(demo, 3);
    for (let i = 0; i < 150; i++) {
        if (i % 6 === 0) demo.key(13); else if (i % 6 === 3) demo.keyUp(13);
        step(1, 20);
    }
    demo.inputRelease(3);
    const sfx = songs.slice(n0).filter(([n]) => n === MUSIC);
    if (sfx.length < 3) errors.push(`only ${sfx.length} SFX requests while flapping`);
    // P pauses (the frame stops; the machine polls the keyboard across host
    // frames), any key resumes, R restarts to the title, Escape leaves
    demo.key(0x70);
    step(10, 20);
    const paused = visible(memory, machine), pv = demo.joustTestVal(2);
    step(100, 20);
    if (demo.joustTestVal(4) !== 2) errors.push(`P did not pause (mode ${demo.joustTestVal(4)})`);
    if (visible(memory, machine).some((v, i) => v !== paused[i])) errors.push("the screen moved while paused");
    if (demo.joustTestVal(2) - pv < 95) errors.push("the ST's clock stopped while paused (its pause is a busy loop)");
    demo.key(0x20);
    demo.keyUp(0x20);
    step(10, 20);
    if (demo.joustTestVal(4) !== 1) errors.push(`a key did not resume (mode ${demo.joustTestVal(4)})`);
    demo.key(0x72);
    step(20, 20);
    if (demo.joustTestVal(4) !== 0) errors.push(`R did not restart to the title (mode ${demo.joustTestVal(4)})`);
    demo.key(0xe012);
    step(1, 20);
    if (demo.pollCartRequest() !== -1) errors.push("Escape did not leave for the menu");
    if (songs.at(-1)?.[0] !== "none") errors.push(`Escape did not stop the sound: ${JSON.stringify(songs.at(-1))}`);
    console.log(`  live: title (${colours.size} colours, tune requested), '1' starts the game, ` +
        `${dv} ST VBLs in 10 s at 60 Hz, ${sfx.length} SFX requests in 3 s of flapping ` +
        `(subtunes ${[...new Set(sfx.map(([, t]) => t))].sort((a, b) => a - b).join(",")})`);
    return errors;
}
function input(demo, dir) { demo.input(dir); }

// The ST screen in the cart's memory, decoded here (4 interleaved planes, 16
// pixels a group, 3-bit guns x 255/7), against the plane as displayed.
function stDiff(memory, demo, shown) {
    const scr = new Uint8Array(memory.buffer, demo.joustTestScreenPtr(), 32000);
    const pal = new Uint16Array(memory.buffer, demo.joustTestPalPtr(), 16);
    const gun = (n) => Math.floor((n & 7) * 255 / 7);
    let bad = 0;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const g = y * 160 + (x >> 4) * 8, b = 15 - (x & 15);
        let c = 0;
        for (let p = 0; p < 4; p++) c |= ((((scr[g + 2 * p] << 8) | scr[g + 2 * p + 1]) >> b) & 1) << p;
        const w = pal[c];
        const want = (gun(w >> 8) | gun(w >> 4) << 8 | gun(w) << 16 | 0xff000000) >>> 0;
        if (shown[y * 320 + x] >>> 0 !== want) bad++;
    }
    return bad ? `${bad} pixels differ` : null;
}

// ---------------------------------------------------------------- the sound
async function audioMachine() {
    const AUDIO_PAGES = 48; // AUDIO_PAGES in machine/sdk
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    return { memory, m, audio };
}

/// TOS's Dosound interpreter, one 50 Hz tick (the reference model's core.py).
function dosoundTick(s, text) {
    if (!s.ptr) return;
    if (s.delay && --s.delay) return;
    let p = s.ptr;
    for (let i = 0; i < 512; i++) {
        const c = text[p];
        if (c < 0x80) { s.psg[c & 15] = text[p + 1]; p += 2; }
        else if (c === 0x80) { s.temp = text[p + 1]; p += 2; }
        else if (c === 0x81) {
            s.psg[text[p + 1] & 15] = s.temp;
            s.temp = (s.temp + text[p + 2]) & 0xff;
            if (s.temp !== text[p + 3]) { s.ptr = p; return; }
            p += 4;
        } else {
            const n = text[p + 1];
            p += 2;
            s.ptr = n ? p : 0;
            if (n) s.delay = n;
            return;
        }
    }
}

async function sound() {
    const prg = await readFile("apps/zig/assets/screens/joust/JOUST.PRG");
    const text = prg.subarray(0x1c);
    const bytes = new Uint8Array(await readFile(`docs/music/${MUSIC}`));
    const errors = [];
    let ticks = 0;
    for (let n = 0; n < 17; n++) {
        const { memory, m, audio } = await audioMachine();
        audio.audioInit();
        new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
        if (!audio.audioLoadSndh(bytes.length)) { errors.push("audioLoadSndh refused joust_sfx.sndh"); break; }
        audio.audioSndhPlay(n + 1);
        const regs = () => [...new Uint8Array(memory.buffer, m.audioYmRegsPtr(), 14)];
        if (n === 16) { // the siren: 16 sweeps of 129 steps, 2976 cycles a step, the last at volume 0: 718 ms heard
            let lastOn = -1, first = -1;
            for (let b = 0; b < 60; b++) {
                audio.audioRender(882);
                const r = regs();
                if (b === 0) first = r[8];
                if (r[8] !== 0) lastOn = b;
            }
            if (first !== 15 || lastOn < 34 || lastOn > 36)
                errors.push(`the siren: volume ${first} at 20 ms, last non-zero at ${(lastOn + 1) * 20} ms (want ~718)`);
            continue;
        }
        const s = { ptr: text.readUInt32BE(0x17e2 + 4 * n), delay: 0, temp: 0, psg: regs() };
        let bad = null;
        for (let b = 0; b < 400 && !bad; b++) {
            audio.audioRender(882); // 20 ms: one Dosound tick, every 6th call of the 300 Hz play
            dosoundTick(s, text);
            ticks++;
            const got = regs();
            if (got.some((v, i) => v !== s.psg[i])) bad = `tick ${b}: YM ${got.join(",")} TOS ${s.psg.slice(0, 14).join(",")}`;
        }
        if (bad) errors.push(`script ${n}: ${bad}`);
        if (audio.audioSndhStuckPc()) errors.push(`script ${n}: stuck at PC ${audio.audioSndhStuckPc()}`);
    }
    console.log(`  sound: 16 Dosound scripts, ${ticks} ticks of YM registers identical to TOS's interpreter; the siren sweeps and ends silent`);
    return errors;
}

await mkdir(outdir, { recursive: true });
let bad = 0;
for (const name of Object.keys(fixture.runs)) bad += await replay(name);
if (broke) {
    console.log(bad ? `joust: PASS (--break ${broke} caught: ${bad} failures)` : `joust: FAILED -- --break ${broke} was not caught`);
    process.exit(bad ? 0 : 1);
}
const errors = [...await live(), ...await sound()];
if (bad) errors.unshift(`${bad} replay checks failed`);
console.log(errors.length ? `joust: FAILED -- ${errors.join("; ")}` : "joust: all pass");
process.exit(errors.length ? 1 : 0);
