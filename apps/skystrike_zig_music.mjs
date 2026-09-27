// SKYSTRIKE ZIG-mode harness, the music (apps/skystrike_zig.mjs drives):
// the song requests the host would see (pollSongRequest), at each of the
// game's own switch points (zig_music.zig).
//   zig      the title -> "Explore the sky"; the menu and briefing go on
//            under it; play -> "The Hawk's Claw"; P -> the title's, its end
//            -> the flight's again; the last plane lost -> "dog75"; the key
//            after it -> the title's; the title's timeout to the hall of fame
//            keeps it (no request)
//   original the same moments request skystrike.sndh's tunes, never a MOD
//   swap     Z in flight: ZIG -> skystrike.sndh's silence (its music is off
//            there), back -> the flight's MOD, the engine note replayed onto
//            each (NOISE / ENVEL as calls, as YM writes); Z on the title: ORIGINAL -> the
//            title's MOD, back -> skystrike.sndh the tune the game chose
//   credits  ZIG's title shows the ticker in the band under the screen (the
//            credit text's pixels in the pen), ORIGINAL's does not
// --break music: the flight's MOD expected on the title; swap: Z expected to
// leave the music alone; credits: the ticker looked for in ORIGINAL.
import { readFile } from "node:fs/promises";
import { zsession, WIN_W } from "./skystrike_zig_session.mjs";
import { toPlay } from "./skystrike_session.mjs";

