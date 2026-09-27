// SKYSTRIKE ZIG-mode harness, the weapon keys (zig_keys.zig; apps/
// skystrike_zig.mjs drives). One key held is the chord it stands for, and
// nothing else: from the same pass of the same flight, the key held for
// three passes and the chord held for three passes leave the same logic
// state (the CRC; Space against ORIGINAL's Space + left, as Space also puts
// " " in the key buffer) --
//   left Ctrl = FIRE (the guns: a round taken), left Shift = FIRE + right
//   (a rocket), Space = FIRE + left (a bomb)
// -- and with the pilot bailed out, Space is ORIGINAL's Space (FIRE, and the
// key the chute's landing reads). ORIGINAL ignores Ctrl and Shift.
// --break keys: Shift compared with FIRE + left.
import { onRunway, takeOff, steer } from "./skystrike_zig_session.mjs";

const FIRE = 0x80, LEFT = 4, RIGHT = 8, CTRL = 0xe014, SHIFT = 0xe015, SPACE = 0x20, ESC = 0xe012, ENTER = 13, SP = 11;
const START = 200; // as apps/skystrike_zig_crc.mjs

/// The flight to pass 30 in the air, then `act` held for 3 passes.
async function flight(zig, act) {
    const s = await onRunway(zig);
    while (s.val(10) < START) s.pass(); // the same pass in either mode
    takeOff(s, 30);
    const before = { ammo: s.v("ammo"), rkf: s.v("rkf"), bf: s.v("bf") };
    act.down(s);
    for (let p = 0; p < 3; p++) s.pass();
    act.up(s);
    s.pass();
    return { crc: s.z("crc") >>> 0, before, after: { ammo: s.v("ammo"), rkf: s.v("rkf"), bf: s.v("bf") } };
}

/// Bailed out (Esc, 153), then Space held: VBL by VBL, as a verdict may
/// follow. Returns the CRC and whether the pilot was out.
async function bailed(zig) {
    const s = await onRunway(zig);
    while (s.val(10) < START) s.pass(); // the same pass in either mode
    takeOff(s, 30);
    steer(s, 5); // up a layer, high enough for the chute
    for (let p = 0; p < 100 && s.v("al") < 1; p++) { s.poke(SP, 11000); s.pass(); }
    steer(s, 4);
    const tap = (cp) => { s.demo.skyTestKey(cp, 1); s.demo.skyTestKey(cp, 0); };
    tap(ESC); s.pass(); s.pass();
    tap(ENTER);
    for (let p = 0; p < 6; p++) s.pass();
    const out = s.v("bale");
    s.demo.skyTestKey(SPACE, 1); s.pass(); s.demo.skyTestKey(SPACE, 0);
    for (let p = 0; p < 6; p++) s.pass();
    return { crc: s.z("crc") >>> 0, out };
}

const key = (cp) => ({ down: (s) => s.demo.skyTestKey(cp, 1), up: (s) => s.demo.skyTestKey(cp, 0) });
const chord = (bits) => ({ down: (s) => s.stick(bits), up: (s) => s.stick(0) });
/// Space as ORIGINAL reads it (FIRE, and " " into the key buffer) + left.
const spaceLeft = { down: (s) => { s.demo.skyTestKey(SPACE, 1); s.stick(LEFT | FIRE); }, up: (s) => { s.demo.skyTestKey(SPACE, 0); s.stick(0); } };
const none = { down: () => {}, up: () => {} };

export async function keys(broke) {
    const errors = [], notes = [];
    const cases = [
        ["Ctrl", CTRL, FIRE, (r) => r.after.ammo < r.before.ammo, "the guns"],
        ["Shift", SHIFT, broke === "keys" ? FIRE | LEFT : FIRE | RIGHT, (r) => r.after.rkf !== 0, "a rocket"],
        ["Space", SPACE, FIRE | LEFT, (r) => r.after.bf !== 0 || r.after.ammo === r.before.ammo, "a bomb"],
    ];
    for (const [name, cp, bits, did, what] of cases) {
        const k = await flight(true, key(cp)), c = cp === SPACE ? await flight(false, spaceLeft) : await flight(true, chord(bits));
        if (k.crc !== c.crc) errors.push(`keys: ZIG's ${name} is not the chord ${bits.toString(16)} (the logic differs)`);
        if (!did(k)) errors.push(`keys: ZIG's ${name} did not fire ${what} (${JSON.stringify(k.before)} -> ${JSON.stringify(k.after)})`);
        else notes.push(`${name} = ${what}`);
    }
    const zb = await bailed(true), ob = await bailed(false);
    if (zb.out !== 1) errors.push(`keys: Esc did not bail out (bale ${zb.out})`);
    if (zb.crc !== ob.crc) errors.push("keys: bailed out, ZIG's Space is not ORIGINAL's");
    for (const [name, cp] of [["Ctrl", CTRL], ["Shift", SHIFT]]) {
        const o = await flight(false, key(cp)), n = await flight(false, none);
        if (o.crc !== n.crc) errors.push(`keys: ORIGINAL's ${name} changed the game`);
    }
    console.log(`  keys: ZIG ${notes.join(", ")}, each = its chord pass for pass; bailed out Space = ORIGINAL's; ORIGINAL ignores Ctrl and Shift`);
    return errors;
}
