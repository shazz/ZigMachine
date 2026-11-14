// GEM's ITEM SELECTOR (rom/gem/desktop/fsel_tree.zig, TOS 4's layout since GEM 5 S2) as ST Replay
// opens it (TOS 1.02's, prototypes/gem_filesel_re/tos102, was the reference before):
//   - a full 8.3 Selection (DRUMLOOP.RAW) stays clear of DRIVE: (it ran into the frame on the board
//     once, when the TOS 1.02 box was 304 wide);
//   - every one of the nine list rows is drawn: a file as NAME    .EXT (dots in one
//     column), an empty slot as the `________.___` template;
//   - pinned picture hashes for the open selector, a row picked, a short name picked.
// ST Replay runs as GEM launches it off its data disk (scene_hash.mjs --data-disk
// --program); the shipped disk's FAT gets three more names pointing at SAMPLE.RAW's bytes.
//
//   node apps/filesel_check.mjs [--print]      (--print: show the hashes to re-pin)
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { makeDataDisk, makeDrive } from "./scene_hash_disk.mjs";
import { parseDisk } from "../docs/zmdisk.js";
import { fselGeom } from "./fsel_geom.mjs";

// Re-pinned for HW 1.13.0: only ST Replay's "bytes free" figure (top right) moved, the
// cart window being 3 MiB; the selector's pixels are unchanged. Again 9 Nov 2026 (the desk
// branch's ZigOS made ST Replay's wasm bigger): against main's cart, 66 pixels differ, all in
// x 509..530, y 10..16 of the screen, which is that figure; the selector is unchanged. Re-pinned
// 10 Nov 2026 on purpose (GEM 5 S2, G21): the selector is TOS 4's now, on the GEM 5 engine.
// Re-pinned 10 Nov again with the "bytes free" figure masked out of the hash (ST Replay grew by its
// C: loader and moved it a third time); the selector's pixels are unchanged. Re-pinned 14 Nov 2026 on
// purpose (fix/fsel-aes340): the list's rows a font height (8 px) apart as TOS 4 draws them in medium,
// the box 312 x 176 (fsel_geom.zig), no frame round the drive buttons, eyeballed against the reference.
const PINS = {
    open: "950a9d751778572553f545619e69fa6da4cca133bb2cf3cb09d92fac78c2686e",
    drumloop: "b3663d5e8219c48830f057929216a52c2cb6f62ff00367c63ec9f58dc5e68d16",
    short: "9e61129a786266e9834efda9d8a21b63a0919141d0c4c17a8e2eaff6347cf5f1",
};
const NAMES = ["DRUMLOOP.RAW", "A.RAW", "BASSLINE.RAW"];
const G = fselGeom(640, 200);           // fsel_geom.zig's layout, centred in 640 x 200
const DX = G.box.x, DY = G.box.y;
const LIST_X = G.list.x;                 // the list box; a name starts 24 px in (row 8 px in, two blanks)
const FIELD_X = G.sel.x, FIELD_Y = G.sel.y;
const row = (i) => [LIST_X + 80, G.row(i).y + 3];

let failed = 0;
const expect = (ok, what) => { console.log(`  ${ok ? "ok  " : "FAIL"} ${what}`); if (!ok) failed++; };

// The shipped disk, with more names in its v1 FAT ($300, 32-byte entries, count at $2E4).
async function testDisk() {
    const buf = new Uint8Array(await readFile("docs/demo-st_replay.zmd"));
    const dv = new DataView(buf.buffer);
    const n = dv.getUint16(0x2e4, true);
    const src = [...Array(n).keys()].map((i) => 0x300 + i * 32)
        .find((e) => new TextDecoder().decode(buf.subarray(e, e + 10)) === "SAMPLE.RAW");
    if (src === undefined) throw new Error("SAMPLE.RAW is not on docs/demo-st_replay.zmd");
    NAMES.forEach((name, k) => {
        const e = 0x300 + (n + k) * 32;
        buf.copyWithin(e, src, src + 32);
        buf.fill(0, e, e + 16);
        buf.set(new TextEncoder().encode(name), e);
    });
    dv.setUint16(0x2e4, n + NAMES.length, true);
    return parseDisk(buf, "test").mounted;
}

