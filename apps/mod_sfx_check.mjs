// Sound effects OVER a MOD (zg.sfxPlay / sfxStop / ymWrite), on the real audio
// modules (docs/machine-audio.wasm + docs/demo-audio.wasm), and the MOD
// loader's refusal of anything but 4-channel ProTracker.
//   quiet    the effect takes the song's channel with the fewest notes
//            (counted here, per order entry, independently of the player)
//   bytes    that channel starts on exactly the effect's bytes, at full
//            volume (64/64 x 1/1.4) and the channel's own pan; one-shot
//   silent   while it plays, the song writes nothing to that channel, and
//            goes on writing to the other three (the music keeps running)
//   release  at the effect's end (its length at its rate) the channel is the
//            song's again: its next row writes to it
//   loop     a looped effect holds the channel until sfxStop(loop only), a
//            one-shot ignores that stop; a loop with no stop is released
//            after the timeout (4 s); a new song cuts it (channel off)
//   ym       a YM write under the MOD is mixed into the output (not without
//            it); refused while an SNDH plays, and the SNDH -> MOD switch
//            leaves the SNDH silent (it no longer renders over the MOD)
//   refused  no MOD playing: the effect is refused and counted
//   gain     zg.requestModVolume scales the song's channels, never the
//            effect's (apps/mod_sfx_gain.mjs)
//   reject   6CHN / 8CHN / 32CH / an untagged file / a short one: refused,
//            counted, with the reason; M.K. / M!K! / 4CHN / FLT4 load
//   node apps/mod_sfx_check.mjs [--break bytes|release|loop|reject|gain]
//     bytes: the effect compared with another sample; release: the channel
//     expected held after the effect's end; loop: the looped effect expected
//     free before its stop; reject: an 8CHN file expected to load; gain: the
//     effect's channel expected scaled with the song
import { readFile } from "node:fs/promises";
import { gain } from "./mod_sfx_gain.mjs";

const MOD = "docs/music/skystrike_the_hawks_claw.mod";
const SNDH = "docs/music/skystrike.sndh";
const SR = 44100, HEADROOM = 1 / 1.4;
const BREAKS = ["bytes", "release", "loop", "reject", "gain"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);

/// The audio modules, every Paula write per channel spied on.
async function machine() {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const log = [];
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    for (const n of ["machinePaulaTrigger", "machinePaulaSetStep", "machinePaulaSetVolume", "machinePaulaSetPos", "machinePaulaSetActive"])
        env[n] = (ch, ...a) => { log.push({ fn: n.slice(12), ch, a, at: a0.frames }); m[n](ch, ...a); };
    env.machinePaulaTrigger = (ch, at, len, ls, ll, pan) => {
        log.push({ fn: "Trigger", ch, at: a0.frames, bytes: new Uint8Array(memory.buffer, at, len).slice(), loop: ll > 0, pan });
        m.machinePaulaTrigger(ch, at, len, ls, ll, pan);
    };
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    const a0 = { memory, m, a, log, frames: 0 };
    a.audioInit();
    a0.stage = (bytes) => { new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes); return bytes.length; };
    a0.render = (n) => { for (let i = 0; i < n; i += 128) { a.audioRender(128); a0.frames += 128; } };
    a0.out = () => new Float32Array(memory.buffer, m.audioLeftPtr(), 128).slice();
    a0.sfx = (bytes, rate, loop) => {
        const at = a.audioSfxBufPtr();
        if (at) new Uint8Array(memory.buffer, at, bytes.length).set(bytes);
        return a.audioSfxPlay(at ? bytes.length : 0, rate, loop ? 1 : 0);
    };
    return a0;
}

/// The channel with the fewest notes over the song, counted here.
function quietest(mod) {
    const len = mod[950], order = [...mod.subarray(952, 952 + len)];
    const notes = [0, 0, 0, 0];
    for (const p of order) for (let c = 0; c < 256; c++) {
        const o = 1084 + p * 1024 + c * 4;
        if (((mod[o] & 15) << 8 | mod[o + 1]) !== 0) notes[c % 4]++;
    }
    return { ch: notes.indexOf(Math.min(...notes)), notes };
}

async function modAudio(mod) {
    const x = await machine();
    if (!x.a.audioLoadMod(x.stage(mod))) throw new Error(`audioLoadMod refused ${MOD}`);
    x.a.audioModPlay();
    x.render(SR / 2);
    return x;
}

const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
const writesTo = (x, ch, from, to = Infinity) => x.log.filter((e) => e.ch === ch && e.at >= from && e.at < to);

