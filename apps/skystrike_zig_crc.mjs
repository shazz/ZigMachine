// SKYSTRIKE ZIG-mode harness, (c) the switch changes nothing but the
// picture and the pace (apps/skystrike_zig.mjs drives).
//
// Three runs of the same flight -- the same input at the same main-loop
// pass, crossing sectors both ways and a layer, firing, a bomb:
//   A  ORIGINAL throughout
//   B  switched by the Z key at passes 25, 55, 85, 115 (ZIG, ORIGINAL, ...)
//   C  ZIG throughout (a frame shown every VBL: the ring's sandboxed draws)
// After every pass the logic state's CRC (zig_crc.zig: every variable, the
// banks, RND, the zones, the sprite table, the flow, both screens; not the
// pacing -- TIMER, z2, t, fps#, lxt) must be the same in all three. Only the
// VBLs a pass took may differ, which is the redraw pause ZIG removes.
// --break crc: run B's switch key is X, a key the game reads into k$.
import { onRunway, steer, Z } from "./skystrike_zig_session.mjs";

const PASSES = 170;
const SWITCHES = [25, 55, 85, 115];
const K_Z = 0x5a, K_X = 0x58, FIRE = 0x80, LEFT = 4, SP = 11;

/// The flight's input at pass p, identical in every run.
function script(s, p) {
    if (p === 0) { s.demo.skyTestKey(57, 1); s.demo.skyTestKey(57, 0); } // throttle 9
    if (p >= 30) s.poke(SP, 11000);
    if (p === 70) steer(s, 8); // back right, over the boundary again
    if (p === 100) steer(s, 5); // climb a layer
    if (p === 128) steer(s, 11); // and down again
    if (p === 145) steer(s, 8);
    s.stick(p >= 40 && p < 46 ? FIRE : p === 150 ? FIRE | LEFT : 0);
}

/// Runs are compared pass for pass from the same main-loop pass: the first
/// screen of play already took ZIG fewer VBLs, so the same VBL is not the
/// same point of the game.
const START = 200;

async function run(zig, switches, key) {
    const s = await onRunway(zig);
    while (s.val(10) < START) s.pass();
    if (s.val(10) !== START) throw new Error(`(c) the run is past pass ${START} on the runway`);
    const crcs = [], vbls = [], modes = [];
    for (let p = 0; p < PASSES; p++) {
        script(s, p);
        if (switches.includes(p)) { s.demo.skyTestKey(key, 1); s.demo.skyTestKey(key, 0); modes.push(s.z("zig")); }
        vbls.push(s.pass());
        crcs.push(s.z("crc") >>> 0);
    }
    return { s, crcs, vbls, modes };
}

export async function crc(broke) {
    const errors = [];
    const a = await run(false, [], K_Z);
    const b = await run(false, SWITCHES, broke === "crc" ? K_X : K_Z);
    const c = await run(true, [], K_Z);
    for (const [name, r] of [["switched", b], ["ZIG", c]]) {
        const at = r.crcs.findIndex((x, i) => x !== a.crcs[i]);
        if (at >= 0) errors.push(`(c) ${name}: the logic state differs from ORIGINAL's after pass ${at} (switches at ${SWITCHES})`);
    }
    if (b.modes.join() !== SWITCHES.map((_, i) => 1 - i % 2).join()) errors.push(`(c) the Z key did not switch the mode (modes ${b.modes})`);
    const zc = c.s;
    if (!zc.z("shifts") || !zc.z("renders")) errors.push(`(c) the ZIG run exercised no ring (shifts ${zc.z("shifts")}, sandboxed draws ${zc.z("renders")})`);
    const sum = (v) => v.reduce((x, y) => x + y, 0);
    const live = [a, c].map((r) => r.s.v("sx") + "/" + r.s.v("al")).join(" ");
    console.log(`  (c) ${PASSES} passes, the CRC after each = ORIGINAL's: switched by Z at ${SWITCHES} (${b.s.z("renders")} sandboxed draws) and ZIG throughout (${zc.z("renders")}); ` +
        `VBLs ORIGINAL ${sum(a.vbls)}, ZIG ${sum(c.vbls)} (the pauses); ${zc.z("shifts")} ring shifts; ends at ${live}`);
    return errors;
}
