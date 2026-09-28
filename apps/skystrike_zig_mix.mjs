// SKYSTRIKE ZIG-mode harness, the engine note's registers (engineCheck) and
// the mix (apps/skystrike_zig_sound.mjs calls both): the levels the player
// hears in flight, on the real audio modules
// (docs/machine-audio.wasm + docs/demo-audio.wasm), RMS over both sides.
//   bed     "The Hawk's Claw" at the gain the cart requested for the flight
//           (zg.requestModVolume), one channel lent as under an effect,
//           20 s of it
//   effect  each sample the flight played, alone (the MOD's own samples
//           zeroed, so the player runs and lends a channel but is silent),
//           over its length (the gun loop: 1 s)
//   engine  the YM as the flight's own writes left it (zig_psg.zig), alone
// Each effect must stand EACH_DB over the bed, and their mean MEAN_DB over it
// (zig_settings.zig's music_gain_play is chosen for 6); the engine under the
// effects' mean, so it does not bury them either.
import { readFile } from "node:fs/promises";

const SR = 44100, MOD = "docs/music/skystrike_the_hawks_claw.mod";
const EACH_DB = 3, MEAN_DB = 5;

/// The engine note: ZIG's YM registers (as the writes before the runway and
/// since take-off leave them) = the game's own PSG commands (its log, the
/// same in both modes) as sound.s writes them (zig_psg.zig), VOLUME on the
/// first zig_settings.psg_voices voices only.
const OP = { volume: 4, noise: 5, envel: 6, hi: 7, lo: 8 };
export function engineCheck(z, o, errors) {
    const regs = new Array(14).fill(null), want = new Array(14).fill(null);
    for (const c of [...z.engine.pre, ...z.engine.ym]) regs[c.a] = c.b;
    let period = 0;
    for (const d of z.engine.log) {
        const op = d >> 8, arg = d & 0xff;
        if (op === OP.volume) for (let v = 0; v < 3; v++) want[8 + v] = v < z.voices ? arg : 0;
        if (op === OP.noise) { want[6] = arg & 31; want[7] = 0xC0; }
        if (op === OP.hi) period = arg << 8 | period & 0xff;
        if (op === OP.lo) period = period & 0xff00 | arg;
        if (op === OP.envel) { want[11] = period & 0xff; want[12] = period >> 8; want[13] = arg & 15; }
    }
    const bad = want.map((w, r) => (w !== null && regs[r] !== w ? `r${r} ${regs[r]} not ${w}` : null)).filter(Boolean);
    if (!want.some((w) => w !== null)) errors.push("sound: throttle 8 logged no PSG command: the engine went unchecked");
    if (bad.length) errors.push(`sound: ZIG's engine note on the YM differs from the game's commands: ${bad.join(", ")}`);
    if (o.engine.log.join() !== z.engine.log.join()) errors.push("sound: the game's PSG commands differ between the modes");
    return `the engine: noise ${regs[6]}, envelope ${regs[13]} period ${regs[12] << 8 | regs[11]} = the game's commands (${z.engine.ym.length} YM writes since take-off)`;
}

/// The flight's MOD (or `mod`) playing at q16 / 65536 of its volume.
async function machine(mod, q16) {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    new Uint8Array(memory.buffer, a.audioSongPtr(), mod.length).set(mod);
    if (!a.audioLoadMod(mod.length)) throw new Error("audioLoadMod refused the flight's MOD");
    a.audioModPlay();
    if (!a.audioModGain(q16)) throw new Error(`audioModGain(${q16}) refused`);
    const x = { a, sum: 0, n: 0 };
    /// n frames; their energy counted when `measure`.
    x.render = (n, measure) => {
        for (let i = 0; i < n; i += 128) {
            a.audioRender(128);
            if (!measure) continue;
            for (const p of [m.audioLeftPtr(), m.audioRightPtr()])
                for (const v of new Float32Array(memory.buffer, p, 128)) { x.sum += v * v; x.n++; }
        }
    };
    x.sfx = (bytes, rate, loop) => {
        new Uint8Array(memory.buffer, a.audioSfxBufPtr(), bytes.length).set(bytes);
        if (!a.audioSfxPlay(bytes.length, rate, loop ? 1 : 0)) throw new Error("audioSfxPlay refused");
    };
    x.db = () => 10 * Math.log10(x.sum / x.n);
    return x;
}

