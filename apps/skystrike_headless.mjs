// Headless SKYSTRIKE driver (cart 79: the STOS game, Automation Menu 258).
// The reference is the ORIGINAL compiled program run on Hatari (TOS 1.02, ST):
// apps/skystrike_fixture.json, from tools/skystrike/make_fixture.py.
//   screens  in lockstep (50 Hz VBLs, RND seeded), the title, the difficulty
//            menu, mission 1's briefing, the first frame of play, a crash
//            landing and the hall of fame: the back / physic screens' colour
//            indices = the ST's RAM, pixel for pixel (rows under sprites or
//            the scroller's newest letter are left out)
//   takeoff  throttle 9 from the runway: x, y, the heading, SP# and the fuel
//            after each of 98 main-loop passes = the ST's own trace
//   logic    keys 0-9 set the throttle; the engine note; FIRE: ammo and the
//            looped gun sample; an enemy in the line of fire: hits score 200
//            with the crash sample; a crash kills ("You Were Killed !",
//            music 2, a key, the title); a crash landing costs a plane, the
//            last one is "No More Aircraft !"; the title times out to the
//            hall of fame; no flow fault, no PEEK/POKE outside a bank, no bad
//            array index, no refused zone or zg.mem allocation
//   live + sound   apps/skystrike_live.mjs
//   node apps/skystrike_headless.mjs [outdir]
//   node apps/skystrike_headless.mjs --break screen|physics|sound|sndh|alloc
//            a wrong menu choice / throttle 8 / a bomb for the burst / the
//            wrong sample / a refused zg.mem allocation: passes only if caught
import { mkdir, readFile } from "node:fs/promises";
import { inflateSync } from "node:zlib";
import { live, sound } from "./skystrike_live.mjs";
import { session, toPlay, has, L, PASSES, SP } from "./skystrike_session.mjs";
import { logic } from "./skystrike_logic.mjs";

const BREAKS = ["screen", "physics", "sound", "sndh", "alloc"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/skystrike";
const fixture = JSON.parse(await readFile("apps/skystrike_fixture.json", "utf8"));

function compareScreens(s, names, errors) {
    for (const ref of fixture.screens.filter((r) => names.includes(r.name.split(" ").slice(0, -1).join(" ")))) {
        const want = inflateSync(Buffer.from(ref.z, "base64"));
        const scr = s.screen(ref.screen);
        let o = 0, bad = 0, first = null;
        for (const [a, b] of ref.spans) for (let i = a * 320; i < b * 320; i++, o++)
            if (scr[i] !== want[o]) { bad++; first ??= `x ${i % 320} y ${(i / 320) | 0}: ${scr[i]} not ${want[o]}`; }
        if (bad) errors.push(`screen: ${ref.name}: ${bad} pixels differ (first at ${first})`);
        else s.passed.push(ref.name);
    }
}

async function screens() {
    const errors = [];
    const s = await session();
    s.passed = [];
    await toPlay(s, (what) => {
        if (what === "title" && !has(s.log(), "music", 1) && !has(s.log(), "music", 3))
            errors.push(`logic: no title tune (MUSIC 1 or 3): ${s.log().map((c) => c.toString(16))}`);
        compareScreens(s, { title: ["title"], menu: ["menu"], briefing: ["briefing"], play: ["play"] }[what], errors);
    }, broke);
    const c = await session();
    c.passed = s.passed;
    await toPlay(c);
    c.set("cl", 1); // the ST reference poked cl = 1 at the same point
    c.vbl(200);
    compareScreens(c, ["crash-land"], errors);
    if (c.v("planes") !== 2) errors.push(`logic: a crash landing left ${c.v("planes")} planes, not 2`);
    const h = await session();
    h.passed = s.passed;
    h.vbl(2200);
    if (h.label() < L.l2260 || h.label() > L.l2311) errors.push(`logic: the title's timeout is not in the hall of fame (label ${h.label()})`);
    compareScreens(h, ["hall of fame"], errors);
    console.log(`  screens: ${s.passed.length} of ${fixture.screens.length} = the ST's RAM (${s.passed.join(", ")})`);
    return errors;
}

async function takeoff() {
    const s = await session();
    await toPlay(s);
    s.runTo("l50", 2000);
    s.set("th", broke === "physics" ? 8 : 9);
    const rows = [];
    let last = s.val(PASSES);
    for (let g = 0; rows.length < fixture.takeoff.length && g < 20000; g++) {
        s.vbl(1);
        if (s.val(PASSES) === last) continue;
        last = s.val(PASSES);
        rows.push([s.v("x"), s.v("y"), s.v("r"), s.val(SP), s.v("fuel")]);
    }
    const bad = rows.findIndex((r, i) => { const w = fixture.takeoff[i]; return r[0] !== w[0] || r[1] !== w[1] || r[2] !== w[2] || Math.abs(r[3] - w[3]) > 2 || r[4] !== w[4]; });
    const errors = bad >= 0 || rows.length < fixture.takeoff.length
        ? [`takeoff: pass ${bad} is x,y,r,sp,fuel ${rows[bad]}, the ST ${fixture.takeoff[bad]}`] : [];
    console.log(`  takeoff: ${rows.length} passes at throttle 9, x ${rows[0]?.[0]} -> ${rows.at(-1)?.[0]}, y ${rows[0]?.[1]} -> ${rows.at(-1)?.[1]}: ${errors.length ? "DIFFER" : "= the ST's trace"}`);
    return errors;
}

await mkdir(outdir, { recursive: true });
const errors = [...await screens(), ...await takeoff(), ...await logic(broke), ...await live(outdir, L), ...await sound(broke)];
if (broke) {
    console.log(errors.length ? `skystrike: PASS (--break ${broke} caught: ${errors[0]})` : `skystrike: FAILED -- --break ${broke} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `skystrike: FAILED -- ${errors.join("; ")}` : "skystrike: all pass");
process.exit(errors.length ? 1 : 0);
