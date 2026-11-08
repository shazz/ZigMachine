// GEM in the desk mode (HW 1.17.0, docs/GEM_DESK_MODE.md §8): ZigGEM over the real machine + ROM,
// driven as the page drives it (gem_headless.mjs's bootGem: one shared memory, the host's
// pointer in PHYSICAL-VISIBLE coordinates, 0..639 x 0..479 in the desk).
//   prefs    Options > Set Preferences has a Desk button; pressing it and OK puts plane 0 in the
//            desk (RESOLUTION 3, hwDeskActive), on a 64-aligned buffer inside the VRAM pool
//   picture  the desk picture (hwRenderDesk's two halves) is the page model of plane 0 (each byte
//            through palette 0, alpha 255): the desktop's colour reaches row 479, the trash
//            sits on the bottom row, and the screen is laid out at 640x480 (menu bar, icons)
//   pointer  a window dragged by its title bar to y 330 lands there: the pointer maps 1:1 in
//            the desk, and the ROM draws past row 200 at stride 640
//   inf      Options > Save Desktop writes DESKTOP.INF with "#E 02" and the window's cells
//   leave    Low + OK leaves the desk (RESOLUTION 0, the same buffer) and the window is clamped
//            into 320x200 (its title bar on row 80), not left out of reach
//   boot     a fresh boot whose disk holds that DESKTOP.INF comes up in the desk, the window
//            where it was saved; on a machine without the mode (hwDeskAvailable 0) the same
//            disk boots low res with the window clamped, and Desk is greyed and does nothing
//   node apps/gem_desk_check.mjs [shots_dir]      node apps/gem_desk_check.mjs --break
//   --break  each mutant must be caught: pointer (the page's old plane mapping, y squeezed to
//            0..199), inf (the boot disk's #E 02 read as 01), nosave (no Save Desktop), older
//            (a machine without the mode that says yes: Desk is not greyed)
import { bootGem } from "./gem_headless.mjs";
import { writePng } from "./scene_png.mjs";

const W = 640, H = 480, HALF = W * (H / 2) * 4;
const REG_RES = 0x00, REG_FB_BASE = 0x44, OFF_PAL = 0x100, OFF_VRAM = 0x1100, VRAM_BYTES = 1 << 20;
const RES_DESK = 3;
const MUTANTS = ["pointer", "inf", "nosave", "older"];
// rom/gem/gui/types.zig: BLACK 0, WHITE 1, MGRAY 3, DESK 5; Prefs' default background
const BLACK = [0, 0, 0], MGRAY = [140, 140, 140], DESK_BG = [1, 160, 164];
const DISK = [{ name: "ALPHA.PRG", type: 0, size: 12345, date: 20260912 }];

// Where Set Preferences' buttons are on a screen (rom/gem/desktop/prefs.zig: a 256x152 box,
// centred; resButton i at hspread over the 3-cell content width, row 13; OK on row 16).
function prefsAt(sw, sh) {
    const dx = (sw - 256) >> 1, dy = (sh - 152) >> 1, x0 = dx + 24, cw = 256 - 48;
    const gap3 = Math.trunc((cw - 3 * 56) / 4), gap2 = Math.trunc((cw - 2 * 64) / 3);
    const res = (i) => [x0 + gap3 * (i + 1) + 56 * i + 28, dy + 13 * 8 + 6];
    return { low: res(0), medium: res(1), desk: res(2), ok: [x0 + gap2 + 32, dy + 16 * 8 + 7], dx, dy };
}

const dv = (gem) => new DataView(gem.memory.buffer, gem.machine.hwVideoBase());
const res = (gem) => dv(gem).getUint8(REG_RES);
const settle = (gem, n = 4) => { for (let i = 0; i < n; i++) gem.frame(); };