const SNDH = "skystrike.sndh", SILENCE = 4;
const src = await readFile("apps/zig/scenes/skystrike/zig_music.zig", "utf8");
const MOD = Object.fromEntries([...src.matchAll(/\.(title|flying|gameover) = "([^"]+)"/g)].map((m) => [m[1], m[2]]));
const SIT = { none: 0, title: 1, flying: 2, gameover: 3 };
const dec = new TextDecoder();

/// The request pending for the host, if any: "name" or "name#tune".
function request(s) {
    const d = s.demo;
    if (!d.pollSongRequest()) return null;
    const name = dec.decode(new Uint8Array(s.memory.buffer, d.songNamePtr(), d.songNameLen()));
    return name.endsWith(".sndh") ? `${name}#${d.songTune()}` : name;
}

/// The run's request log: polled after every displayed frame, as the host does.
function track(s) {
    const got = [];
    const poll = () => { const r = request(s); if (r) got.push(r); };
    s.each = poll;
    s.take = () => { poll(); return got.splice(0); };
    return s;
}

/// Title -> menu -> briefing -> play -> pause -> flight; then, from play, the
/// last plane lost and back to the title.
async function journey(zig) {
    const s = track(await zsession(zig));
    const at = {};
    await toPlay(s, (what) => { at[what] = s.take(); at[`${what}@`] = s.z("sit"); });
    s.press(0x39);
    for (let p = 0; p < 30; p++) s.pass(s.each);
    at.flight = s.take();
    s.demo.skyTestKey(0x50, 1); s.demo.skyTestKey(0x50, 0);
    s.run(40, s.each);
    at.pause = s.take();
    s.demo.skyTestKey(0x51, 1); s.demo.skyTestKey(0x51, 0);
    for (let p = 0; p < 5; p++) s.pass(s.each);
    at.unpause = s.take();
    // the game over as the screens harness reaches it: at once after play
    const g = track(await zsession(zig));
    await toPlay(g);
    g.take();
    await gameOver(g, at);
    return at;
}

async function gameOver(s, at) {
    s.set("planes", 1);
    s.set("cl", 1);
    for (let i = 0; i < 2000 && s.z("sit") !== SIT.gameover && s.z("tune") !== 2; i++) s.run(1, s.each);
    s.run(20, s.each);
    at.over = s.take();
    s.press(32);
    for (let i = 0; i < 2000 && s.z("sit") !== SIT.title; i++) s.run(1, s.each);
    s.run(20, s.each);
    at.back = s.take();
}

const sndh = (tunes) => (r) => tunes.some((t) => r === `${SNDH}#${t}`);
const is = (name) => (r) => r === name;

function checkJourney(at, zig, broke, errors) {
    const title = broke === "music" ? MOD.flying : MOD.title;
    const want = zig
        ? { title: [is(title)], menu: [], briefing: [], play: [is(MOD.flying)], pause: [is(MOD.title)], unpause: [is(MOD.flying)], over: [is(MOD.gameover)], back: [is(MOD.title)] }
        // ORIGINAL restarts a random tune as the menu and briefing redraw the title (2350)
        : { title: [sndh([1, 3])], menu: [sndh([1, 3])], briefing: [sndh([1, 3])], pause: [sndh([1, 3])], over: [sndh([2])] };
    const mode = zig ? "ZIG" : "ORIGINAL";
    // play's request comes with the first frames of the flight
    const got = { ...at, play: [...(at.play ?? []), ...(at.flight ?? [])] };
    for (const [k, w] of Object.entries(want)) {
        const g = got[k] ?? [];
        const last = g.at(-1);
        const wrong = w.length === 0 ? g.length > 0 : zig ? !(last && w[0](last)) : !g.every(w[0]);
        if (wrong || (!zig && k !== "menu" && k !== "briefing" && !g.length))
            errors.push(`music: ${mode}'s ${k} requested ${JSON.stringify(g)}`);
    }
    if (!zig && Object.values(at).flat().some((r) => typeof r === "string" && r.endsWith(".mod"))) errors.push("music: ORIGINAL requested a MOD");
}

/// The frame's zg.sndhCall ops (d0 & $7FFF), as the host drains them.
function sndhOps(s) {
    const n = s.demo.pollSndhCalls(), out = [];
    for (let i = 0; i < n; i++) out.push(s.demo.sndhCallD0(i) & 0x7fff);
    return out;
}

/// The frame's zg.ymWrite registers, as the host drains them (sfx_queue.zig).
function ymRegs(s) {
    const n = s.demo.pollSfx(), dv = new DataView(s.memory.buffer, s.demo.sfxEntriesPtr(), n * 16), regs = {};
    for (let i = 0; i < n; i++) if (dv.getUint8(i * 16) === 3) regs[dv.getUint8(i * 16 + 1)] = dv.getUint8(i * 16 + 2);
    return regs;
}

/// Z in flight and on the title; the engine note replayed across it.
async function swap(broke, errors) {
    const f = track(await zsession(true));
    await toPlay(f);
    f.press(0x39);
    for (let p = 0; p < 10; p++) f.pass(f.each);
    f.take();
    f.demo.pollSndhCalls();
    f.demo.pollSfx();
    f.press(0x5a);
    const toOrig = f.take(), calls = sndhOps(f);
    f.press(0x5a);
    const toZig = f.take(), ym = ymRegs(f);
    // the engine note replayed onto the new song: NOISE and ENVEL both ways
    const noise = f.v("th") ? 31 - f.v("th") : null;
    if (broke !== "swap" && (!calls.includes(5 << 8 | noise) || !calls.some((d) => d >> 8 === 6)))
        errors.push(`swap: Z to ORIGINAL in flight did not replay the engine note onto skystrike.sndh (calls ${calls.map((d) => d.toString(16))})`);
    if (broke !== "swap" && (ym[6] !== noise || ym[13] === undefined))
        errors.push(`swap: Z to ZIG in flight did not replay the engine note onto the YM (noise ${ym[6]}, shape ${ym[13]}; want noise ${noise})`);
    const t = track(await zsession(false));
    t.vbl(500);
    t.run(2, t.each);
    const tune = t.z("tune");
    t.take();
    t.press(0x5a);
    const tToZig = t.take();
    t.press(0x5a);
    const tToOrig = t.take();
    const expect = [
        ["flight ZIG -> ORIGINAL", toOrig, `${SNDH}#${SILENCE}`],
        ["flight ORIGINAL -> ZIG", toZig, MOD.flying],
        ["title ORIGINAL -> ZIG", tToZig, MOD.title],
        ["title ZIG -> ORIGINAL", tToOrig, `${SNDH}#${tune}`],
    ];
    for (const [what, got, want] of expect) {
        const ok = broke === "swap" ? got.length === 0 : got.at(-1) === want;
        if (!ok) errors.push(`swap: Z (${what}) requested ${JSON.stringify(got)}, not ${broke === "swap" ? "nothing" : want}`);
    }
    return `Z in flight -> ${toOrig.at(-1)} -> ${toZig.at(-1)}; on the title -> ${tToZig.at(-1)} -> ${tToOrig.at(-1)}`;
}

/// The ticker's text pixels in the band under ZIG's title.
async function credits(broke, errors) {
    const out = [];
    for (const zig of [true, false]) {
        const s = await zsession(zig);
        s.vbl(500);
        s.run(3);
        const ov = s.overlay(), shown = s.z("credits");
        let pen = 0;
        for (let y = 265; y < 280; y++) for (let x = 0; x < WIN_W; x++) if (ov[y * WIN_W + x] !== ov[279 * WIN_W]) pen++;
        const want = broke === "credits" ? !zig : zig;
        const on = shown === 1 && pen > 200 && s.demo.isPlaneEnabled(2) === 1;
        if (on !== want) errors.push(`credits: ${zig ? "ZIG" : "ORIGINAL"}'s title ${on ? "shows" : "has no"} music credits (shown ${shown}, ${pen} text pixels in the band)`);
        out.push(`${zig ? "ZIG" : "ORIGINAL"} ${pen} px`);
    }
    return out.join(", ");
}

export async function music(broke) {
    const errors = [];
    const z = await journey(true), o = await journey(false);
    checkJourney(z, true, broke, errors);
    checkJourney(o, false, broke, errors);
    const sw = await swap(broke, errors);
    const cr = await credits(broke, errors);
    const short = (l) => (l ?? []).map((r) => r.replace("skystrike_", "").replace(".mod", "")).join("+") || "-";
    console.log(`  music: ZIG title ${short(z.title)}, play ${short([...z.play, ...z.flight])}, pause ${short(z.pause)}/${short(z.unpause)}, over ${short(z.over)}, back ${short(z.back)}; ORIGINAL title ${short(o.title)}, pause ${short(o.pause)}, over ${short(o.over)}; ${sw}; credits ticker: ${cr}`);
    return errors;
}
