// SKYSTRIKE ZIG-mode harness, the sound effects (apps/skystrike_zig.mjs drives).
//   events  the same flight in both modes: FIRE, an enemy hit, a bomb on the
//           ground, a crash. ZIG sends ZPLAY with that event's sample (gun
//           looped, airburst, ground explosion or splash, crash); ORIGINAL
//           sends no ZIG command at all
//   chip    skystrike.sndh on the sealed audio machine: each ZPLAY starts a
//           Paula channel on exactly that sample's bytes
//           (tools/skystrike/make_sfx.py's sfx/*.raw), while subtune 1's music
//           goes on moving the YM as before (a Maestro digi takes it over);
//           the ZIG run's commands start the event samples in order, the
//           ORIGINAL run's start no channel
// --break sound: the sample table swapped (gun <-> airburst).
import { readFile } from "node:fs/promises";
import { onRunway, takeOff, CLEAR_SENT } from "./skystrike_zig_session.mjs";
import { ENEMY } from "./skystrike_session.mjs";

const MUSIC = "skystrike.sndh", RESIDENT = 0x8000, ZPLAY = 9, ZSTOP = 10;
const FIRE = 0x80, LEFT = 4, E = { sx: 0, al: 2, x: 4, y: 6 };
const src = await readFile("apps/zig/scenes/skystrike/zig_sound.zig", "utf8");
const NAMES = src.match(/Sample = enum\(u8\) \{([^}]*)\}/)[1].split(",").map((x) => x.trim()).filter(Boolean);
const id = (name) => NAMES.indexOf(name);

/// The flight's events; returns the commands each sent.
async function events(zig) {
    const s = await onRunway(zig);
    takeOff(s, 40);
    const got = {}, grab = (k) => { got[k] = s.sent(); s.poke(CLEAR_SENT, 0); };
    s.poke(CLEAR_SENT, 0);
    s.stick(FIRE); s.pass(); s.stick(0); s.pass();
    grab("gun");
    for (let shots = 0; shots < 40 && s.v("ammo") > 0; shots++) {
        const sc = s.v("scre");
        s.poke(ENEMY + E.sx, s.v("sx")); s.poke(ENEMY + E.al, s.v("al"));
        s.poke(ENEMY + E.x, s.v("x") - 48); s.poke(ENEMY + E.y, s.v("y"));
        s.stick(FIRE); s.pass(); s.stick(0); s.pass();
        if (s.v("scre") !== sc) break;
    }
    grab("bang");
    s.stick(FIRE | LEFT); s.pass(); s.stick(0);
    for (let p = 0; p < 40 && s.v("bf"); p++) s.pass();
    grab("bomb");
    s.set("al", -1);
    s.run(8);
    grab("crash");
    return got;
}

const zplays = (list) => list.filter((d) => d >> 8 === ZPLAY).map((d) => d & 0xff);

function cartChecks(z, o, errors) {
    const want = { gun: [id("gun") | 0x80], bang: [id("bang")], bomb: [id("bomb"), id("splash")], crash: [id("crash")] };
    for (const [k, ids] of Object.entries(want))
        if (!zplays(z[k]).some((x) => ids.includes(x))) errors.push(`sound: ZIG's ${k} sent no ZPLAY ${ids.map((x) => x.toString(16))}: ${z[k].map((x) => x.toString(16))}`);
    const zig = Object.values(o).flat().filter((d) => d >> 8 === ZPLAY || d >> 8 === ZSTOP);
    if (zig.length) errors.push(`sound: ORIGINAL sent ZIG commands ${zig.map((x) => x.toString(16))}`);
}

async function audioMachine(bytes, triggers) {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    env.machinePaulaTrigger = (ch, at, len, ls, ll, pan) => { triggers.push({ ch, bytes: new Uint8Array(memory.buffer, at, len).slice(), loop: ll > 0 }); m.machinePaulaTrigger(ch, at, len, ls, ll, pan); };
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) throw new Error(`audioLoadSndh refused ${MUSIC}`);
    const vols = () => [...new Uint8Array(memory.buffer, m.audioYmRegsPtr(), 16)].slice(8, 11).join();
    const changes = (ms) => { let n = 0, last = vols(); for (let t = 0; t < ms * 44.1; t += 64) { audio.audioRender(64); const v = vols(); if (v !== last) n++; last = v; } return n; };
    return { audio, changes, call: (d) => audio.audioSndhCall(RESIDENT | d) };
}

const which = (raw, bytes) => raw.findIndex((r) => r.length === bytes.length && r.every((b, i) => b === bytes[i]));

/// Every sample on the chip, under the music.
async function chipChecks(bytes, raw, broke, errors) {
    const base = await audioMachine(bytes, []);
    base.audio.audioSndhPlay(1);
    base.changes(200);
    const music = base.changes(1000);
    const notes = [];
    for (let k = 0; k < NAMES.length; k++) {
        const trig = [];
        const a = await audioMachine(bytes, trig);
        a.audio.audioSndhPlay(1);
        a.changes(200);
        a.call(ZPLAY << 8 | k | (k === 0 ? 0x80 : 0));
        const ch = a.changes(1000);
        const t = trig.find((x) => x.ch === 0);
        const expect = broke === "sound" && k < 2 ? 1 - k : k;
        if (!t || which(raw, t.bytes) !== expect || t.loop !== (k === 0)) errors.push(`sound: ZPLAY ${k} started ${t ? `${NAMES[which(raw, t.bytes)] ?? "unknown bytes"}${t.loop ? " looped" : ""}` : "no channel"}, not ${NAMES[expect]}`);
        if (ch < music / 2 || ch > music * 2) errors.push(`sound: under ${NAMES[k]} the music moved the YM ${ch} times a second, ${music} without it`);
        notes.push(`${NAMES[k]} ${t?.bytes.length ?? 0} B`);
    }
    return `${notes.join(", ")}; the music ${music} YM changes/s with or without them`;
}

/// The runs' own commands on the chip.
async function replay(bytes, raw, list) {
    const trig = [];
    const a = await audioMachine(bytes, trig);
    a.audio.audioSndhPlay(4);
    a.changes(20);
    for (const d of list) { a.call(d); a.changes(20); }
    return trig.filter((t) => t.ch === 0).map((t) => NAMES[which(raw, t.bytes)] ?? "?");
}

export async function sound(broke) {
    const errors = [];
    const bytes = new Uint8Array(await readFile(`docs/music/${MUSIC}`));
    const raw = await Promise.all(NAMES.map(async (n) => new Uint8Array(await readFile(`apps/zig/assets/screens/skystrike/sfx/${n}.raw`))));
    const z = await events(true), o = await events(false);
    cartChecks(z, o, errors);
    const chip = await chipChecks(bytes, raw, broke, errors);
    const zRun = await replay(bytes, raw, Object.values(z).flat());
    const oRun = await replay(bytes, raw, Object.values(o).flat());
    const order = ["gun", "bang", zRun.includes("splash") ? "splash" : "bomb", "crash"];
    let at = 0;
    for (const n of zRun) if (n === order[at]) at++;
    if (at < order.length) errors.push(`sound: the ZIG run's commands started ${zRun.join(" ")} (want ${order.join(", ")} in order)`);
    if (oRun.length) errors.push(`sound: the ORIGINAL run's commands started Paula channels: ${oRun.join(" ")}`);
    console.log(`  sound: ZIG events -> ${zRun.join(" ")}; ORIGINAL -> no channel; ${chip}`);
    return errors;
}