async function oneShot(mod, bang, gun, errors, notes) {
    const x = await modAudio(mod), q = quietest(mod).ch;
    const t0 = x.frames;
    if (!x.sfx(bang, 12517, false)) return errors.push("bytes: audioSfxPlay refused over a playing MOD");
    const ch = x.a.audioSfxChannel();
    if (ch !== q) errors.push(`quiet: the effect took channel ${ch}, the fewest notes are on ${q} (${quietest(mod).notes})`);
    const t = x.log.find((e) => e.fn === "Trigger" && e.at === t0);
    const want = broke === "bytes" ? gun : bang;
    if (!t || t.ch !== ch || !same(t.bytes, want) || t.loop) errors.push(`bytes: the effect's channel did not start on the effect's bytes (${t ? `${t.bytes.length} B on ${t.ch}${t.loop ? " looped" : ""}` : "no trigger"})`);
    const vol = x.log.find((e) => e.fn === "SetVolume" && e.at === t0 && e.ch === ch);
    if (!vol || Math.abs(vol.a[0] - HEADROOM) > 1e-6) errors.push(`bytes: the effect's volume is ${vol?.a[0]}, not 64/64 x 1/1.4`);
    if (t && Math.abs(t.pan - (ch === 0 || ch === 3 ? -0.6 : 0.6)) > 1e-6) errors.push(`bytes: the effect's pan ${t.pan} is not channel ${ch}'s`);
    const len = Math.ceil(bang.length * SR / 12517), end = t0 + len;
    x.render(len - 256);
    if (x.a.audioSfxChannel() !== ch) errors.push("release: the channel went back before the effect's end");
    const during = writesTo(x, ch, t0 + 1, x.frames);
    if (during.length) errors.push(`silent: the song wrote ${during.length} times to the lent channel ${ch} (${during[0].fn})`);
    const others = [0, 1, 2, 3].filter((c) => c !== ch).map((c) => writesTo(x, c, t0 + 1, x.frames).length);
    if (others.some((n) => n === 0)) errors.push(`silent: the music stopped on the other channels (${others} writes)`);
    x.render(SR);
    const held = x.a.audioSfxChannel() !== -1;
    if (broke === "release" ? !held : held) errors.push(`release: channel ${ch} ${held ? "still held" : "free"} ${((x.frames - end) / SR).toFixed(2)} s after the effect's end`);
    const back = writesTo(x, ch, end);
    if (!back.length) errors.push(`release: the song never wrote to channel ${ch} again after the effect`);
    notes.push(`the effect on channel ${ch} (notes per channel ${quietest(mod).notes}), ${bang.length} B = ${(len / SR * 1000).toFixed(0)} ms, the song silent there and busy on the others (${others} writes), back on it ${((back[0]?.at - end) / SR * 1000).toFixed(0)} ms after`);
}

async function looped(mod, gun, errors, notes) {
    const x = await modAudio(mod);
    x.sfx(gun, 12517, true);
    const t = x.log.at(-3);
    if (!t || t.fn !== "Trigger" || !t.loop) errors.push("loop: the looped effect did not start looped");
    x.render(SR * 2);
    const free = x.a.audioSfxChannel() === -1;
    if (broke === "loop" ? !free : free) errors.push("loop: the looped effect gave its channel back with no stop");
    const t1 = x.frames;
    x.a.audioSfxStop(1);
    if (x.a.audioSfxChannel() !== -1) errors.push("loop: sfxStop(loop only) did not stop the looped effect");
    x.render(SR / 2);
    if (!writesTo(x, quietest(mod).ch, t1).length) errors.push("loop: the song did not get the channel back after the stop");
    // a one-shot ignores the loop-only stop; a loop with no stop times out
    x.sfx(gun, 12517, false);
    x.a.audioSfxStop(1);
    if (x.a.audioSfxChannel() === -1) errors.push("loop: sfxStop(loop only) stopped a one-shot");
    x.sfx(gun, 12517, true);
    x.render(SR * 3.9);
    if (x.a.audioSfxChannel() === -1) errors.push("loop: the loop timed out before 4 s");
    x.render(SR * 0.2);
    if (x.a.audioSfxChannel() !== -1) errors.push("loop: the loop with no stop kept its channel past the 4 s timeout");
    // a new song cuts a looping effect: its channel switched off, not left looping
    x.sfx(gun, 12517, true);
    const held = x.a.audioSfxChannel(), t2 = x.frames;
    x.a.audioLoadMod(x.stage(mod));
    x.a.audioModPlay();
    const off = x.log.some((e) => e.fn === "SetActive" && e.ch === held && e.a[0] === 0 && e.at === t2);
    if (x.a.audioSfxChannel() !== -1 || !off) errors.push(`loop: a new song left the looped effect on channel ${held} (held ${x.a.audioSfxChannel()}, switched off ${off})`);
    notes.push("the gun loop held until its stop (a one-shot ignores it), 4 s with none, cut by a new song");
}

