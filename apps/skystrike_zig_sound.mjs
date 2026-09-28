// SKYSTRIKE ZIG-mode harness, the sound effects (apps/skystrike_zig.mjs drives).
//   events  the same flight in both modes: FIRE, an enemy hit, a bomb on the
//           ground, a crash. The host's view of ZIG's effect commands
//           (pollSfx, polled every frame as docs/sealed-loader.js does): each
//           event plays its sample (gun looped, airburst, ground explosion or
//           splash, crash), exactly that sample's bytes (sfx/*.raw) at its STE
//           rate; ORIGINAL sends none, and ZIG sends nothing to skystrike.sndh
//   engine  ZIG's YM writes leave the engine note as ORIGINAL's commands set
//           it (noise 31 - throttle, envelope 10, its period), and none were
//           refused
//   chip    the ZIG run's commands, frame by frame, on the sealed audio machine
//           over "The Hawk's Claw": each effect starts on the MOD's lent
//           channel on exactly its bytes, in the events' order; the other
//           channels go on playing the song; each one-shot gives the channel
//           back at its end (the song writes to it again); the gun loop is
//           let go by the engine's own SAMSTOP (a loop-only stop)
//   mix     the levels at the gain the cart requested for the flight: each
//           effect clearly over the music bed, the engine under the effects
//           (apps/skystrike_zig_mix.mjs, which also holds the engine check)
// --break sound: the sample table swapped (gun <-> airburst); mix: the
// flight's music gain set to 1.0.
import { readFile } from "node:fs/promises";
import { zsession, takeOff, Z } from "./skystrike_zig_session.mjs";
import { ENEMY, toPlay } from "./skystrike_session.mjs";
import { engineCheck, mix } from "./skystrike_zig_mix.mjs";

const FIRE = 0x80, LEFT = 4, E = { sx: 0, al: 2, x: 4, y: 6 };
const PLAY = 1, STOP = 2, YM = 3, GAIN = 4, SR = 44100, PER_FRAME = SR / 50;
const src = await readFile("apps/zig/scenes/skystrike/zig_sound.zig", "utf8");
const NAMES = src.match(/Sample = enum\(u8\) \{([^}]*)\}/)[1].split(",").map((x) => x.trim()).filter(Boolean);
const fxSrc = await readFile("apps/zig/scenes/skystrike/zig_fx.zig", "utf8");
const RATE = Object.fromEntries([...fxSrc.matchAll(/\.(\w+) = \.\{ \.pcm = @embedFile\(DIR \+\+ "\w+\.raw"\), \.rate = (HI|LO) \}/g)].map((m) => [m[1], m[2] === "HI" ? 12517 : 6258]));

/// The frame's effect commands, as the host drains them.
function drain(s, frame, out) {
    const n = s.demo.pollSfx();
    const dv = new DataView(s.memory.buffer, s.demo.sfxEntriesPtr(), n * 16);
    for (let i = 0; i < n; i++) {
        const o = i * 16, op = dv.getUint8(o), c = { frame, op, a: dv.getUint8(o + 1), b: dv.getUint8(o + 2) };
        if (op === PLAY) {
            c.bytes = new Uint8Array(s.memory.buffer, dv.getUint32(o + 4, true), dv.getUint32(o + 8, true)).slice();
            c.rate = dv.getUint32(o + 12, true);
        }
        if (op === GAIN) c.q16 = dv.getUint32(o + 8, true);
        out.push(c);
    }
}

