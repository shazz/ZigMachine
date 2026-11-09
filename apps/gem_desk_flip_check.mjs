// GEM's desk mode on the board (Matt, 8 Nov 2026): the screen blinked whenever the mouse moved,
// and there was no pointer. The board scans plane 0 out LIVE in the desk, and every drawn frame
// repainted the whole screen in place, so the half-drawn frame was on the screen; the board has
// no picture to draw its arrow on there (fpga/cycles/bmain.c). Now the shell hands the ROM two
// buffers and the ROM draws each frame into the one not on screen, then flips FB_BASE
// (rom/gem/desktop/deskflip.zig), and GEM draws TOS's arrow last in a desk frame (deskarrow.zig).
//   flip     a clean frame moves nothing (FB_BASE, the pixels); a pointer move flips FB_BASE to
//            the other buffer of a pair (64-aligned, in the pool, not overlapping, one of them
//            the boot buffer) and leaves the buffer that was on screen untouched; the desk rests
//            again within SETTLE frames
//   whole    a session (A:\ opened and dragged to y 184, a menu title hovered, a click) with the back buffer
//            poisoned before every frame shows, frame by frame, the single-buffered desk's
//            pictures: every drawn frame is whole, and two buffers change no pixel
//   arrow    in the desk the arrow (mask white, data black) is at the pointer, and follows it;
//            in LOW and MEDIUM the plane under the pointer is bare desktop (the hosts draw it)
//   node apps/gem_desk_flip_check.mjs        node apps/gem_desk_flip_check.mjs --break
//   --break  each mutant must be caught: noflip (the shell's buffers never reach the ROM), busy
//            (a host that moves the pointer every frame: the desk never rests), arrow (the ROM
//            told a pointer 24 pixels right of the page's), lowarrow (an arrow in the low plane)
import { bootGem } from "./gem_headless.mjs";
import { W, H, OFF_VRAM, VRAM_BYTES, res, fbBase, settle, pickRes, deskPicture, bufferAt } from "./gem_desk_lib.mjs";

const MUTANTS = ["noflip", "busy", "arrow", "lowarrow"];
const BLACK = 0, WHITE = 1, DESK = 5; // rom/gem/gui/types.zig
const MASK = [0xC000, 0xE000, 0xF000, 0xF800, 0xFC00, 0xFE00, 0xFF00, 0xFF80, 0xFFC0, 0xFFE0, 0xFE00, 0xEF00, 0xCF00, 0x8780, 0x0780, 0x0380];
const DATA = [0x0000, 0x4000, 0x6000, 0x7000, 0x7800, 0x7C00, 0x7E00, 0x7F00, 0x7F80, 0x7C00, 0x6C00, 0x4600, 0x0600, 0x0300, 0x0300, 0x0000];
const DISK = [{ name: "ALPHA.PRG", type: 0, size: 12345, date: 20260912 }];
const ROM = {
    noflip: () => ({ deskSetBuffers: () => {} }),
    arrow: (rom, m) => ({ deskHostPointer: (x, y, b) => rom.deskHostPointer(m.hwDeskActive() ? x + 24 : x, y, b) }),
};

const click = (gem) => (x, y) => gem.click(res(gem) === 0 ? 2 * x : x, y); // low res: the host's x is doubled
const park = (gem, x, y) => { gem.point(res(gem) === 0 ? 2 * x : x, y, 0); settle(gem, 6); };
// The 16x16 under (x, y) in a plane of `stride`: the arrow's indices, or `bare` when it is all DESK.
function arrowAt(plane, stride, x, y) {
    let arrow = true, bare = true;
    for (let r = 0; r < 16; r++)
        for (let i = 0; i < 16; i++) {
            const bit = 0x8000 >> i, v = plane[(y + r) * stride + x + i];
            const want = MASK[r] & bit ? (DATA[r] & bit ? BLACK : WHITE) : DESK;
            arrow &&= v === want;
            bare &&= v === DESK;
        }
    return { arrow, bare };
}
function poke(plane, stride, x, y) { // the lowarrow mutant: an arrow where the hosts draw theirs
    for (let r = 0; r < 16; r++) for (let i = 0; i < 16; i++) if (MASK[r] & (0x8000 >> i)) plane[(y + r) * stride + x + i] = WHITE;
}

// LOW, then MEDIUM, then the desk; the plane modes have no arrow of GEM's under the pointer.
async function toDesk(brk, check) {
    const gem = await bootGem({ rom: ROM[brk] });
    gem.mount(DISK);
    const a = fbBase(gem);
    for (const [mode, stride, sw] of [["low", 320, 320], ["medium", 640, 640]]) {
        if (mode === "medium") pickRes(gem, click(gem), "medium", 320, 200);
        park(gem, 200, 150);
        const plane = new Uint8Array(gem.memory.buffer, gem.machine.hwVideoBase() + fbBase(gem), stride * 200);
        if (brk === "lowarrow" && mode === "low") poke(plane, stride, 200, 150);
        check(arrowAt(plane, stride, 200, 150).bare, `arrow: GEM drew under the pointer in ${mode} (${sw} wide): the host draws it there`);
    }
    pickRes(gem, click(gem), "desk", 640, 200);
    check(gem.machine.hwDeskActive() === 1, `flip: Desk + OK left RESOLUTION ${res(gem)}`);
    return { gem, a };
}

