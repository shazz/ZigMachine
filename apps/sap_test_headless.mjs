// Headless SAP TEST driver: boots the sap_test cart (apps/zig/scenes/sap_test.zig) as
// docs/ loads it, presses its keys, and follows every song request it makes into the
// browser's audio path, as docs/sealed-loader.js + audio-worklet-sealed.js do.
//
//   node apps/sap_test_headless.mjs [--break tune|silent]
//
// Checked:
//   1. the screen draws: the list and the status are on the plane, and the credits
//      scroller moves from frame to frame;
//   2. the cart requests Warhawk.sap song 1 when it starts, then for each key the RIGHT
//      file and song number: Down x4 + Fire = BMX_Simulator.sap 1, Right = 2, Right = 3,
//      Right wraps to 1, Left wraps to 3; Up + Right on one-song Ninja requests nothing,
//      Fire = Ninja.sap 1; key 3 = Barbarian.sap 1;
//   3. every requested file is in docs/music/, loads in docs/demo-audio.wasm's SAP
//      player (mode 5, status 0), has as many songs as the screen says, and the song
//      asked for plays something (not silence) on docs/machine-audio.wasm's POKEY;
//   4. Escape and Back both leave to the menu.
//
// --break tune:   the request's song number is read as 0 (what zg.requestSong would
//                 send: the file's DEFSONG), so the song checks must fail.
// --break silent: the POKEY's render is a no-op, so the not-silence check must fail.
import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { boot } from "./naos_nitrowave_boot.mjs"; // the generic headless boot (machine + ROM + cart)

const BREAK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
if (BREAK !== null && !["tune", "silent"].includes(BREAK)) { console.error(`sap_test: unknown --break ${BREAK}`); process.exit(1); }

const AUDIO_PAGES = 48; // machine/sdk/audio.zig
const SR = 44100, BLOCK = 882;
const SONGS = { "Warhawk.sap": 1, "Gauntlet.sap": 1, "Barbarian.sap": 1, "Ninja.sap": 1, "BMX_Simulator.sap": 3 };
const K_ESC = 0xE012;
const errors = [];

const S = await boot("docs/demo-sap_test.wasm");
const W = S.machine.hwPhysWidth(), H = S.machine.hwPhysHeight();
const step = () => { S.machine.hwClear(); S.demo.frame(20); S.machine.hwRenderPlane(0); };
const request = () => {
    if (!S.demo.pollSongRequest()) return null;
    const name = new TextDecoder().decode(new Uint8Array(S.memory.buffer, S.demo.songNamePtr(), S.demo.songNameLen()));
    return { name, tune: BREAK === "tune" ? 0 : S.demo.songTune() };
};
const rows = (y0, y1) => {
    const b = new Uint8Array(S.memory.buffer, S.machine.hwPhysicalPtr(), W * H * 4);
    return b.slice(y0 * W * 4, y1 * W * 4);
};
const differs = (a, b) => a.some((v, i) => v !== b[i]);
const colours = (px) => { const s = new Set(); for (let i = 0; i < px.length; i += 4) s.add((px[i] << 16) | (px[i + 1] << 8) | px[i + 2]); return s.size; };

// --- 1 + 2: the start, then each key and the request it must make ----------
const asked = [];
function expect(label, want) {
    step();
    const got = request();
    if (got) asked.push(got);
    const show = (r) => (r ? `${r.name} song ${r.tune}` : "no request");
    if (show(got) !== show(want)) errors.push(`${label}: ${show(got)}, want ${show(want)}`);
}
expect("start", { name: "Warhawk.sap", tune: 1 });
for (let i = 0; i < 30; i++) step();
const Y0 = 40; // the 200 visible lines start at physical row 40
const list = rows(Y0 + 30, Y0 + 140), scrollA = rows(Y0 + 182, Y0 + 200);
step();
if (colours(list) < 4) errors.push(`the tune list draws ${colours(list)} colours, want ink, cursor, composer and background`);
if (!differs(scrollA, rows(Y0 + 182, Y0 + 200))) errors.push("the credits scroller did not move in a frame");