/// The flight's events; returns each event's commands and the whole run's,
/// and the gain the cart requested for the flight's MOD (the last one queued
/// on the way to the runway).
async function events(zig, broke) {
    const s = await zsession(zig);
    if (broke === "mix") s.poke(Z.gainPlay, 1000);
    await toPlay(s);
    if (!s.runTo("l50", 2000)) throw new Error(`not in play (label ${s.label()})`);
    const before = [];
    drain(s, -1, before);
    const gain = before.findLast((c) => c.op === GAIN)?.q16 ?? null;
    const refused0 = s.z("fxRefused");
    const all = [];
    let frame = 0;
    const each = () => drain(s, frame++, all);
    takeOff(s, 40, each);
    // the engine note: throttle 8, the game's own commands logged
    s.poke(12, 0);
    let from = all.length;
    s.press(56);
    for (let p = 0; p < 6; p++) s.pass(each);
    const engine = { ym: all.filter((c) => c.op === YM), pre: before.filter((c) => c.op === YM), log: s.log(), upTo: all.length };
    const got = {}, sent = {};
    from = all.length;
    const grab = (k) => { got[k] = all.slice(from); from = all.length; sent[k] = s.sent(); s.poke(13, 0); };
    s.poke(13, 0);
    s.stick(FIRE); s.pass(each); s.stick(0); s.pass(each);
    grab("gun");
    // the gun loop goes on until the engine routine's SAMSTOP (nso runs out)
    for (let p = 0; p < 20 && !all.slice(from).some((c) => c.op === STOP && c.a === 1); p++) s.pass(each);
    grab("gunstop");
    for (let shots = 0; shots < 40 && s.v("ammo") > 0; shots++) {
        const sc = s.v("scre");
        s.poke(ENEMY + E.sx, s.v("sx")); s.poke(ENEMY + E.al, s.v("al"));
        s.poke(ENEMY + E.x, s.v("x") - 48); s.poke(ENEMY + E.y, s.v("y"));
        s.stick(FIRE); s.pass(each); s.stick(0); s.pass(each);
        if (s.v("scre") !== sc) break;
    }
    grab("bang");
    s.stick(FIRE | LEFT); s.pass(each); s.stick(0);
    for (let p = 0; p < 40 && s.v("bf"); p++) s.pass(each);
    grab("bomb");
    s.set("al", -1);
    s.run(8, each);
    grab("crash");
    return { got, sent, all, engine, gain, voices: s.z("psgVoices"), refused: s.z("fxRefused") - refused0 };
}

const which = (raw, bytes) => raw.findIndex((r) => r.length === bytes.length && r.every((b, i) => b === bytes[i]));

function cartChecks(z, o, raw, broke, errors) {
    const id = (n) => NAMES.indexOf(broke === "sound" ? { gun: "bang", bang: "gun" }[n] ?? n : n);
    const want = { gun: [["gun", true]], bang: [["bang", false]], bomb: [["bomb", false], ["splash", false]], crash: [["crash", false]] };
    for (const [k, alts] of Object.entries(want)) {
        const plays = z.got[k].filter((c) => c.op === PLAY);
        const ok = plays.some((c) => alts.some(([n, loop]) => which(raw, c.bytes) === id(n) && c.rate === RATE[n] && !!c.a === loop));
        if (!ok) errors.push(`sound: ZIG's ${k} played ${plays.map((c) => `${NAMES[which(raw, c.bytes)] ?? `${c.bytes.length} unknown bytes`}@${c.rate}${c.a ? " looped" : ""}`).join(", ") || "nothing"}`);
    }
    if (o.all.length) errors.push(`sound: ORIGINAL sent ${o.all.length} effect / YM commands`);
    const toSndh = Object.values(z.sent).flat();
    if (toSndh.length) errors.push(`sound: ZIG sent ${toSndh.length} commands to skystrike.sndh (${toSndh.slice(0, 4).map((d) => d.toString(16))})`);
    if (!Object.values(o.sent).flat().length) errors.push("sound: ORIGINAL sent nothing to skystrike.sndh");
    if (z.refused) errors.push(`sound: ${z.refused} of ZIG's effect / YM commands were refused by the queue`);
}

async function audioMachine(log) {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory }, t = { frames: 0 };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    for (const n of ["machinePaulaSetStep", "machinePaulaSetVolume"]) env[n] = (ch, v) => { log.push({ ch, at: t.frames }); m[n](ch, v); };
    env.machinePaulaTrigger = (ch, at, len, ls, ll, pan) => {
        log.push({ ch, at: t.frames, bytes: new Uint8Array(memory.buffer, at, len).slice(), loop: ll > 0 });
        m.machinePaulaTrigger(ch, at, len, ls, ll, pan);
    };
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    const mod = new Uint8Array(await readFile("docs/music/skystrike_the_hawks_claw.mod"));
    new Uint8Array(memory.buffer, a.audioSongPtr(), mod.length).set(mod);
    if (!a.audioLoadMod(mod.length)) throw new Error("audioLoadMod refused the flight's MOD");
    a.audioModPlay();
    const render = (n) => { for (let i = 0; i < n; i += 128) { a.audioRender(128); t.frames += 128; } };
    const apply = (c) => {
        if (c.op === YM) return a.audioSfxYm(c.a, c.b);
        if (c.op === STOP) return a.audioSfxStop(c.a);
        if (c.op === GAIN) return a.audioModGain(c.q16);
        new Uint8Array(memory.buffer, a.audioSfxBufPtr(), c.bytes.length).set(c.bytes);
        return a.audioSfxPlay(c.bytes.length, c.rate, c.a);
    };
    return { a, t, render, apply };
}