/// The YM mixed under the MOD, refused under an SNDH; SNDH -> MOD.
async function ym(mod, sndh, errors, notes) {
    const a = await modAudio(mod), b = await modAudio(mod);
    const w = [[0, 0x40], [1, 1], [7, 0x3E], [8, 15]];
    for (const [r, v] of w) if (!b.a.audioSfxYm(r, v)) errors.push(`ym: audioSfxYm(${r}) refused under a MOD`);
    let diff = 0;
    for (let i = 0; i < 50; i++) { a.render(128); b.render(128); const x = a.out(), y = b.out(); for (let k = 0; k < 128; k++) diff = Math.max(diff, Math.abs(x[k] - y[k])); }
    if (diff < 0.01) errors.push(`ym: a tone written to the YM does not reach the MOD's output (max difference ${diff})`);
    const s = await machine();
    if (!s.a.audioLoadSndh(s.stage(sndh))) throw new Error(`audioLoadSndh refused ${SNDH}`);
    s.a.audioSndhPlay(1);
    s.render(SR / 4);
    const before = s.a.audioSfxRefused();
    if (s.a.audioSfxYm(8, 15) || s.a.audioSfxRefused() !== before + 1) errors.push("ym: a YM write under an SNDH was not refused and counted");
    if (s.a.audioSfxBufPtr() !== 0) errors.push("ym: the effect buffer is offered while an SNDH owns song RAM");
    if (!s.a.audioLoadMod(s.stage(mod))) errors.push("ym: the MOD after the SNDH was refused");
    s.a.audioModPlay();
    if (s.a.audioMode() !== 1) errors.push(`ym: after SNDH -> MOD the mode is ${s.a.audioMode()}, not 1 (MOD)`);
    const c = await machine();
    c.a.audioLoadMod(c.stage(mod));
    c.a.audioModPlay();
    let d2 = 0;
    for (let i = 0; i < 50; i++) { s.render(128); c.render(128); const x = s.out(), y = c.out(); for (let k = 0; k < 128; k++) d2 = Math.max(d2, Math.abs(x[k] - y[k])); }
    if (d2 > 1e-6) errors.push(`ym: after SNDH -> MOD the output is not the MOD's alone (max difference ${d2.toFixed(4)})`);
    notes.push(`the YM mixed under the MOD (max ${diff.toFixed(3)}), refused under an SNDH, which a MOD then replaces cleanly`);
}

async function refused(errors) {
    const x = await machine();
    if (x.sfx(new Uint8Array(100), 12517, false) || x.a.audioSfxRefused() !== 1) errors.push("refused: an effect with no MOD playing was not refused and counted");
}

async function reject(mod, errors, notes) {
    const x = await machine();
    const tag = (t) => { const m = mod.slice(); m.set([...t].map((c) => c.charCodeAt(0)), 1080); return m; };
    for (const t of ["M.K.", "M!K!", "4CHN", "FLT4"])
        if (!x.a.audioLoadMod(x.stage(tag(t)))) errors.push(`reject: a ${t} MOD was refused`);
    let n = 0;
    for (const t of ["6CHN", "8CHN", "32CH", "\0\0\0\0"]) {
        const ok = x.a.audioLoadMod(x.stage(tag(t)));
        n++;
        if (broke === "reject" && t === "8CHN" ? !ok : ok) errors.push(`reject: a ${JSON.stringify(t)} file loaded as a 4-channel MOD`);
        if (x.a.audioModError() !== 2) errors.push(`reject: ${JSON.stringify(t)} refused for reason ${x.a.audioModError()}, not 2 (not 4-channel)`);
    }
    if (x.a.audioLoadMod(x.stage(mod.subarray(0, 1000))) || x.a.audioModError() !== 1) errors.push("reject: a 1000-byte file was not refused as too short");
    n++;
    if (x.a.audioModRejected() !== n) errors.push(`reject: ${x.a.audioModRejected()} rejections counted, not ${n}`);
    x.a.audioModPlay();
    x.render(SR / 4);
    notes.push(`${n} bad files refused and counted (6CHN, 8CHN, 32CH, untagged, short), the four ProTracker tags loaded`);
}

const errors = [], notes = [];
const mod = new Uint8Array(await readFile(MOD));
const sndh = new Uint8Array(await readFile(SNDH));
const bang = new Uint8Array(await readFile("apps/zig/assets/screens/skystrike/sfx/bang.raw"));
const gun = new Uint8Array(await readFile("apps/zig/assets/screens/skystrike/sfx/gun.raw"));
await oneShot(mod, bang, gun, errors, notes);
await looped(mod, gun, errors, notes);
await ym(mod, sndh, errors, notes);
await refused(errors);
await reject(mod, errors, notes);
await gain(machine, mod, bang, broke, errors, notes);
for (const n of notes) console.log(`  ${n}`);
// exitCode, never process.exit(): on a loaded box (the gate) process.exit()
// with this many wasm instances deadlocked node 24 at exit (main thread and
// its V8 worker both parked on a futex, 0% CPU) in about 1 run in 20, and 4
// of 6 in one gate. Nothing is left pending here, so node exits by itself.
if (broke) {
    const hit = errors.find((e) => e.startsWith(`${broke}:`));
    console.log(hit ? `mod_sfx_check: PASS (--break ${broke} caught: ${hit})` : `mod_sfx_check: FAILED -- --break ${broke} not caught (${errors.length} other errors)`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `mod_sfx_check: FAILED -- ${errors.join("; ")}` : "mod_sfx_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
