// GEM 5 step 1 (docs/GEM5_ENGINE.md): the desk mode painted by the engine — object trees, damage
// per buffer, a layer compositor (rom/gem/engine, rom/gem/desktop/eng). Each check below runs the
// real ROM with A:\ open in the desk, the engine on, in both looks (deskSetEngine 1: flat TOS 1; 2: TOS 4 3D).
//   desk      the engine painted the desk: the menu bar, A:\'s frame, the desktop colour, the arrow
//   clean     frames with no input paint nothing: FB_BASE stays, the buffer not on screen keeps
//             every byte of a poison, the engine's drawn-frame counter does not move
//   pointer   a pointer move repaints two 16x16 boxes (<= 512 px of damage), and nothing of a
//             poisoned back buffer outside the boxes around the pointer's last three places
//   window    A:\ dragged by its title bar repaints its old and new places only (a poisoned back
//             buffer survives outside them) and lands where it was dropped
//   oracle    after every gesture, painting only the damage = repainting the whole desk, byte for
//             byte (deskSetEngine again invalidates both buffers: the next frame is a whole repaint)
//   return    Return closes Desktop Info with its default button, old path and engine (TOS form_do)
//   cost      apps/frame_cost.mjs, A:\ open, the pointer moving every frame: old path vs engine
//   node apps/gem_engine_check.mjs        node apps/gem_engine_check.mjs --break
//   --break   each mutant (engine.zig BREAK_*) must be caught: whole (repaint all), noclip (paint
//             unclipped), onesnap (one snapshot for two buffers), drop (lose a damage box), noenter (Return ignored), and
//             engineoff (the engine never switched on)
import { bootGem } from "./gem_headless.mjs";
import { W, H, res, fbBase, settle, pickRes, bufferAt } from "./gem_desk_lib.mjs";
import { cost } from "./gem_engine_cost.mjs";

const MUTANTS = { whole: 1 << 8, noclip: 1 << 9, onesnap: 1 << 10, drop: 1 << 11, noenter: 1 << 12, engineoff: 0 };
const BLACK = 0, WHITE = 1, DESK = 5; // rom/gem/gui/types.zig
const DISK = [{ name: "ALPHA.PRG", type: 0, size: 12345, date: 20260912 }, { name: "README.TXT", type: 1, size: 99, date: 20260912 }];
const WIN = { x: 24, y: 24, w: 320, h: 120 }; // A:\ opens here (deskwin's cascade start, the desk's 640 width)
const click = (gem) => (x, y) => gem.click(res(gem) === 0 ? 2 * x : x, y);

const stats = (gem) => {
    const s = new Uint32Array(gem.memory.buffer, gem.rom.deskEngineStats(), 8);
    return { drawn: s[1], area: s[5] };
};
const other = (gem, pair) => (fbBase(gem) === pair[0] ? pair[1] : pair[0]);

async function setup(brk, look) {
    const gem = await bootGem();
    gem.mount(DISK);
    pickRes(gem, click(gem), "medium", 320, 200);
    pickRes(gem, click(gem), "desk", 640, 200);
    gem.open(35, 40); // A:\ (the floppy icon, top left)
    settle(gem, 10);
    gem.engMode = look | (MUTANTS[brk] ?? 0);
    if (brk !== "engineoff") gem.rom.deskSetEngine(gem.engMode);
    gem.point(400, 300, 0);
    const a = fbBase(gem);
    gem.point(402, 300, 0); // a drawn frame flips: the other buffer
    const pair = [a, fbBase(gem)];
    settle(gem, 4);
    return { gem, pair };
}

// Both buffers repainted whole (deskSetEngine invalidates both snapshots): after a poison test.
function heal(gem) {
    gem.rom.deskSetEngine(gem.engMode);
    settle(gem, 4);
}

// Repaint whole (both snapshots invalidated) and compare with what the damage painted.
function oracle(gem, what, check) {
    settle(gem, 4);
    const shown = bufferAt(gem, fbBase(gem)).slice();
    gem.rom.deskSetEngine(gem.engMode);
    gem.frame();
    const now = bufferAt(gem, fbBase(gem));
    let bad = -1;
    for (let i = 0; i < W * H && bad < 0; i++) if (now[i] !== shown[i]) bad = i;
    check(bad < 0, `oracle: after ${what}, the damage-painted desk differs from a whole repaint at (${bad % W}, ${Math.trunc(bad / W)})`);
    settle(gem, 4);
}

function desk(gem, check) {
    const s = stats(gem), p = bufferAt(gem, fbBase(gem));
    check(s.drawn > 0, `desk: the engine painted nothing (${s.drawn} frames drawn)`);
    check(p[5 * W + 600] === WHITE && p[10 * W + 600] === BLACK, "desk: no menu bar (white rows, a black line at row 10)");
    check(p[WIN.y * W + WIN.x + 100] === BLACK && p[(WIN.y + WIN.h - 1) * W + WIN.x + 100] === BLACK, "desk: no A:\\ frame where it opened");
    check(p[300 * W + 600] === DESK, "desk: no desktop colour at (600, 300)");
    check(p[301 * W + 402] === WHITE && p[302 * W + 403] === BLACK, "desk: no arrow at the pointer (402, 300)");
}

function clean(gem, pair, check) {
    const back = other(gem, pair), f = fbBase(gem), d0 = stats(gem).drawn;
    bufferAt(gem, back).fill(0xEE);
    settle(gem, 6);
    check(fbBase(gem) === f, "clean: a frame with no input moved FB_BASE");
    check(bufferAt(gem, back).every((v) => v === 0xEE), "clean: a frame with no input wrote into the buffer not on screen");
    check(stats(gem).drawn === d0, `clean: ${stats(gem).drawn - d0} frames drawn with no input`);
    heal(gem);
}

