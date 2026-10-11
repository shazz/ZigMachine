// scene_hash.mjs's disk side, as the browser mounts a disk (docs/sealed-loader.js): the drive
// (--disk) and GEM over a data disk (--data-disk). The parser is the browser's, docs/zmdisk.js.
import { readFile } from "node:fs/promises";
import { parseDisk } from "../docs/zmdisk.js";

// The drive over one mounted disk: the function body is docs/sealed-loader.js's
// diskReadBlock VERBATIM (fpga/tests/test_board_disk.py checks the two texts are
// equal, and the native host's and the board's host/disk.h against it).
export function makeDrive(memory, mountedDisk) {
    function diskReadBlock(block, dstOff) {
        if (!mountedDisk) return 0;
        const start = (block >>> 0) * 512; // the i32 is a u32 block: >= 2^31 is past the end, not from it
        const src = mountedDisk.buf.subarray(start, start + 512);
        if (src.length === 0) return 0;
        new Uint8Array(memory.buffer, dstOff, src.length).set(src);
        return src.length;
    }
    return diskReadBlock;
}

// GEM over a data disk (--data-disk): docs/sealed-loader.js's step after demo.frame(), from
// its cart-request poll to the end of the FAT listing block, VERBATIM
// (fpga/tests/test_board_gemdisk.py checks the texts are equal; the native host's and the
// board's host/disk_app.h are held against this). As in the browser, diskApp is true: GEM was
// booted because the disk is not bootable. swapCart only reports the request: this harness
// cannot swap carts. A request to run a program that is not on the disk fails in the browser
// (no such file, or bytes that are not a program: only a type-0 file is one) and the running
// cart keeps going and polling; any other request swaps the cart, so polling stops.
export function makeDataDisk(memory, rom, mountedDisk) {
    const text_encoder = new TextEncoder();
    const text_decoder = new TextDecoder();
    const diskApp = true;
    let diskDirSet = false, swapping = false, demo;
    const swapCart = (req) => {
        const name = req === 1 || req === 3 ? text_decoder.decode(
            new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen())) : "";
        const found = req === 3 && Object.hasOwn(mountedDisk.files, name) && mountedDisk.files[name].type === 0;
        swapping = req !== 3 || found;
        const where = req !== 3 ? "" : found ? " (on the disk)" : " (not on the disk)";
        console.error(`scene_hash: cart request ${req} "${name}"${where}`);
    };
    return function step(cart) {
        demo = cart;
        if (!swapping && demo.pollCartRequest) {
            const req = demo.pollCartRequest();
            if (req !== 0) swapCart(req);
        }

        // Tell GEM whether an app-disk is inserted (idempotent; takes effect once
        // the cart is booted) so its FLOPPY icon opens the app.
        if (demo.insertDisk) demo.insertDisk(diskApp ? 1 : 0);

        // Hand GEM the mounted disk's FAT directory for its FLOPPY window (once
        // booted): per file a 16-byte name + 1 type byte (0=program, 1=data).
        if (!diskDirSet && diskApp && mountedDisk && demo.diskDirPtr &&
            demo.isBooted && demo.isBooted()) {
            // The record layout and the cap come FROM THE ROM, not from literals
            // here. They used to be `25` and `12` mirrored by hand against
            // desktop.zig, with a comment as the only contract — and the ROM's own
            // clamp had drifted to a THIRD number (/17), which would have admitted
            // 17 records into a 12-record buffer the moment the host stopped
            // capping. Ask, don't mirror.
            const ENT = (rom && rom.deskDirEntryBytes) ? rom.deskDirEntryBytes() : 25;
            const MAXF = (rom && rom.deskDirMaxFiles) ? rom.deskDirMaxFiles() : 12;
            const names = Object.keys(mountedDisk.files).slice(0, MAXF);
            const dir = new Uint8Array(memory.buffer, demo.diskDirPtr(), names.length * ENT);
            dir.fill(0);
            const ddv = new DataView(dir.buffer, dir.byteOffset, dir.byteLength);
            names.forEach((name, i) => {
                dir.set(text_encoder.encode(name).subarray(0, 16), i * ENT);
                dir[i * ENT + 16] = mountedDisk.files[name].type & 0xff;
                ddv.setUint32(i * ENT + 17, (mountedDisk.files[name].len || 0) >>> 0, true); // size
                ddv.setUint32(i * ENT + 21, (mountedDisk.date || 0) >>> 0, true); // date YYYYMMDD
            });
            demo.setDiskFileCount(names.length);
            diskDirSet = true;
        }
    };
}

// --data-disk: the browser's mount (parseDisk), refused unless it is a data disk (the browser
// boots a bootable disk's own cart, not GEM).
export async function mountDataDisk(path) {
    const d = parseDisk(new Uint8Array(await readFile(path)), path);
    if (d.bootable) throw new Error(`${path}: bootable, not a data disk`);
    return d.mounted;
}
