// scene_hash.mjs --kos X.zmd|none: KOS's power-on (docs/ZIGTOS_BOOT.md, KOS = ZigTOS), as
// docs/sealed-loader.js runs it and the native host's --kos (fpga/host/kos_host.c) and the
// board firmware (fpga/cycles/bkos.c) reproduce it:
//
//   1. kosSetBoot(cold, or warm: --warm, what will boot, drive A full?, hwRamFree), hwInit,
//      kosPostStart(kosPostFrames(n)): no POST after a warm reset;
//   2. the POST: each frame kosPostFrame(), plane 0 only, until it says done
//      (--post-frames 0: no POST, `post=0` in glass.cfg);
//   3. drive A: a v2 disk whose 1 KB boot sector sums to $1234 runs that sector first (its
//      chainload, request 2, then boots its cart, or the desktop over the disk when the
//      descriptor names no cart: sysinfo); a bootable disk boots its cart; a data disk or an
//      empty drive boots the desktop (the gem shell cart), a data disk with GEM's step
//      (scene_hash_disk.mjs makeDataDisk).
//
// The cart that boots after drive A is the one given to scene_hash.mjs (the native host links
// it): demo-gem.wasm for the desktop, the disk's own cart otherwise, which is checked against
// the disk's bytes. Every phase change happens between frames, before the next hwClear.
import { readFile } from "node:fs/promises";
import { parseDisk } from "../docs/zmdisk.js";
import { makeDataDisk, makeDrive } from "./scene_hash_disk.mjs";

const BOOT_COLD = 0, BOOT_WARM = 1, DEV_DESKTOP = 0, DEV_DRIVE_A = 1, CHAINLOAD = 2;

// unpackCart's depack (sealed-loader.js), so a packed disk cart compares with the given wasm.
function unpack(memory, machine, rom, bytes) {
    const u8 = new Uint8Array(bytes);
    if (u8.length < 10 || String.fromCharCode(...u8.subarray(0, 4)) !== "ZX0!") return u8;
    const src = machine.hwRomRamBase() + machine.hwRomRamUsed();
    new Uint8Array(memory.buffer, src, u8.length).set(u8);
    const n = rom.romDepack(src, u8.length, machine.hwRamBase(), machine.hwRamSize());
    return new Uint8Array(memory.buffer.slice(machine.hwRamBase(), machine.hwRamBase() + n));
}

function sameBytes(a, b) {
    return a.length === b.length && a.every((v, i) => v === b[i]);
}

// What drive A holds: { disk, sector, chain (the cart after the sector, null = the desktop), bootable }.
async function driveA(path) {
    if (path === "none") return { disk: null };
    const d = parseDisk(new Uint8Array(await readFile(path)), path);
    const sector = d.v2 && d.bootable;
    const chain = sector && d.mounted.chainCart.len ? d.mounted.chainCart : null;
    return { disk: d, sector, chain, bootable: d.bootable && (!sector || chain !== null) };
}

// The KOS driver. `instantiate(bytes)` is scene_hash.mjs's (its env, stubs, cart high).
export async function kosBoot({ memory, machine, rom, env, cartBytes, instantiate, drivePath, postFrames, warm }) {
    const a = await driveA(drivePath);
    if (a.disk) env.diskReadBlock = makeDrive(memory, a.disk.mounted);
    rom.kosSetBoot(warm ? BOOT_WARM : BOOT_COLD, a.bootable ? DEV_DRIVE_A : DEV_DESKTOP, a.disk ? 1 : 0, machine.hwRamFree());
    machine.hwInit();
    let phase = "post", cur = null, step = null, next = null;
    postFrames = rom.kosPostFrames(postFrames);
    if (postFrames > 0) rom.kosPostStart(postFrames);
    else next = "drive";

    const bootCart = async (dataDisk) => {
        if (a.bootable && !a.sector) checkCart(a.disk.cart);
        if (a.chain) checkCart(a.disk.mounted.buf.buffer.slice(a.chain.start, a.chain.start + a.chain.len));
        cur = await instantiate(cartBytes);
        machine.hwInit();
        cur.boot();
        cur.skipBoot?.();
        step = dataDisk ? makeDataDisk(memory, rom, a.disk.mounted, false) : null;
        phase = "cart";
    };
    // The depack lands in the cart window, as the browser's does; the window is put back (and the ROM's
    // free RAM the packed bytes went through) so the cart then boots over the bytes the native host's does.
    const checkCart = (bytes) => {
        const win = new Uint8Array(memory.buffer, machine.hwRamBase(), machine.hwRamSize());
        const free = new Uint8Array(memory.buffer, machine.hwRomRamBase() + machine.hwRomRamUsed(), bytes.byteLength);
        const keep = win.slice(), keepFree = free.slice();
        const same = sameBytes(unpack(memory, machine, rom, bytes), new Uint8Array(cartBytes));
        win.set(keep);
        free.set(keepFree);
        if (!same) throw new Error(`--kos ${drivePath}: the cart given is not the disk's`);
    };
    const boot = {
        // drive A, after the POST (sealed-loader.js kosBootDrive)
        drive: async () => {
            if (!a.sector) return bootCart(a.disk && !a.bootable);
            cur = await instantiate(a.disk.cart); // the 1 KB sector, as the browser instantiates it
            machine.hwInit();
            cur.boot();
            phase = "sector";
        },
        // the sector's chainload: its cart, or the desktop over the disk (swapCart req 2 / 4)
        chain: () => bootCart(a.chain === null),
    };

    return {
        // Between frames: the phase change the last frame asked for.
        async between() {
            if (next) await boot[next]();
            next = null;
            rom.kosTick();
        },
        frame(dt) {
            if (phase === "post") {
                if (rom.kosPostFrame()) next = "drive";
            } else if (phase === "sector") {
                cur.frame(dt);
                if (cur.pollCartRequest() === CHAINLOAD) next = "chain";
            } else {
                cur.frame(dt);
                step?.(cur);
            }
        },
        isPlaneEnabled: (p) => (phase === "post" ? p === 0 : cur.isPlaneEnabled(p)),
        current: () => cur,
    };
}