// Outside `boxes`, the poison must be intact.
function poisonKept(buf, boxes) {
    for (let y = 0; y < H; y++)
        for (let x = 0; x < W; x++) {
            if (boxes.some((b) => x >= b.x && x < b.x + b.w && y >= b.y && y < b.y + b.h)) continue;
            if (buf[y * W + x] !== 0xEE) return [x, y];
        }
    return null;
}

function pointer(gem, pair, check) {
    gem.point(410, 300, 0);
    check(stats(gem).area <= 2 * 16 * 16, `pointer: a pointer move repainted ${stats(gem).area} px (two arrows: 512)`);
    gem.point(420, 300, 0);
    const back = other(gem, pair);
    bufferAt(gem, back).fill(0xEE);
    gem.point(430, 300, 0); // drawn into the poisoned buffer
    const bad = poisonKept(bufferAt(gem, back), [{ x: 400, y: 300, w: 46, h: 16 }]);
    check(!bad, `pointer: a pointer move wrote outside the arrows' boxes, at (${bad})`);
    heal(gem);
    for (const x of [440, 452, 470]) gem.point(x, 300, 0);
    oracle(gem, "three pointer moves", check);
}

// Matt on the board (9 Nov): Return did not close a dialog although its default button is drawn
// bold. TOS's form_do: Return fires the DEFAULT button. Desktop Info, on the old path and the engine.
function returnKey(gem, check) {
    const breaks = gem.engMode & ~0xFF;
    for (const mode of [0, gem.engMode & 0xFF]) {
        gem.rom.deskSetEngine(mode | breaks);
        gem.point(600, 400, 0);
        settle(gem, 6);
        const before = bufferAt(gem, fbBase(gem)).slice();
        gem.point(20, 4, 0); // over Desk: it drops
        gem.click(30, 15); // Desktop Info...
        gem.point(600, 400, 0);
        settle(gem, 6);
        const same = () => bufferAt(gem, fbBase(gem)).every((v, i) => v === before[i]);
        const path = mode ? "the engine" : "the old path";
        check(!same(), `return: Desktop Info did not open (${path}): the check proves nothing`);
        gem.key(13);
        settle(gem, 6);
        check(same(), `return: Return did not close Desktop Info with its default button (${path})`);
    }
    gem.rom.deskSetEngine(gem.engMode);
    settle(gem, 4);
}

function window(gem, pair, check) {
    const grab = [250, WIN.y + 5], drop = [350, WIN.y + 65];
    gem.point(...grab, 0);
    gem.point(...grab, 1);
    for (let i = 1; i <= 6; i++) gem.point(grab[0] + (drop[0] - grab[0]) * i / 6, grab[1] + (drop[1] - grab[1]) * i / 6, 1);
    const back = other(gem, pair);
    bufferAt(gem, back).fill(0xEE);
    gem.point(...drop, 0); // the release: the window lands
    const moved = { x: WIN.x + 100, y: WIN.y + 60 };
    const room = (r) => ({ x: r.x - 3, y: r.y - 3, w: WIN.w + 8, h: WIN.h + 8 });
    // the buffer holds the frame before last: the outline was one drag step short of the drop then
    const ghost = { x: WIN.x + Math.trunc(100 * 5 / 6), y: WIN.y + Math.trunc(60 * 5 / 6) };
    const bad = poisonKept(bufferAt(gem, back), [room(WIN), room(ghost), room(moved), { x: drop[0] - 70, y: drop[1] - 70, w: 140, h: 140 }]);
    check(!bad, `window: the drop wrote outside the window's old and new places, at (${bad})`);
    const p = bufferAt(gem, back);
    let top = -1;
    for (let y = 11; y < H && top < 0; y++) if (p[y * W + moved.x + 100] === BLACK) top = y;
    check(top === moved.y, `window: A:\\ did not land where it was dropped (its top at y ${top}, want ${moved.y})`);
    heal(gem);
    gem.drag(drop[0], drop[1], drop[0] - 60, drop[1] + 40, 5); // and once more, unpoisoned
    oracle(gem, "a window move", check);
}

async function run(brk, look = 1) {
    const fails = [], check = (ok, what) => ok || fails.push(what);
    const { gem, pair } = await setup(brk, look);
    check(pair[0] !== pair[1], "setup: two pointer moves did not show the desk's two buffers");
    desk(gem, check);
    oracle(gem, "the first frames", check);
    clean(gem, pair, check);
    pointer(gem, pair, check);
    window(gem, pair, check);
    returnKey(gem, check);
    return fails;
}

if (process.argv.includes("--break")) {
    let missed = 0;
    for (const brk of Object.keys(MUTANTS)) {
        const fails = await run(brk);
        console.log(`${fails.length ? "caught " : "MISSED "} ${brk}${fails.length ? ": " + fails[0] : ""}`);
        missed += !fails.length;
    }
    process.exit(missed ? 1 : 0);
}
const fails = [...await run(null, 1), ...(await run(null, 2)).map((f) => `3D look: ${f}`)];
if (!process.argv.includes("--no-cost")) fails.push(...await cost());
for (const f of fails) console.log(`FAIL ${f}`);
console.log(fails.length ? "gem_engine_check: FAILED" : "gem_engine_check: the engine paints the desk, only its damage, per buffer; a clean frame paints nothing; a pointer move two arrows; a window move its two places; damage = whole repaint");
process.exit(fails.length ? 1 : 0);
