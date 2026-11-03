// A C program port started the way the machine starts it (apps/ports_headless.mjs): its disk is a DATA
// disk, so the machine boots GEM (docs/demo-gem.wasm) over it; GEM's FLOPPY window lists the FAT, a
// double-click on the program asks the host to run it (request 3), and the host instantiates the FAT
// file, depacked by the ROM, as the next cart with the same disk in the drive. The program's quit is
// request 4: the host brings GEM back over the disk. All of it as docs/sealed-loader.js does (swapCart,
// unpackCart, the FAT listing it hands GEM), on the apps/ports_machine.mjs machine.
import { readFile } from "node:fs/promises";
import { parseDisk } from "../docs/zmdisk.js";
import { startCart, step, picture, sha } from "./ports_machine.mjs";

// GEM's cells in physical-visible coordinates (apps/gem_headless.mjs measured them): the FLOPPY icon,
// and the first file of its window (the FAT sorted by name: BOOT.WSM sorts first on every port disk).
const FLOPPY = [70, 40], FIRST_FILE = [75, 66];
const DBLCLICK = 2; // pointer buttons bit 1: the loader's synthesised double-click
const SETTLE = 6;
// What GEM imports beyond a port's env (retired or unused headlessly): no-ops, as the loader's stubs.
const noop = () => {};
const GEM_EXTRA = { jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop,
    audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop };

let gemBytes = null;

// GEM over the mounted disk: booted, the disk inserted, its FAT listing handed over (the loader's
// diskDirSet), then a few frames. Returns how many FAT files GEM was handed and its cap.
function startGem(m) {
    startCart(m, gemBytes, "docs/demo-gem.wasm", { ...m.env, ...GEM_EXTRA });
    m.demo.insertDisk(1);
    gemFrames(m, SETTLE);
    const files = Object.entries(parseDisk(m.drive.disk, "port").mounted.files);
    const ent = m.rom.deskDirEntryBytes(), max = m.rom.deskDirMaxFiles();
    const shown = files.slice(0, max);
    const dir = new Uint8Array(m.memory.buffer, m.demo.diskDirPtr(), shown.length * ent);
    const dv = new DataView(dir.buffer, dir.byteOffset, dir.byteLength);
    dir.fill(0);
    shown.forEach(([name, f], i) => {
        dir.set(new TextEncoder().encode(name).subarray(0, 16), i * ent);
        dir[i * ent + 16] = f.type & 0xff;
        dv.setUint32(i * ent + 17, f.len >>> 0, true);
    });
    m.demo.setDiskFileCount(shown.length);
    gemFrames(m, SETTLE);
    return { files: files.map(([n]) => n), max };
}

// GEM's frames: the VBL, then the swap protocol's request 3 (run a program), as the loader polls it.
function gemFrames(m, n) {
    for (let i = 0; i < n; i++) {
        step(m);
        if (m.demo.pollCartRequest?.() === 3 && !m.request) {
            m.request = new TextDecoder().decode(new Uint8Array(m.memory.buffer, m.demo.getCartTagPtr(), m.demo.getCartTagLen()));
        }
    }
}
const point = (m, [x, y], b) => { m.demo.pointer(x, y, b); gemFrames(m, 1); };
const open = (m, at) => { point(m, at, 0); point(m, at, DBLCLICK); point(m, at, 0); gemFrames(m, SETTLE); };

// A FAT file as the loader runs it: the ZX0-packed image into the ROM's free RAM, romDepack into the
// cart window, copied out (sealed-loader.js unpackCart).
function depack(m, entry) {
    const u8 = m.drive.disk.subarray(entry.start, entry.start + entry.len);
    if (u8.length > m.machine.hwRomRamFree()) throw new Error(`the program (${u8.length} B packed) does not fit the ROM's free RAM`);
    const src = m.machine.hwRomRamBase() + m.machine.hwRomRamUsed();
    new Uint8Array(m.memory.buffer, src, u8.length).set(u8);
    const n = m.rom.romDepack(src, u8.length, m.machine.hwRamBase(), m.machine.hwRamSize());
    if (!n) throw new Error("the program does not depack (romDepack returned 0)");
    return new Uint8Array(m.memory.buffer.slice(m.machine.hwRamBase(), m.machine.hwRamBase() + n));
}

// Boot GEM over m's disk and run the port's program from it. Returns what the checks need: the FAT and
// GEM's cap, the desktop's picture before anything was touched, the program GEM asked for, and whether
// its depacked bytes are the committed cart's. pullDrive: the drive is emptied before the program starts.
export async function launchFromGem(m, cartPath, pullDrive = false) {
    gemBytes ??= await readFile("docs/demo-gem.wasm");
    const disk = parseDisk(m.drive.disk, cartPath);
    const sector = await bootSector(m, disk);
    const listing = startGem(m);
    const desk = sha(picture(m).px);
    open(m, FLOPPY);
    open(m, FIRST_FILE);
    const name = m.request;
    m.request = null;
    if (!name) throw new Error("GEM never asked to run a program (no request 3 after the double-click)");
    const entry = disk.mounted.files[name];
    if (!entry || entry.type !== 0) throw new Error(`GEM asked for "${name}", which is no program on the disk`);
    const bytes = depack(m, entry);
    const cart = new Uint8Array(await readFile(cartPath));
    const same = bytes.length === cart.length && bytes.every((b, i) => b === cart[i]);
    m.backs = 0;
    if (pullDrive) m.drive.disk = null; // the program starts with an empty drive (a --break)
    startCart(m, bytes, `${name} (from the disk)`);
    return { ...listing, sector, desk, name, same, dataDisk: !disk.bootable || disk.osAfterBoot };
}

// Block 0, run as the loader runs a v2 sector before the OS: it is docs/boot-sdl.wasm (the shared "SDL"
// sector, padded to 1 KB summing to $1234), and it asks for request 2 within MAX_SECTOR frames over a
// descriptor that names no cart, so GEM boots after it (apps/sysinfo_gem_check.mjs checkSector).
const MAX_SECTOR = 600;
async function bootSector(m, disk) {
    const want = new Uint8Array(await readFile("docs/boot-sdl.wasm"));
    const block0 = m.drive.disk.subarray(0, 1024);
    const ours = disk.v2 && disk.bootable && want.every((b, i) => b === block0[i]);
    if (!ours) return { ours, frames: 0, chains: false };
    const bs = new WebAssembly.Instance(new WebAssembly.Module(block0.slice()), { env: { ...m.env, beep: noop } }).exports;
    m.live.demo = bs;
    m.machine.hwInit();
    bs.boot();
    let f = 0;
    for (; f < MAX_SECTOR && bs.pollCartRequest() === 0; f++) {
        m.machine.hwClear();
        bs.frame(1000 / 60);
        for (let p = 0; p < 4; p++) if (!bs.isPlaneEnabled || bs.isPlaneEnabled(p)) m.machine.hwRenderPlane(p);
    }
    return { ours, frames: f, chains: bs.pollCartRequest() === 2 && disk.mounted.chainCart.len === 0 };
}

// After a frame of the program: its request 4 (quit) brings GEM back over the same disk, as the loader.
export function serviceQuit(m) {
    if (m.backs === undefined || m.demo.pollCartRequest?.() !== 4) return;
    m.backs++;
    startGem(m);
}