async function boot() {
    const memory = new WebAssembly.Memory({ initial: 128, maximum: 128 });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) } })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw") && !(k in env)) env[k] = machine[k];
    const mounted = await testDisk();
    env.diskReadBlock = makeDrive(memory, mounted);
    const bytes = await readFile("docs/demo-st_replay.wasm");
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(bytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => 0;
    demo = (await WebAssembly.instantiate(bytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(bytes).high ?? 0);
    machine.hwInit(); demo.boot(); demo.skipBoot?.();
    const step = makeDataDisk(memory, rom, mounted, true);
    const W = machine.hwPhysWidth(), H = machine.hwPhysHeight(), bx = machine.hwBorderX(), by = machine.hwBorderY();
    const comp = new Uint32Array(W * H);
    const frame = () => {
        machine.hwClear(); demo.frame(16.6); step(demo);
        comp.fill(0);
        for (let p = 0; p < machine.hwPlanesNumber(); p++) {
            if (!demo.isPlaneEnabled(p)) continue;
            machine.hwRenderPlane(p);
            const s = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), W * H);
            for (let i = 0; i < s.length; i++) if (s[i] >>> 24) comp[i] = s[i];
        }
    };
    const px = (x, y) => comp[(y + by) * W + x + bx];
    // The "bytes free" figure (x 480..560, y 8..18) left out: it moves with the cart's size, not the selector.
    const hash = () => {
        const c = comp.slice();
        for (let y = 8; y <= 18; y++) c.fill(0, (y + by) * W + 480 + bx, (y + by) * W + 560 + bx);
        return createHash("sha256").update(new Uint8Array(c.buffer)).digest("hex");
    };
    const click = (x, y) => { for (const b of [0, 1, 0]) { demo.pointer(x, y, b); frame(); } frame(); };
    return { demo, frame, px, hash, click, refused: () => machine.hwRamAllocFailures() };
}

// Ink per 8 px cell of one pixel row: '#' where the cell has any pixel of `ink`.
function cells(m, x, y, n, ink) {
    let s = "";
    for (let c = 0; c < n; c++) {
        let any = false;
        for (let k = 0; k < 8; k++) any ||= m.px(x + c * 8 + k, y) === ink;
        s += any ? "#" : ".";
    }
    return s;
}

// The same over the glyph rows y0..y1 (above the underscore line): '#' where a cell has ink.
function cellsIn(m, x, y0, y1, n, ink) {
    let s = "";
    for (let c = 0; c < n; c++) {
        let any = false;
        for (let y = y0; y <= y1; y++) any ||= cells(m, x + c * 8, y, 1, ink) === "#";
        s += any ? "#" : ".";
    }
    return s;
}

const m = await boot();
for (let i = 0; i < 20; i++) m.frame();
m.demo.key(0x6c); // 'l': Load from disc
for (let i = 0; i < 4; i++) m.frame();
const ink = m.px(DX, DY + 10), paper = m.px(DX + 4, DY + 10); // the box frame / its inside
const got = { open: m.hash() };

// The empty rows: the template's underscores run along the row's 7th pixel row (y + 6) in all
// 12 cells (the dot's foot is in cell 8 there too); one row up only the dot has ink. A file row
// has no underscore line at all.
for (let i = 4; i < 9; i++) {
    const y = row(i)[1] + 3; // = the row's top + 6
    expect(cells(m, LIST_X + 24, y, 12, ink) === "############" && cells(m, LIST_X + 24, y - 1, 12, ink) === "........#...",
        `empty row ${i + 1} shows ________.___`);
}
expect(cells(m, LIST_X + 24, row(0)[1] + 3, 12, ink) !== "############", "a file row has no underscores");

m.click(...row(1)); // DRUMLOOP.RAW (FAT order: SAMPLE, DRUMLOOP, A, BASSLINE)
got.drumloop = m.hash();
let past = 0; // between the field's last cell and the box's inner frame, on the field's rows
for (let y = FIELD_Y - 1; y < FIELD_Y + 8; y++)
    for (let x = FIELD_X + 96 + 2; x < DX + 224; x++) if (m.px(x, y) !== paper) past++; // up to DRIVE:
expect(past === 0, `DRUMLOOP.RAW ends inside the frame (${past} pixels past the field)`);
expect(cellsIn(m, FIELD_X, FIELD_Y, FIELD_Y + 5, 12, ink) === "############", "the Selection shows all 12 cells of DRUMLOOP.RAW");
expect(cells(m, LIST_X + 24, row(1)[1] + 3, 12, paper) === "############", "the picked row is drawn in inverse");

m.click(...row(2)); // A.RAW: listed as A       .RAW
got.short = m.hash();
expect(cells(m, LIST_X + 24, row(2)[1] + 3, 12, paper) === "#.......####", "A.RAW is listed as A       .RAW");

for (const [k, h] of Object.entries(got)) {
    if (process.argv.includes("--print")) console.log(`    ${k}: "${h}",`);
    else expect(h === PINS[k], `${k}: picture ${h.slice(0, 16)} is the pinned ${PINS[k].slice(0, 16)}`);
}
expect(m.refused() === 0, "no zg.mem allocation refused");
if (failed) { console.log(`filesel_check: ${failed} FAILED`); process.exit(1); }
console.log("filesel_check: the ITEM SELECTOR is TOS's");
