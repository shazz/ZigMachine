// SKYSTRIKE harness, part 3 (apps/skystrike_headless.mjs is the driver): the
// game's rules driven by scripted input in lockstep, and the sound commands
// they make (the cart's log of MUSIC / SAMPLAY / SAMLOOP / VOLUME / NOISE /
// ENVEL, in the order the game makes them).
import { session, toPlay, has, ENEMY } from "./skystrike_session.mjs";

const FIRE = 0x80, LEFT = 4;
const E = { sx: 0, al: 2, x: 4, y: 6, fre: 8 }; // enemy 0's ENEMY[k] ids (testapi.zig)

/// In the air: the throttle key, the engine note, fuel burnt, the guns, and
/// an enemy put in the line of fire (the plane flies left) shot at.
async function flying(broke, errors, notes) {
    const s = await session();
    await toPlay(s, null, broke);
    s.runTo("l50", 2000);
    s.clearLog();
    s.press(57); // '9'
    s.vbl(300);
    if (s.v("th") !== 9) errors.push(`logic: key 9 left the throttle at ${s.v("th")}`);
    const log = s.log();
    if (!(has(log, "volume", 16) && has(log, "noise", 22) && has(log, "envel", 10)))
        errors.push(`logic: no engine note at throttle 9 (VOLUME 16, NOISE 22, ENVEL 10): ${log.map((c) => c.toString(16))}`);
    if (s.v("fuel") >= 5000 || s.v("y") >= 154) errors.push(`logic: not flying after 6 s (y ${s.v("y")}, fuel ${s.v("fuel")})`);
    const ammo = s.v("ammo");
    s.clearLog();
    s.stick(FIRE | (broke === "sound" ? LEFT : 0)); // --break sound: a bomb, not the guns
    s.vbl(4);
    s.stick(0);
    s.vbl(6);
    const g = s.log();
    if (s.v("ammo") !== ammo - 1 || !has(g, "samloop", 1) || !has(g, "samplay", 1))
        errors.push(`logic: FIRE: ammo ${ammo} -> ${s.v("ammo")}, sounds ${g.map((c) => c.toString(16))} (want ammo - 1, SAMLOOP ON, SAMPLAY 1)`);
    let shots = 0, hit = null;
    while (s.v("ammo") > 0 && !hit) {
        const sc = s.v("scre");
        s.poke(ENEMY + E.sx, s.v("sx")); s.poke(ENEMY + E.al, s.v("al"));
        s.poke(ENEMY + E.x, s.v("x") - 48); s.poke(ENEMY + E.y, s.v("y"));
        s.clearLog();
        s.stick(FIRE); s.vbl(3); s.stick(0); s.vbl(3);
        shots++;
        if (s.v("scre") !== sc) hit = { d: s.v("scre") - sc, fre: s.val(ENEMY + E.fre), log: s.log() };
    }
    if (!hit || hit.d !== 200 || hit.fre !== 1 || !has(hit.log, "samplay", 2))
        errors.push(`logic: an enemy dead ahead: ${hit ? `scored ${hit.d}, damage ${hit.fre}, sounds ${hit.log.map((c) => c.toString(16))}` : `no hit in ${shots} shots`} (want 200, 1, SAMPLAY 2)`);
    notes.push(`key 9 -> throttle 9 + the engine note, FIRE -> ammo - 1 + the looped burst, an enemy dead ahead hit on shot ${shots}: +200 + the crash sample`);
    return s;
}

/// A crash (altitude layer below the ground): the crash sample, the wreck
/// burning 16 passes, "You Were Killed !", music 2, a key, the title.
async function killed(s, errors, notes) {
    s.clearLog();
    s.set("al", -1);
    s.vbl(6);
    const c = s.log();
    if (!s.v("crsh") || !has(c, "music", 0) || !has(c, "samloop", 0) || !has(c, "samplay", 2))
        errors.push(`logic: the crash: crsh ${s.v("crsh")}, sounds ${c.map((x) => x.toString(16))} (want MUSIC OFF, SAMLOOP OFF, SAMPLAY 2)`);
    s.clearLog();
    if (!s.runTo("l190b", 3000) || !s.v("crsh") || !has(s.log(), "music", 2))
        errors.push(`logic: a crash did not end the game with music 2 (label ${s.label()}, crsh ${s.v("crsh")})`);
    s.vbl(50);
    s.press(32);
    if (!s.runTo("l2006", 3000)) errors.push(`logic: a key after "You Were Killed !" did not return to the title (label ${s.label()})`);
    notes.push("a crash -> the crash sample, killed, music 2, a key, the title");
}

/// The last plane crash-landed: "No More Aircraft !" (crsh = 0), music 2.
async function lastPlane(broke, errors, notes) {
    const s = await session();
    await toPlay(s, null, broke);
    s.set("planes", 1);
    s.set("cl", 1);
    s.clearLog();
    if (!s.runTo("l190b", 3000) || s.v("crsh") !== 0 || s.v("planes") !== 0 || !has(s.log(), "music", 2))
        errors.push(`logic: the last plane landed hard: label ${s.label()}, crsh ${s.v("crsh")}, planes ${s.v("planes")} (want the game over, No More Aircraft)`);
    notes.push("the last plane crash-landed -> No More Aircraft, music 2");
    return s;
}

export async function logic(broke) {
    const errors = [], notes = [];
    const s = await flying(broke, errors, notes);
    await killed(s, errors, notes);
    const t = await lastPlane(broke, errors, notes);
    if (broke === "alloc") t.demo.skyTestRefuse();
    for (const x of [s, t]) {
        const bad = { faults: x.val(1), oob: x.val(2), "bad index": x.val(3), "refused zones": x.val(4), "div by 0": x.val(7) };
        for (const [k, n] of Object.entries(bad)) if (n) errors.push(`logic: ${n} ${k}`);
        const mem = x.machine.hwRamAllocFailures();
        if (mem || x.val(5)) errors.push(`logic: ${mem || x.val(5)} zg.mem allocation(s) refused`);
    }
    console.log(`  logic: ${notes.join("; ")}`);
    return errors;
}