const press = (dir) => S.demo.input(dir);
for (let i = 0; i < 4; i++) { press(1); expect(`Down ${i + 1}`, null); }
press(5); expect("Fire on BMX SIMULATOR", { name: "BMX_Simulator.sap", tune: 1 });
press(3); expect("Right", { name: "BMX_Simulator.sap", tune: 2 });
press(3); expect("Right", { name: "BMX_Simulator.sap", tune: 3 });
press(3); expect("Right past the last song", { name: "BMX_Simulator.sap", tune: 1 });
press(2); expect("Left past the first song", { name: "BMX_Simulator.sap", tune: 3 });
press(0); expect("Up to NINJA", null);
press(3); expect("Right on a one-song tune", null);
press(5); expect("Fire on NINJA", { name: "Ninja.sap", tune: 1 });
S.demo.setShadeMode(2); expect("key 3", { name: "Barbarian.sap", tune: 1 });

// --- 3: each request through the browser's SAP path --------------------------
async function audio() {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    if (BREAK === "silent") env.machineRenderPokey = () => {};
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    return { memory, machine, a };
}
let played = 0;
for (const { name, tune } of asked) {
    const path = `docs/music/${name}`;
    if (!existsSync(path)) { errors.push(`${name}: not in docs/music/, the site would 404`); continue; }
    const bytes = await readFile(path);
    const m = await audio();
    new Uint8Array(m.memory.buffer, m.a.audioSongPtr(), bytes.length).set(bytes);
    if (!m.a.audioLoadSap(bytes.length)) { errors.push(`${name}: refused, status ${m.a.audioSapStatus()}`); continue; }
    m.a.audioSapPlay(tune);
    if (m.a.audioSapSongs() !== SONGS[name]) errors.push(`${name}: ${m.a.audioSapSongs()} songs, the screen shows ${SONGS[name]}`);
    let lo = Infinity, hi = -Infinity;
    for (let done = 0; done < 1.5 * SR; done += BLOCK) {
        m.a.audioRender(BLOCK);
        for (const s of new Float32Array(m.memory.buffer, m.machine.audioLeftPtr(), BLOCK)) { lo = Math.min(lo, s); hi = Math.max(hi, s); }
    }
    if (m.a.audioMode() !== 5 || m.a.audioSapStatus() !== 0) errors.push(`${name} song ${tune}: mode ${m.a.audioMode()}, status ${m.a.audioSapStatus()}`);
    if (hi - lo < 0.01) errors.push(`${name} song ${tune}: silence over 1.5 s (the POKEY's output is unipolar: a level that never moves is silence too)`);
    else played++;
}

// --- 4: the ways out ---------------------------------------------------------
for (const [label, act] of [["Escape", (d) => d.key(K_ESC)], ["Back", (d) => d.input(6)]]) {
    const K = await boot("docs/demo-sap_test.wasm");
    for (let i = 0; i < 5; i++) { K.machine.hwClear(); K.demo.frame(20); }
    if (K.demo.pollCartRequest() !== 0) errors.push(`${label}: a cart request before any key`);
    act(K.demo);
    if (K.demo.pollCartRequest() !== -1) errors.push(`${label} does not leave to the menu`);
}

if (BREAK) {
    const caught = errors.length > 0;
    console.log(caught ? `sap_test: PASS (--break ${BREAK} caught: ${errors.length} errors, first: ${errors[0]})`
        : `sap_test: FAIL, --break ${BREAK} was NOT caught`);
    process.exit(caught ? 0 : 1);
}
if (errors.length) {
    console.log("sap_test: WRONG");
    for (const e of errors.slice(0, 12)) console.log("  " + e);
    process.exit(1);
}
console.log(`sap_test: ${asked.length} song requests, each the right file and song; ${played} played on the POKEY (not silence), song counts as shown; list drawn, scroller moving; Escape and Back leave`);