/// The MOD with every sample's bytes zeroed: it plays, silently.
function silenced(mod) {
    let patterns = 0;
    for (let i = 0; i < 128; i++) patterns = Math.max(patterns, mod[952 + i]);
    const out = mod.slice();
    out.fill(0, 1084 + (patterns + 1) * 1024);
    return out;
}

/// The bed: the song with one channel lent to a silent loop (re-lent
/// before its 4 s timeout), 20 s.
async function bed(mod, q16) {
    const x = await machine(mod, q16);
    for (let t = 0; t < 20; t += 2) { x.sfx(new Uint8Array(64), 12517, true); x.render(SR * 2, true); }
    return x.db();
}

/// `fx`: [{ name, bytes, rate, loop }]; `ym`: [[reg, val]] in order; `q16`:
/// the flight's gain as the cart requested it. Returns the summary line.
export async function mix(fx, ym, q16, errors) {
    const mod = new Uint8Array(await readFile(MOD)), quiet = silenced(mod);
    const b = await bed(mod, q16);
    const levels = [];
    for (const f of fx) {
        const x = await machine(quiet, q16);
        x.render(SR / 4, false);
        x.sfx(f.bytes, f.rate, f.loop);
        x.render(f.loop ? SR : Math.ceil(f.bytes.length * SR / f.rate), true);
        levels.push({ name: f.name, db: x.db() });
    }
    const e = await machine(quiet, q16);
    e.render(SR / 4, false);
    for (const [r, v] of ym) e.a.audioSfxYm(r, v);
    e.render(SR, true);
    const engine = e.db();
    const mean = 10 * Math.log10(levels.reduce((s, l) => s + 10 ** (l.db / 10), 0) / levels.length);
    for (const l of levels)
        if (l.db - b < EACH_DB) errors.push(`mix: ${l.name} is ${(l.db - b).toFixed(1)} dB over the music bed (gain ${(q16 / 65536).toFixed(3)}), under ${EACH_DB}`);
    if (mean - b < MEAN_DB) errors.push(`mix: the effects average ${(mean - b).toFixed(1)} dB over the music bed, under ${MEAN_DB}`);
    if (engine >= mean) errors.push(`mix: the engine (${engine.toFixed(1)} dBFS) is not under the effects (${mean.toFixed(1)} dBFS)`);
    if (!levels.length) errors.push("mix: the flight played no effect: the mix went unchecked");
    const each = levels.map((l) => `${l.name} ${(l.db - b >= 0 ? "+" : "")}${(l.db - b).toFixed(1)}`).join(", ");
    return `the mix at gain ${(q16 / 65536).toFixed(3)}: bed ${b.toFixed(1)} dBFS, effects ${each} dB (mean ${(mean - b).toFixed(1)}), engine ${engine.toFixed(1)} dBFS`;
}

/// apps/skystrike_zig_music.mjs's "gain": each MOD request's gain (`at`: its
/// journey, each stage's requests with their .gains) = its situation's
/// setting (`set`: the cart's, x 1000).
export function checkGains(at, zig, set, broke, errors) {
    const q = (milli) => Math.round(milli / 1000 * 65536);
    const title = broke === "gain" ? set.play : set.menus;
    const want = { title, play: set.play, pause: set.menus, unpause: set.play, over: set.over, back: set.menus };
    const gains = (k) => [...(at[k]?.gains ?? []), ...(k === "play" ? at.flight?.gains ?? [] : [])];
    const mode = zig ? "ZIG" : "ORIGINAL";
    if (!zig) {
        const any = Object.keys(at).flatMap((k) => at[k]?.gains ?? []);
        if (any.length) errors.push(`gain: ORIGINAL requested MOD gains ${any}`);
        return;
    }
    for (const [k, w] of Object.entries(want)) {
        const g = gains(k);
        if (g.length !== 1 || Math.abs(g[0] - q(w)) > 1) errors.push(`gain: ${mode}'s ${k} requested gains ${JSON.stringify(g)} (x 65536), not one of ${q(w)}`);
    }
    for (const k of ["menu", "briefing"]) if (gains(k).length) errors.push(`gain: ${mode}'s ${k} requested gains ${gains(k)} with no MOD`);
    if (!(set.play < set.menus)) errors.push(`gain: the flight's music gain ${set.play / 1000} is not under the menus' ${set.menus / 1000}`);
}
