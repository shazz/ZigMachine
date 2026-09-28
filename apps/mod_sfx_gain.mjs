// apps/mod_sfx_check.mjs's "gain": zg.requestModVolume on the real audio
// modules (audioModGain, q16 = gain x 65536).
//   scaled   the song's channels at once and from then on at gain x their
//            volume (x 1/1.4); the output exactly gain x the gain-1 output
//   borrowed an effect's channel stays at 64/64 x 1/1.4, unscaled, and the
//            song's other channels go on scaled; the channel given back is
//            scaled again
//   reset    a new MOD starts at gain 1
//   refused  q16 over 1.0, or no MOD playing: refused and counted
// --break gain: the effect's channel expected scaled too.
const SR = 44100, HEADROOM = 1 / 1.4, G = 0.25, Q = G * 65536;

const vols = (x, from, pred = () => true) => x.log.filter((e) => e.fn === "SetVolume" && e.at >= from && pred(e));

/// Two machines on the same song, one at gain G from `at`: their output.
async function level(machine, mod, errors) {
    const one = await machine(), g = await machine();
    for (const x of [one, g]) { x.a.audioLoadMod(x.stage(mod)); x.a.audioModPlay(); x.render(SR / 2); }
    if (!g.a.audioModGain(Q)) errors.push("gain: audioModGain refused over a playing MOD");
    let e1 = 0, eg = 0;
    for (let i = 0; i < SR * 4 / 128; i++) {
        one.render(128); g.render(128);
        for (const v of one.out()) e1 += v * v;
        for (const v of g.out()) eg += v * v;
    }
    const db = 10 * Math.log10(eg / e1), want = 20 * Math.log10(G);
    if (Math.abs(db - want) > 0.01) errors.push(`gain: at ${G} the song is ${db.toFixed(3)} dB, not ${want.toFixed(3)}`);
    return { g, db };
}

async function borrowed(x, bang, broke, errors) {
    const t0 = x.frames;
    x.sfx(bang, 12517, false);
    const ch = x.a.audioSfxChannel();
    const v = vols(x, t0, (e) => e.ch === ch && e.at === t0).at(-1)?.a[0];
    const want = broke === "gain" ? HEADROOM * G : HEADROOM;
    if (v === undefined || Math.abs(v - want) > 1e-6) errors.push(`gain: the effect's channel ${ch} is at ${v}, not ${want.toFixed(4)} (64/64 x 1/1.4${broke === "gain" ? " x the gain" : ", unscaled"})`);
    x.render(Math.ceil(bang.length * SR / 12517) + SR);
    const song = vols(x, t0 + 1, (e) => e.ch !== ch || e.at > t0 + bang.length * SR / 12517);
    const loud = song.filter((e) => e.a[0] > HEADROOM * G + 1e-6);
    if (!song.length) errors.push("gain: the song wrote no volume while and after the effect played: unchecked");
    if (loud.length) errors.push(`gain: the song wrote ${loud.length} volumes over ${G} x 1/1.4 around the effect (channel ${loud[0].ch}: ${loud[0].a[0]})`);
    return ch;
}

export async function gain(machine, mod, bang, broke, errors, notes) {
    const { g, db } = await level(machine, mod, errors);
    const t1 = g.frames;
    g.a.audioModGain(Q);
    const now = vols(g, t1, (e) => e.at === t1);
    if (now.length !== 4) errors.push(`gain: the gain rewrote ${now.length} channels' volumes at once, not 4`);
    const ch = await borrowed(g, bang, broke, errors);
    const refused = g.a.audioSfxRefused();
    if (g.a.audioModGain(65537) || g.a.audioSfxRefused() !== refused + 1) errors.push("gain: a gain over 1.0 was not refused and counted");
    const t2 = g.frames;
    g.a.audioLoadMod(g.stage(mod));
    g.a.audioModPlay();
    g.render(SR * 2);
    if (!vols(g, t2, (e) => e.a[0] > HEADROOM * G + 1e-6).length) errors.push("gain: a new MOD did not start back at gain 1");
    const none = await machine();
    if (none.a.audioModGain(Q) || none.a.audioSfxRefused() !== 1) errors.push("gain: a gain with no MOD playing was not refused and counted");
    notes.push(`gain ${G}: the song ${db.toFixed(2)} dB, its channels rescaled at once, the effect on channel ${ch} unscaled at 64/64 x 1/1.4, back to 1 on a new MOD; over 1.0 or no MOD refused`);
}