function flips(brk, gem, a, check) {
    park(gem, 400, 300);
    const f0 = fbBase(gem), pic0 = deskPicture(gem);
    for (let i = 0; i < 8; i++) {
        if (brk === "busy") gem.demo.pointer(400 + (i & 1), 300, 0);
        gem.frame();
        if (fbBase(gem) !== f0) return check(false, `flip: a clean frame (${i}) moved FB_BASE`);
    }
    check(deskPicture(gem).every((v, i) => v === pic0[i]), "flip: a clean frame changed the picture");
    const shown = bufferAt(gem, f0).slice();
    gem.point(410, 300, 0);
    const f1 = fbBase(gem);
    check(f1 !== f0, "flip: a drawn frame (the pointer moved) left FB_BASE where it was");
    check(bufferAt(gem, f0).every((v, i) => v === shown[i]), "flip: the drawn frame wrote into the buffer on screen");
    const lo = Math.min(f0, f1), hi = Math.max(f0, f1);
    check(lo % 64 === 0 && hi % 64 === 0 && lo >= OFF_VRAM && hi + W * H <= OFF_VRAM + VRAM_BYTES && hi - lo >= W * H,
        `flip: the buffers ${f0}, ${f1} are not two 64-aligned, disjoint desk buffers in the pool`);
    check(f0 === a || f1 === a, "flip: neither buffer is the one the boot allocated");
    let n = 0, last = f1;
    for (let i = 0; i < 10; i++) {
        gem.frame();
        if (fbBase(gem) !== last) n++, last = fbBase(gem);
        if (i >= 4) check(fbBase(gem) === last, "flip: the desk did not rest after the move");
    }
    check(n <= 2 && (last === f0 || last === f1), `flip: ${n} flips after one move (SETTLE is 2), FB_BASE ${last}`);
    const { arrow } = arrowAt(bufferAt(gem, fbBase(gem)), W, 410, 300);
    check(arrow, "arrow: no arrow at the pointer (410, 300) in the desk");
    park(gem, 100, 350);
    const now = bufferAt(gem, fbBase(gem));
    check(arrowAt(now, W, 100, 350).arrow && arrowAt(now, W, 410, 300).bare, "arrow: it did not follow the pointer to (100, 350)");
}

// One input a frame (null: none), the same for both desks.
const SESSION = [[35, 40, 0], [35, 40, 2], [35, 40, 0], ...Array(12).fill(null),
    ...Array.from({ length: 8 }, (_, i) => [200 + 12 * i, 30 + 20 * i, 1]), [296, 190, 0], ...Array(6).fill(null),
    [120, 4, 0], ...Array(6).fill(null), [500, 400, 0], [500, 400, 1], [500, 400, 0], ...Array(6).fill(null)];
// `pair`: poison the buffer not on screen before every frame (null: the single-buffered desk).
function play(gem, pair) {
    const pics = [];
    for (const s of SESSION) {
        if (pair) bufferAt(gem, fbBase(gem) === pair[0] ? pair[1] : pair[0]).fill(0xEE);
        if (s) gem.demo.pointer(...s);
        gem.frame();
        pics.push(deskPicture(gem));
    }
    return pics;
}
async function whole(brk, check) {
    const { gem } = await toDesk(brk, check), ref = (await toDesk("noflip", () => true)).gem;
    for (const g of [gem, ref]) g.point(410, 300, 0);
    const f0 = fbBase(gem);
    for (const g of [gem, ref]) g.point(420, 300, 0); // a second drawn frame: the other buffer
    const pair = fbBase(gem) !== f0 ? [f0, fbBase(gem)] : null;
    if (brk !== "noflip") check(pair !== null, "whole: two moves did not show two buffers (nothing poisoned)");
    const pics = play(gem, pair), refPics = play(ref, null);
    const plane = bufferAt(gem, fbBase(gem));
    let black = 0;
    for (let x = 130; x < 400; x++) black += plane[184 * W + x] === BLACK;
    check(black > 240, "whole: A:\\ was not dragged to y 184 (no title bar frame there): the session proves less than it says");
    const bad = pics.findIndex((pic, i) => !pic.every((v, j) => v === refPics[i][j]));
    check(bad < 0, `whole: session frame ${bad} over a poisoned back buffer is not the single-buffered desk's`);
}

async function run(brk) {
    const fails = [], check = (ok, what) => ok || fails.push(what);
    const { gem, a } = await toDesk(brk, check);
    flips(brk, gem, a, check);
    await whole(brk, check);
    return fails;
}

if (process.argv.includes("--break")) {
    let missed = 0;
    for (const brk of MUTANTS) {
        const fails = await run(brk);
        console.log(`${fails.length ? "caught " : "MISSED "} ${brk}${fails.length ? ": " + fails[0] : ""}`);
        missed += !fails.length;
    }
    process.exit(missed ? 1 : 0);
}
const fails = await run(null);
for (const f of fails) console.log(`FAIL ${f}`);
console.log(fails.length ? "gem_desk_flip_check: FAILED" : "gem_desk_flip_check: the desk draws into the buffer not on screen and flips only drawn frames, each whole; GEM's arrow is at the pointer in the desk and only there");
process.exit(fails.length ? 1 : 0);