// The host's pointer, as sealed-loader.js sends it: the desk's own coordinates there, and the
// `pointer` mutant's plane mapping (the canvas's 560 CSS rows squeezed onto 0..199).
function host(gem, brk, x, y) {
    if (brk === "pointer" && gem.machine.hwDeskActive()) return [x, Math.round(y * 200 / 480)];
    return [x, y];
}
// In low res the host's x is twice the desktop's (the ROM halves it).
const lx = (gem, x) => (res(gem) === 0 ? 2 * x : x);
function click(gem, brk, x, y) { gem.click(...host(gem, brk, lx(gem, x), y)); }
function drag(gem, brk, a, b) { gem.drag(...host(gem, brk, a[0], a[1]), ...host(gem, brk, b[0], b[1]), 8); }

function pickRes(gem, brk, which, sw, sh) {
    click(gem, brk, 180, 8); // Options (the host's x 360 in low res)
    click(gem, brk, 210, 15); // Set Preferences...
    settle(gem);
    const p = prefsAt(sw, sh);
    click(gem, brk, ...p[which]);
    click(gem, brk, ...p.ok);
    settle(gem, 6);
    return p;
}

function deskPicture(gem) {
    const out = new Uint8Array(2 * HALF);
    for (let half = 0; half < 2; half++) {
        gem.machine.hwRenderDesk(half);
        out.set(new Uint8Array(gem.memory.buffer, gem.machine.hwPhysicalPtr(), HALF), half * HALF);
    }
    return out;
}
// The page model: plane 0's bytes at FB_BASE & ~7, stride 640, through palette 0, alpha 255.
function modelOf(gem) {
    const v = dv(gem), base = gem.machine.hwVideoBase() + (v.getUint32(REG_FB_BASE, true) & ~7);
    const plane = new Uint8Array(gem.memory.buffer, base, W * H);
    const out = new Uint8Array(W * H * 4);
    for (let i = 0; i < W * H; i++) {
        const c = v.getUint32(OFF_PAL + plane[i] * 4, true);
        out.set([c & 255, (c >> 8) & 255, (c >> 16) & 255, 255], i * 4);
    }
    return out;
}
const px = (pic, w, x, y) => [pic[(y * w + x) * 4], pic[(y * w + x) * 4 + 1], pic[(y * w + x) * 4 + 2]];
const eq = (a, b) => a.every((v, i) => v === b[i]);
// How much of row y, x0..x1, is in colour c.
function rowShare(pic, w, y, x0, x1, c) {
    let n = 0;
    for (let x = x0; x < x1; x++) n += eq(px(pic, w, x, y), c);
    return n / (x1 - x0);
}
// The low-res raster's visible 320x200 (each logical pixel is two physical ones), as RGBA.
function lowPicture(gem) {
    gem.machine.hwRenderPlane(0);
    const pfb = new Uint8Array(gem.memory.buffer, gem.machine.hwPhysicalPtr(), gem.w * gem.h * 4);
    const out = new Uint8Array(320 * 200 * 4);
    for (let y = 0; y < 200; y++)
        for (let x = 0; x < 320; x++) {
            const s = ((y + gem.by) * gem.w + 2 * x + gem.bx) * 4;
            out.set(pfb.subarray(s, s + 4), (y * 320 + x) * 4);
        }
    return out;
}

// A v1 .zmd (docs/FLOPPY_DISK.md: "ZMDISK" at 0, file count at $2E4, the FAT at $300, 32-byte
// entries) holding DESKTOP.INF at $400, served as the drive serves it (diskReadBlock).
function infDisk(text) {
    const disk = new Uint8Array(0x400 + 512);
    disk.set(new TextEncoder().encode("ZMDISK"), 0);
    new DataView(disk.buffer).setUint16(0x2e4, 1, true);
    disk.set(new TextEncoder().encode("DESKTOP.INF"), 0x300);
    new DataView(disk.buffer).setUint32(0x310, 0x400, true);
    new DataView(disk.buffer).setUint32(0x314, text.length, true);
    disk[0x318] = 1;
    disk.set(text, 0x400);
    return disk;
}
function serveDisk(disk) {
    return (memory) => (block, dst) => {
        const at = block * 512;
        if (at >= disk.length) return 0;
        const n = Math.min(512, disk.length - at);
        new Uint8Array(memory.buffer, dst, n).set(disk.subarray(at, at + n));
        return n;
    };
}

