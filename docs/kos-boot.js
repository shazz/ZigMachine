// --------------------------------------------------------------------------
// KOS, the KESTREL Operating System: the browser's power-on (docs/ZIGTOS_BOOT.md, where
// "ZigTOS" is KOS). docs/sealed-loader.js's boot() uses it when the page powers on with a
// disk in drive A (?disk=X.zmd, or a TV channel's disk) or none (?disk=none):
//
//   1. kosSetBoot(cold, or warm with ?warm=1, what will boot, drive A full?, hwRamFree), hwInit;
//   2. the POST: rom.wasm draws it on plane 0 (rom/kos/kos.zig) for ?post=N frames
//      (default 180; ?post=0: none; none after a warm reset: kosPostFrames), any key skips the rest;
//   3. request KOS_BOOT_DRIVE: the loader's swapCart boots drive A: the disk's boot sector
//      or cart, or the desktop (demo-gem.wasm) over a data disk or an empty drive.
//
// The same steps run in node (apps/scene_hash_kos.mjs), the native host (fpga/host/kos_host.c)
// and the board firmware (fpga/cycles/bkos.c), which agree frame for frame.
// --------------------------------------------------------------------------
globalThis.ZMKos = (function () {
    const BOOT_COLD = 0, BOOT_WARM = 1, DEV_DESKTOP = 0, DEV_DRIVE_A = 1;
    const POST_FRAMES = 180; // rom/kos/kos.zig POST_FRAMES
    const BOOT_DRIVE = 5;    // the POST's request: boot drive A (sealed-loader.js swapCart)

    // What drive A will boot: its cart (a bootable disk, or one whose executable boot sector
    // chainloads a cart) or the desktop (a data disk, a sector that hands over to the OS, none).
    function bootsCart(drive, mounted) {
        if (!drive || !drive.bootable) return false;
        return !(drive.v2 && mounted && mounted.chainCart && mounted.chainCart.len === 0);
    }

    // The POST as the running "cart" until it ends: plane 0 only, no HBL handler, no exports
    // beyond what the loader's frame and input handlers call.
    function postCart(rom, frames) {
        let done = false;
        rom.kosPostStart(frames);
        const skip = () => { done = true; };
        return {
            frame() { if (!done) done = rom.kosPostFrame() !== 0; },
            isPlaneEnabled: (p) => p === 0,
            pollCartRequest: () => (done ? BOOT_DRIVE : 0),
            hblDispatch() {},
            ownsKeyboard: () => 0,
            key: skip, // a key held at power-on skips the POST, as on the ST
            input: skip,
        };
    }

    // Stage 1: the reset's system variables, then the hardware's.
    function power(rom, machine, drive, mounted, warm) {
        rom.kosSetBoot(warm ? BOOT_WARM : BOOT_COLD, bootsCart(drive, mounted) ? DEV_DRIVE_A : DEV_DESKTOP, drive ? 1 : 0, machine.hwRamFree());
        machine.hwInit();
    }

    // ?post=N: the POST's frames (0 = none); anything else is the default. The ROM has the last
    // word: no POST after a warm reset (rom/kos/kos.zig kosPostFrames).
    function postFrames(params, rom) {
        const n = Number(params.get("post"));
        const asked = params.has("post") && Number.isInteger(n) && n >= 0 ? n : POST_FRAMES;
        return rom.kosPostFrames ? rom.kosPostFrames(asked) : asked;
    }

    // A raw FAT disk image (an .ST, a dumped floppy: docs/KOS_FAT.md): whole 512-byte sectors and a
    // BPB saying 512 bytes a sector. The drive serves it as any disk; the desktop shell reads its FAT.
    function fatImage(buf) {
        if (buf.length < 4096 || buf.length % 512 !== 0 || (buf[11] | buf[12] << 8) !== 512) return null;
        return { buf, files: {}, fat: true };
    }

    // A FAT12/16 floppy's file by its 8.3 name, the first found breadth first (the desktop's own
    // listing order, apps/zig/scenes/gem_fat.zig); its bytes, or null. A program GEM launches
    // off a real floppy (request 3): the browser reads it here, the board's glass with
    // rom/kos/fat.zig. Floppies only (FAT32 is C:, not drive A).
    function fatFile(b, name) {
        const u16 = (o) => b[o] | b[o + 1] << 8, u32 = (o) => (u16(o) | u16(o + 2) << 16) >>> 0;
        const spc = b[13], fat0 = u16(14), fats = b[16], rootN = u16(17), fatsz = u16(22);
        const total = u16(19) || u32(32), root0 = fat0 + fats * fatsz, data0 = root0 + ((rootN * 32 + 511) >> 9);
        const clusters = Math.floor((total - data0) / spc), fat12 = clusters < 4085;
        const next = (c) => {
            const o = fat0 * 512 + (fat12 ? c + (c >> 1) : c * 2), w = u16(o);
            const n = fat12 ? (c & 1 ? w >> 4 : w & 0xfff) : w;
            return n >= (fat12 ? 0xff8 : 0xfff8) || n < 2 || n > clusters + 1 ? 0 : n;
        };
        const chain = (c, limit) => { const out = []; while (c && out.length <= clusters && out.length < limit) { out.push(c); c = next(c); } return out; };
        const secs = (c) => Array.from({ length: spc }, (_, k) => data0 + (c - 2) * spc + k);
        const entries = (sectors) => sectors.flatMap((s) => Array.from({ length: 16 }, (_, k) => s * 512 + k * 32));
        const text = (o, n) => String.fromCharCode(...b.subarray(o, o + n)).trimEnd();
        let dirs = [Array.from({ length: (rootN * 32 + 511) >> 9 }, (_, k) => root0 + k)];
        while (dirs.length) {
            const subs = [];
            for (const sectors of dirs) for (const e of entries(sectors)) {
                if (b[e] === 0 || b[e] === 0xe5 || b[e] === 0x2e || b[e + 11] === 0x0f || b[e + 11] & 8) continue;
                const nm = text(e, 8) + (text(e + 8, 3) ? "." + text(e + 8, 3) : ""), first = u16(e + 26);
                if (b[e + 11] & 0x10) { subs.push(chain(first, 1e9).flatMap(secs)); continue; }
                if (nm !== name) continue;
                const size = u32(e + 28), out = new Uint8Array(size);
                let at = 0;
                for (const c of chain(first, Math.ceil(size / (spc * 512)))) for (const s of secs(c)) {
                    const k = Math.min(512, size - at);
                    if (k > 0) out.set(b.subarray(s * 512, s * 512 + k), at);
                    at += k;
                }
                return at >= size ? out : null;
            }
            dirs = subs;
        }
        return null;
    }

    return { BOOT_DRIVE, bootsCart, fatFile, fatImage, postCart, power, postFrames };
})();
