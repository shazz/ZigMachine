// The browser host's gamepads (site/js/gamepad.js, R83: two joysticks, one per player), run in a vm
// with scripted Gamepad API objects and a recording cart.
//
//   pad 1          input()/inputRelease(): d-pad, stick past half its throw, fire buttons
//   pad 2          input2()/inputRelease2() when the cart exports both (player 2)
//   no input2      pad 2 merged into input(): an edge only when the union of both pads changes,
//                  so a one-pad cart behaves as with one stick and two pads never cancel each other
//   one pad        a cart WITH input2 sees nothing on player 2
//   a cart swap    a held pad is a fresh press on the new cart; blur lets everything go
//
//   node apps/harness/gamepad_check.mjs [--break pad2|merge]
//   --break pad2   pad 2 is sent to input(): the player-2 check fails
//   --break merge  the merge sends every edge of either pad: the union check fails
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !["pad2", "merge"].includes(broke)) { console.error("--break pad2|merge"); process.exit(2); }

let src = await readFile("site/js/gamepad.js", "utf8");
if (broke === "pad2") src = src.replace("(c) => demo.input2(c)", "(c) => demo.input(c)");
if (broke === "merge") src = src.replace("edges(union(state.now), union(next), inp, rel);", "edges(state.now[0], next[0], inp, rel); edges(state.now[1], next[1], inp, rel);");
const ZMPad = vm.runInNewContext(`${src}; ZMPad`);

const pad = (index, held = {}) => {
    const buttons = Array.from({ length: 17 }, () => ({ pressed: false }));
    for (const b of held.buttons || []) buttons[b].pressed = true;
    return { index, connected: true, buttons, axes: held.axes || [0, 0, 0, 0] };
};
const recorder = (names) => {
    const log = [];
    const demo = {};
    for (const n of names) demo[n] = (c) => log.push(`${n}(${c})`);
    return { demo, log, take: () => log.splice(0).join(" ") };
};
const P1 = ["input", "inputRelease"], P2 = ["input2", "inputRelease2"];
const errors = [];
const expect = (what, got, want) => { if (got !== want) errors.push(`${what}: got "${got}" want "${want}"`); };
const RIGHT = { buttons: [15] }, LEFT = { buttons: [14] }, FIRE = { buttons: [0] };

// A cart with player 2: each pad has its own export pair; the players never touch each other.
{
    const { demo, take } = recorder([...P1, ...P2]);
    ZMPad.poll([pad(0, RIGHT)], demo);
    expect("pad 1 right", take(), "input(3)");
    ZMPad.poll([pad(0, RIGHT)], demo);
    expect("a held pad sends nothing again", take(), "");
    ZMPad.poll([pad(0, RIGHT), pad(1, { buttons: [14, 0] })], demo);
    expect("pad 2 left + fire is player 2", take(), "input2(2) input2(5)");
    ZMPad.poll([pad(0), pad(1, { axes: [0, -0.9] })], demo);
    expect("pad 1 released, pad 2's stick up", take(), "inputRelease(3) input2(0) inputRelease2(2) inputRelease2(5)");
    ZMPad.poll([pad(0)], demo);
    expect("pad 2 unplugged lets go", take(), "inputRelease2(0)");
    ZMPad.poll([pad(0, FIRE), null, pad(3, LEFT)], demo);
    expect("gaps and nulls skipped: the second CONNECTED pad is player 2", take(), "input(5) input2(2)");
    ZMPad.release(demo);
    expect("blur releases both players", take(), "inputRelease(5) inputRelease2(2)");
}

// One pad only: player 2 is never called (a cart with input2 and a one-pad owner play as before).
{
    const { demo, take } = recorder([...P1, ...P2]);
    ZMPad.poll([pad(0, { axes: [0.9, 0] }), pad(1)], demo);
    ZMPad.poll([pad(0, { axes: [0.4, 0] }), pad(1)], demo); // inside the dead zone: released
    expect("one pad, a stick: no player 2 call", take(), "input(3) inputRelease(3)");
}

// A cart WITHOUT input2 (every cart but a two-player one): pad 2 is merged into input().
{
    const { demo, take } = recorder(P1);
    ZMPad.poll([pad(0), pad(1, LEFT)], demo);
    expect("no input2: pad 2 left is input(2)", take(), "input(2)");
    ZMPad.poll([pad(0, LEFT), pad(1, LEFT)], demo);
    expect("...pad 1 joining the same direction is no new press", take(), "");
    ZMPad.poll([pad(0, LEFT), pad(1)], demo);
    expect("...pad 2 letting go does not release what pad 1 holds", take(), "");
    ZMPad.poll([pad(0), pad(1)], demo);
    expect("...both let go: the release", take(), "inputRelease(2)");
    // only one of the pair is not enough: both exports or none
    const half = recorder([...P1, "input2"]);
    ZMPad.poll([pad(0), pad(1, RIGHT)], half.demo);
    expect("input2 without inputRelease2 is merged too", half.take(), "input(3)");
}

// A cart swap: a new demo starts from nothing held, and a pad still held is pressed on it.
{
    const a = recorder(P1), b = recorder(P1);
    ZMPad.poll([pad(0, RIGHT)], a.demo);
    a.take();
    ZMPad.poll([pad(0, RIGHT)], b.demo);
    expect("a pad held across a swap is a fresh press on the new cart", b.take(), "input(3)");
}

if (broke) {
    if (!errors.length) { console.log(`=> FAIL: --break ${broke} was NOT caught`); process.exit(1); }
    console.log(`=> PASS ✅ --break ${broke} caught (${errors.length} failures)`);
    process.exit(0);
}
for (const e of errors) console.log(`  FAIL ${e}`);
if (errors.length) { console.log(`=> FAIL (${errors.length})`); process.exit(1); }
console.log("=> PASS ✅ gamepads: pad 1 = input, pad 2 = input2, merged for a cart without it");