async function shot(dir, name, pic, w, h) {
    if (!dir) return;
    writePng(`${dir}/${name}.png`, pic, w, h);
    console.log(`  shot: ${dir}/${name}.png`);
}

// Session 1: enter the desk from the prefs, check it, drag a window low, save, leave.
async function session(brk, dir, fails) {
    const check = (ok, what) => ok || fails.push(what);
    const gem = await bootGem();
    gem.mount(DISK);
    check(res(gem) === 0, `boot: GEM came up in RESOLUTION ${res(gem)}, not low`);
    const base = await enterDesk(gem, brk, dir, check);
    await windowLow(gem, brk, dir, check);
    const text = saveDesktop(gem, brk, check);
    pickRes(gem, brk, "low", W, H);
    check(!gem.machine.hwDeskActive() && res(gem) === 0, `leave: Low + OK left RESOLUTION ${res(gem)}`);
    check(dv(gem).getUint32(REG_FB_BASE, true) === base, "leave: low res left the desk's buffer");
    const lp = lowPicture(gem);
    check(rowShare(lp, 320, 80, 4, 316, BLACK) > 0.9, "leave: the window was not clamped into 320x200 (no title bar frame on row 80)");
    await shot(dir, "gem-low-after-desk", lp, 320, 200);
    return text;
}

// Set Preferences > Desk > OK: the desk, its buffer, its 640x480 picture. Returns FB_BASE.
async function enterDesk(gem, brk, dir, check) {
    pickRes(gem, brk, "desk", 320, 200);
    check(gem.machine.hwDeskActive() === 1 && res(gem) === RES_DESK, `prefs: Desk + OK left RESOLUTION ${res(gem)}`);
    const base = dv(gem).getUint32(REG_FB_BASE, true);
    check(base % 64 === 0 && base >= OFF_VRAM && base + W * H <= OFF_VRAM + VRAM_BYTES, `prefs: FB_BASE ${base} outside the pool`);
    const pic = deskPicture(gem);
    check(eq(pic, modelOf(gem)), "picture: hwRenderDesk is not plane 0 through palette 0");
    check(eq(px(pic, W, 320, 470), DESK_BG) && eq(px(pic, W, 630, 479), DESK_BG), "picture: the desktop's colour does not reach row 479");
    check(rowShare(pic, W, 10, 0, W, BLACK) > 0.95, "picture: no menu bar line under row 10 across 640");
    let low = 0;
    for (let y = 400; y < H; y++) low += rowShare(pic, W, y, 0, 80, DESK_BG) < 1; // rows the icon or its label reach
    check(low > 20, "picture: no trash icon on the bottom row");
    await shot(dir, "gem-desk", pic, W, H);
    return base;
}

// A:\ opened and dragged by its title bar to y 330: the pointer is 1:1, the ROM draws past row 200.
async function windowLow(gem, brk, dir, check) {
    gem.open(...host(gem, brk, 35, 40)); // FLOPPY: A:\ opens at the cascade's first spot (24, 24)
    settle(gem, 12);
    drag(gem, brk, [200, 30], [300, 336]); // the window moves by (100, 306)
    settle(gem, 6);
    const pic = deskPicture(gem);
    check(eq(pic, modelOf(gem)), "pointer: the picture with a window is not the page model");
    check(rowShare(pic, W, 330, 130, 440, BLACK) > 0.9, "pointer: no window title bar frame on row 330 (x 130..440)");
    check(rowShare(pic, W, 30, 130, 300, DESK_BG) > 0.9, "pointer: the window did not leave y 24");
    await shot(dir, "gem-desk-window", pic, W, H);
}