/// The ZIG run's commands on the chip, over the flight's MOD.
async function chip(z, raw, errors) {
    const log = [], x = await audioMachine(log);
    x.render(SR / 2);
    const started = [], releases = [];
    let frame = 0, gunStopped = false;
    for (const c of z.all) {
        for (; frame < c.frame; frame++) x.render(PER_FRAME);
        const held = x.a.audioSfxChannel();
        x.apply(c);
        if (c.op === PLAY) {
            const ch = x.a.audioSfxChannel(), t = log.findLast((e) => e.bytes && e.ch === ch);
            started.push({ name: NAMES[which(raw, t?.bytes ?? [])] ?? "?", ch, at: x.t.frames, same: t && which(raw, t.bytes) === which(raw, c.bytes) });
        }
        if (c.op === STOP && c.a === 1 && held >= 0 && started.at(-1)?.name === "gun" && x.a.audioSfxChannel() === -1) gunStopped = true;
    }
    x.render(SR * 2);
    const ch = started[0]?.ch ?? -1;
    for (let i = 0; i < started.length; i++) {
        const s = started[i], next = started[i + 1]?.at ?? x.t.frames;
        if (!s.same) errors.push(`sound: the chip's channel ${s.ch} did not start on ${s.name}'s bytes`);
        const others = [0, 1, 2, 3].filter((c) => c !== s.ch).some((c) => log.some((e) => e.ch === c && e.at > s.at && e.at < next));
        if (!others && next - s.at > SR / 4) errors.push(`sound: the song stopped under ${s.name}`);
        if (s.name !== "gun") {
            const end = s.at + Math.ceil(raw[NAMES.indexOf(s.name)].length * SR / RATE[s.name]);
            if (end + SR / 10 < next) releases.push(log.some((e) => e.ch === s.ch && !e.bytes?.length && e.at > end && e.at < next) ? s.name : `!${s.name}`);
        }
    }
    const order = ["gun", "bang", started.some((s) => s.name === "splash") ? "splash" : "bomb", "crash"];
    let at = 0;
    for (const s of started) if (s.name === order[at]) at++;
    if (at < order.length) errors.push(`sound: the chip started ${started.map((s) => s.name).join(" ")} (want ${order.join(", ")} in order)`);
    if (!gunStopped) errors.push("sound: the engine's SAMSTOP never let the gun loop go");
    const kept = releases.filter((r) => r.startsWith("!"));
    if (kept.length) errors.push(`sound: after ${kept.map((r) => r.slice(1)).join(", ")} the song never took channel ${ch} back`);
    if (!releases.length) errors.push("sound: no effect ended before the next: the release went unchecked");
    return `the chip: ${started.map((s) => s.name).join(" ")} on channel ${ch}, the song back on it after ${releases.join(", ")}, the gun loop let go by SAMSTOP`;
}

export async function sound(broke) {
    const errors = [];
    const raw = await Promise.all(NAMES.map(async (n) => new Uint8Array(await readFile(`apps/zig/assets/screens/skystrike/sfx/${n}.raw`))));
    const z = await events(true, broke), o = await events(false);
    cartChecks(z, o, raw, broke, errors);
    const eng = engineCheck(z, o, errors);
    const c = await chip(z, raw, errors);
    const plays = z.all.filter((x) => x.op === PLAY).map((x) => NAMES[which(raw, x.bytes)]);
    if (o.gain !== null) errors.push(`mix: ORIGINAL requested a MOD gain (${o.gain})`);
    let m = "the mix: unchecked";
    if (z.gain === null) errors.push("mix: ZIG requested no MOD gain for the flight");
    else {
        const fx = [...new Map(z.all.filter((x) => x.op === PLAY).map((x) => [NAMES[which(raw, x.bytes)], x])).entries()]
            .map(([name, x]) => ({ name, bytes: x.bytes, rate: x.rate, loop: !!x.a }));
        const ym = [...z.engine.pre, ...z.engine.ym].map((x) => [x.a, x.b]);
        m = await mix(fx, ym, z.gain, errors);
    }
    console.log(`  sound: ZIG events -> ${plays.join(" ")}; ORIGINAL -> none; ${eng}; ${c}; ${m}`);
    return errors;
}