// Options > Save Desktop in the desk: DESKTOP.INF's text (the ROM's copy), checked.
function saveDesktop(gem, brk, check) {
    if (brk !== "nosave") {
        click(gem, brk, 180, 8); // Options
        click(gem, brk, 210, 31); // Save Desktop
        settle(gem);
    }
    const text = new Uint8Array(gem.memory.buffer, gem.rom.deskInfPtr(), gem.rom.deskInfLen()).slice();
    const inf = new TextDecoder().decode(text);
    check(inf.startsWith("#E 02 01a0a4\r\n"), `inf: DESKTOP.INF does not start "#E 02": ${JSON.stringify(inf.slice(0, 16))}`);
    check(/#W 00 00 15 41 40 15 00 A:\\@\r\n/.test(inf), `inf: no #W for A:\\ at cells (15, 41) 40x15: ${JSON.stringify(inf)}`);
    return text;
}

// Session 2: a boot that finds DESKTOP.INF on its disk.
async function boot(brk, text, available, dir, fails) {
    const check = (ok, what) => ok || fails.push(what);
    const t = brk === "inf" ? new TextEncoder().encode(new TextDecoder().decode(text).replace("#E 02", "#E 01")) : text;
    const gem = await bootGem({ diskReadBlock: serveDisk(infDisk(t)), deskAvailable: brk === "older" ? 1 : available });
    gem.mount(DISK);
    settle(gem, 12);
    if (available) {
        check(gem.machine.hwDeskActive() === 1, `boot: the disk's DESKTOP.INF (#E 02) booted RESOLUTION ${res(gem)}, not the desk`);
        if (!gem.machine.hwDeskActive()) return;
        const pic = deskPicture(gem);
        check(rowShare(pic, W, 328, 126, 436, BLACK) > 0.9, "boot: A:\\ did not reopen where it was saved (cells 15, 41: title bar on row 328)");
        await shot(dir, "gem-desk-boot", pic, W, H);
        return;
    }
    check(res(gem) === 0 && !gem.machine.hwDeskActive(), `older: a machine without the mode booted RESOLUTION ${res(gem)}`);
    const lp = lowPicture(gem);
    check(rowShare(lp, 320, 80, 4, 316, BLACK) > 0.9, "older: the saved window was not clamped into 320x200");
    pickRes(gem, brk, "desk", 320, 200); // Desk is greyed: pressing it and OK changes nothing
    check(res(gem) === 0 && !gem.machine.hwDeskActive(), "older: Desk + OK entered the desk on a machine without it");
    click(gem, brk, 180, 8);
    click(gem, brk, 210, 15);
    settle(gem);
    const p = prefsAt(320, 200), g = lowPicture(gem);
    const frame = (b) => px(g, 320, b[0], p.dy + 13 * 8); // a resolution button's top edge
    check(eq(frame(p.desk), MGRAY) && eq(frame(p.low), BLACK), "older: Desk is not greyed in Set Preferences");
    await shot(dir, "gem-prefs-no-desk", g, 320, 200);
}

async function run(brk, dir) {
    const fails = [];
    const text = await session(brk, dir, fails);
    await boot(brk, text, 1, dir, fails);
    await boot(brk, text, 0, dir, fails);
    return fails;
}

if (process.argv.includes("--break")) {
    let missed = 0;
    for (const brk of MUTANTS) {
        const fails = await run(brk, null);
        console.log(`${fails.length ? "caught " : "MISSED "} ${brk}${fails.length ? ": " + fails[0] : ""}`);
        missed += !fails.length;
    }
    process.exit(missed ? 1 : 0);
}
const fails = await run(null, process.argv[2] || null);
for (const f of fails) console.log(`FAIL ${f}`);
console.log(fails.length ? "gem_desk_check: FAILED" : "gem_desk_check: GEM's Desk button, the 640x480 desktop, the pointer, DESKTOP.INF's #E 02 and the boot back into it all hold");
process.exit(fails.length ? 1 : 0);
